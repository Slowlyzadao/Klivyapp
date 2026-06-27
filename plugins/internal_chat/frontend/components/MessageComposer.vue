<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import AttachmentPreviewList from './AttachmentPreviewList.vue';
import AudioRecorder from './AudioRecorder.vue';
import MentionPopover from './MentionPopover.vue';
import ReplyPreview from './ReplyPreview.vue';
import StickerPicker from './StickerPicker.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import { useMentionAutocomplete } from '@plugins/internal_chat/frontend/composables/useMentionAutocomplete';
import { useTypingIndicator } from '@plugins/internal_chat/frontend/composables/useTypingIndicator';

const props = defineProps({
  roomId: { type: Number, required: true },
  members: { type: Array, default: () => [] },
  replyTarget: { type: Object, default: null },
});
const emit = defineEmits(['cancel-reply', 'sent']);

const MAX_SIZE_MB = 40;
const MAX_FILES = 10;

const store = useStore();
const text = ref('');
const files = ref([]);
const dragOver = ref(false);
const error = ref('');
const textareaRef = ref(null);
const fileInputRef = ref(null);
const showStickerPicker = ref(false);

const currentUserId = computed(() => store.getters.getCurrentUserID);
const candidates = computed(() => {
  // Inclui humanos da sala (exceto o próprio) + a Bea quando for membro.
  const humans = [];
  const ais = [];
  for (const m of props.members || []) {
    if (m.is_ai && m.ai_agent_id) {
      ais.push({
        id: m.ai_agent_id,
        name: 'Beatriz · IA',
        avatar_url: m.avatar_url,
        is_ai: true,
      });
    } else if (m.user_id && m.user_id !== currentUserId.value) {
      humans.push({
        id: m.user_id,
        name: m.name || 'Usuário',
        avatar_url: m.avatar_url,
        is_ai: false,
      });
    }
  }

  // Ordem do popover: @todos primeiro (quando 2+ humanos), depois IAs
  // (Bea), depois humanos. IAs vêm acima dos humanos pra que a Bea apareça
  // sempre nos primeiros candidatos visíveis (popover faz slice de 8).
  const list = [];
  if (humans.length >= 2) {
    list.push({
      id: 'all',
      name: 'Todos',
      description: `Notificar ${humans.length} membros`,
      is_all: true,
    });
  }
  return [...list, ...ais, ...humans];
});

const typing = useTypingIndicator(() => props.roomId);

const mention = useMentionAutocomplete({
  candidatesRef: candidates,
  getValue: () => text.value,
  getCaret: () => textareaRef.value?.selectionStart ?? text.value.length,
  applyReplacement: (next, caret) => {
    text.value = next;
    setTimeout(() => {
      if (!textareaRef.value) return;
      textareaRef.value.focus();
      textareaRef.value.setSelectionRange(caret, caret);
      autoGrow({ target: textareaRef.value });
    }, 0);
  },
});

const isSending = computed(
  () => store.getters['internalChatMessages/getUIFlags'].isSending
);
// FE-13 (auditoria 2026-05-18): flag local sync usada como mutex no
// `send`/`sendSticker`. O getter `isSending` do store só vira true APÓS
// o dispatch ser processado — janela de microtarefas permite re-entry
// (user pressionando Enter 2x rápido, double click). `localSending` é
// setado synchronously antes de qualquer await pra fechar a brecha.
const localSending = ref(false);

const hasContent = computed(
  () => text.value.trim().length > 0 || files.value.length > 0
);

const validateAndAdd = list => {
  error.value = '';
  const next = [...files.value];
  for (const f of list) {
    if (next.length >= MAX_FILES) {
      error.value = `Máximo ${MAX_FILES} arquivos por mensagem`;
      break;
    }
    if (f.size > MAX_SIZE_MB * 1024 * 1024) {
      error.value = `${f.name} excede ${MAX_SIZE_MB} MB`;
      continue;
    }
    next.push(f);
  }
  files.value = next;
};

const onFileChange = e => {
  validateAndAdd(Array.from(e.target.files || []));
  e.target.value = '';
};
const removeFile = idx => {
  files.value = files.value.filter((_, i) => i !== idx);
};
const onDrop = e => {
  e.preventDefault();
  dragOver.value = false;
  validateAndAdd(Array.from(e.dataTransfer.files || []));
};

