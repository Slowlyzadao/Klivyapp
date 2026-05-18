<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import AttachmentPreviewList from './AttachmentPreviewList.vue';
import AudioRecorder from './AudioRecorder.vue';
import MentionPopover from './MentionPopover.vue';
import ReplyPreview from './ReplyPreview.vue';
import StickerPicker from './StickerPicker.vue';
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
  if (isSending.value) return;
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
  }
};

const sendSticker = async sticker => {
  if (!sticker?.id || isSending.value) return;
  showStickerPicker.value = false;
  try {
    await store.dispatch('internalChatMessages/send', {
      roomId: props.roomId,
      stickerId: sticker.id,
    });
    emit('sent');
  } catch {
    error.value = 'Falha ao enviar figurinha';
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

const autoGrow = e => {
  const el = e.target;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 160)}px`;
};
</script>

<template>
  <div
    class="relative px-4 py-3 border-t border-n-weak bg-n-solid-1"
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

    <div class="flex items-end gap-2">
      <button
        type="button"
        class="inline-flex items-center justify-center w-10 h-10 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition shrink-0"
        title="Anexar arquivo"
        @click="fileInputRef.click()"
      >
        <span class="i-lucide-paperclip text-lg" />
      </button>
      <input
        ref="fileInputRef"
        type="file"
        multiple
        class="hidden"
        @change="onFileChange"
      >

      <AudioRecorder
        @ready="onAudioReady"
        @error="onAudioError"
      />

      <button
        type="button"
        class="inline-flex items-center justify-center w-10 h-10 rounded-md transition shrink-0"
        :class="
          showStickerPicker
            ? 'bg-n-alpha-2 text-n-slate-12'
            : 'text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12'
        "
        title="Figurinhas"
        @click="showStickerPicker = !showStickerPicker"
      >
        <span class="i-lucide-sticker text-lg" />
      </button>

      <textarea
        ref="textareaRef"
        v-model="text"
        rows="1"
        placeholder="Escreva uma mensagem... (use @ para mencionar)"
        class="flex-1 resize-none px-3 py-2 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand max-h-[160px]"
        @keydown="handleKeydown"
        @input="onInput"
      />
      <button
        type="button"
        class="inline-flex items-center justify-center w-10 h-10 rounded-md bg-n-brand text-white transition disabled:opacity-50 disabled:cursor-not-allowed hover:brightness-110 shrink-0"
        :disabled="!hasContent || isSending"
        @click="send()"
      >
        <span class="i-lucide-send text-lg" />
      </button>
    </div>
  </div>
</template>