const send = async ({ extraFiles = [] } = {}) => {
  const allFiles = [...files.value, ...extraFiles];
  if (text.value.trim().length === 0 && allFiles.length === 0) return;
  // FE-13: mutex sync (`localSending`) ANTES de qualquer await — fecha
  // a brecha entre Enter duplicado e o store atualizar `isSending`.
  if (isSending.value || localSending.value) return;
  localSending.value = true;
  try {
    const contentAttributes = {};
    if (props.replyTarget?._is_snapshot) {
      // "Responder no particular" — origem está em outra sala, salva snapshot
      // do quote pra renderizar a citação sem precisar resolver in_reply_to.
      contentAttributes.quoted_message = props.replyTarget;
    } else if (props.replyTarget?.id) {
      contentAttributes.in_reply_to = props.replyTarget.id;
    }
    const mentioned = mention.collectInsertedIds();
    if (mentioned.userIds?.length) contentAttributes.mentioned_user_ids = mentioned.userIds;
    if (mentioned.aiAgentIds?.length) contentAttributes.mentioned_ai_agent_ids = mentioned.aiAgentIds;

    await store.dispatch('internalChatMessages/send', {
      roomId: props.roomId,
      content: text.value.trim(),
      contentAttributes,
      files: allFiles,
    });
    text.value = '';
    files.value = [];
    error.value = '';
    mention.reset();
    typing.stopNow();
    emit('sent');
    textareaRef.value?.focus();
  } catch (e) {
    error.value = 'Falha ao enviar mensagem';
  } finally {
    localSending.value = false;
  }
};

const sendSticker = async sticker => {
  if (!sticker?.id || isSending.value || localSending.value) return;
  localSending.value = true;
  showStickerPicker.value = false;
  try {
    await store.dispatch('internalChatMessages/send', {
      roomId: props.roomId,
      stickerId: sticker.id,
    });
    emit('sent');
  } catch {
    error.value = 'Falha ao enviar figurinha';
  } finally {
    localSending.value = false;
  }
};

const onAudioReady = file => send({ extraFiles: [file] });
const onAudioError = msg => { error.value = msg; };

const handleKeydown = e => {
  if (mention.handleKeydown(e)) return;
  if (e.key === 'Escape' && props.replyTarget) {
    e.preventDefault();
    emit('cancel-reply');
    return;
  }
  if (e.key === 'Enter' && !e.shiftKey) {
    e.preventDefault();
    send();
  }
};

const onInput = e => {
  autoGrow(e);
  mention.evaluate();
  if (text.value.trim().length > 0) typing.onKeystroke();
  else typing.stopNow();
};

// UX-fix 2026-05-20: respeita `min-height: 32px` do CSS pra não saltar
// quando user digita o 1º caractere (scrollHeight pulava entre limites).
const autoGrow = e => {
  const el = e.target;
  el.style.height = 'auto';
  const sh = el.scrollHeight;
  // Só seta altura inline quando passa do mínimo (multi-linha).
  if (sh > 36) {
    el.style.height = `${Math.min(sh, 160)}px`;
  }
};
</script>

<template>
  <!-- UX-fix 2026-05-20: container externo sem border-top + sem bg
       sólido próprio (era `border-t border-n-weak bg-n-solid-1`) — o
       composer agora flutua sobre o pattern de fundo do MessageThread,
       padrão WhatsApp/Telegram (sem chrome separador). -->
  <div
    class="relative px-4 py-2"
    :class="dragOver ? 'ring-2 ring-n-brand ring-inset' : ''"
    @dragover.prevent="dragOver = true"
    @dragleave="dragOver = false"
    @drop="onDrop"
  >
    <p
      v-if="error"
      class="px-1 mb-1 text-xs text-n-ruby-11"
    >
      {{ error }}
    </p>

    <ReplyPreview
      v-if="replyTarget"
      :message="replyTarget"
      @close="emit('cancel-reply')"
    />

    <AttachmentPreviewList
      :files="files"
      @remove="removeFile"
    />

    <MentionPopover
      v-if="mention.isOpen.value"
      :candidates="mention.filteredCandidates.value"
      :highlighted-index="mention.highlightedIndex.value"
      @select="mention.selectCandidate"
      @hover="idx => (mention.highlightedIndex.value = idx)"
    />

    <StickerPicker
      v-if="showStickerPicker"
      @select="sendSticker"
      @close="showStickerPicker = false"
    />

    <!-- UX-fix 2026-05-20 (refinamento WhatsApp final):
         - Wrapper input em cápsula `bg-n-solid-1 shadow-sm` (visível
           flutuando sobre o pattern do thread, sem border-top)
         - TODOS os controles DENTRO do wrapper: sticker + anexo à
           esquerda, áudio + send à direita
         - SEM focus-within ring (feedback de foco é o cursor piscando)
         - Send no canto direito SEMPRE visível (mantém affordance —
           user clica direto sem pensar) -->
    <!-- UX-fix 2026-05-20: altura wrapper 52px (padrão WA mobile) com
         ícones w-10 h-10 + text-xl pra serem confortáveis ao toque. -->
    <div
      class="flex items-center gap-1 min-w-0 min-h-[52px] pl-1.5 pr-2 rounded-full bg-n-solid-1 shadow-sm transition-colors"
    >
      <Tooltip label="Figurinhas" position="top">
        <button
          type="button"
          class="inline-flex items-center justify-center w-10 h-10 rounded-full transition shrink-0"
          :class="
            showStickerPicker
              ? 'bg-n-alpha-2 text-n-slate-12'
              : 'text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12'
          "
          @click="showStickerPicker = !showStickerPicker"
        >
          <span class="i-lucide-smile text-xl" />
        </button>
      </Tooltip>

      <Tooltip label="Anexar arquivo" position="top">
        <button
          type="button"
          class="inline-flex items-center justify-center w-10 h-10 rounded-full text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition shrink-0"
          @click="fileInputRef.click()"
        >
          <span class="i-lucide-paperclip text-xl" />
        </button>
      </Tooltip>
      <input
        ref="fileInputRef"
        type="file"
        multiple
        class="hidden"
        @change="onFileChange"
      >

      <!-- Classe `ic-composer-textarea` no `<style scoped>` abaixo sobrescreve
           o estilo global de `textarea { @apply field-base h-16 }` que vem
           de `app/javascript/dashboard/assets/scss/_base.scss:112`. Sem
           isso o textarea ganha: outline cinza/azul ao focar, altura
           mínima 64px, fundo `bg-n-alpha-black2`, rounded-lg — visual
           agressivo que não combina com o composer WhatsApp-style. -->
      <textarea
        ref="textareaRef"
        v-model="text"
        rows="1"
        :placeholder="$t('INTERNAL_CHAT.MESSAGE.COMPOSER_PLACEHOLDER')"
        class="ic-composer-textarea flex-1 min-w-0 resize-none text-sm text-n-slate-12 placeholder:text-n-slate-10 max-h-[160px] leading-snug"
        @keydown="handleKeydown"
        @input="onInput"
      />

      <!-- Padrão WhatsApp clássico: send E mic ocupam o MESMO slot
           à direita do textarea.
           - Sem conteúdo + idle: mic visível (user pode gravar áudio)
           - Com conteúdo: send visível (mic some)
           - Recording/preview: AudioRecorder controla a UI inteira
             (expandido), mesmo se o user começou a digitar antes —
             priorizar gravação em andamento sobre toggle pra send. -->
      <Tooltip
        v-if="hasContent"
        label="Enviar mensagem"
        position="top"
      >
        <button
          type="button"
          class="inline-flex items-center justify-center w-10 h-10 rounded-full bg-n-brand text-white shrink-0 transition hover:brightness-110 active:scale-95 disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="isSending || localSending"
          @click="send()"
        >
          <span class="i-lucide-send text-lg" />
        </button>
      </Tooltip>
      <AudioRecorder
        v-else
        @ready="onAudioReady"
        @error="onAudioError"
      />
    </div>
  </div>
</template>

<style scoped>
/* UX-fix 2026-05-20: sobrescreve estilo global de `textarea` aplicado
   por `app/javascript/dashboard/assets/scss/_base.scss:112` que faz
   `@apply field-base h-16` em TODO textarea — força outline cinza/azul,
   altura mínima 64px e bg-n-alpha-black2. Sem esse reset o composer
   WhatsApp-style fica com chrome agressivo no foco. `!important` é
   cirúrgico contra reset externo (pattern documentado em AGENTS.md
   e na memória feedback_bug_visual_recorrente_estrutural). */
.ic-composer-textarea {
  background: transparent !important;
  outline: none !important;
  border: none !important;
  border-radius: 0 !important;
  height: auto !important;
  min-height: 32px;
  padding: 6px 8px;
  box-shadow: none !important;
}
.ic-composer-textarea:focus,
.ic-composer-textarea:hover {
  outline: none !important;
  background: transparent !important;
  box-shadow: none !important;
}
</style>
