<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
// Toast feedback padrão do Chatwoot — `useAlert` empilha mensagens no canto
// inferior direito com timeout. Mesma fonte usada pelos templates da Bea.
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// FE-8: BeclinicButton no preview-modal de sticker (Salvar/Remover/Fechar).
// Chevrons (em Tooltip), inline edit buttons (text-[11px] minúsculo), e
// reaction-bar interna ficam nativos por terem visual contextual ao bubble.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import MessageAttachments from './MessageAttachments.vue';
import ReplyPreview from './ReplyPreview.vue';
// FE-1 (auditoria 2026-05-19): partes display-only do bubble extraídas pra
// reduzir LOC do god component. State crítico (showActionsMenu, edição
// inline FE-20, sticker actions FE-14) PERMANECE aqui no pai — só blocos
// puramente visuais foram movidos.
import ReadReceiptIcon from './messageBubbleParts/ReadReceiptIcon.vue';
import ReactionsBar from './messageBubbleParts/ReactionsBar.vue';
import MessageActionsMenu from './messageBubbleParts/MessageActionsMenu.vue';

const props = defineProps({
  message: { type: Object, required: true },
  isOwn: { type: Boolean, default: false },
});

const store = useStore();
const route = useRoute();
const router = useRouter();
const { t } = useI18n();
const currentUserId = computed(() => store.getters.getCurrentUserID);

// Paleta de pastéis pra label do nome do remetente em grupo (estilo WhatsApp).
// Cor é determinística pelo user_id — mesmo user sempre pega a mesma cor.
// Tons foram escolhidos pra contrastar com o fundo SVG (pattern verde-claro)
// tanto em light quanto em dark mode.
const NAME_COLORS = [
  { bg: '#FECACA', text: '#991B1B' }, // red
  { bg: '#FED7AA', text: '#9A3412' }, // orange
  { bg: '#FDE68A', text: '#92400E' }, // amber
  { bg: '#D9F99D', text: '#3F6212' }, // lime
  { bg: '#A7F3D0', text: '#065F46' }, // emerald
  { bg: '#A5F3FC', text: '#155E75' }, // cyan
  { bg: '#BAE6FD', text: '#075985' }, // sky
  { bg: '#C7D2FE', text: '#3730A3' }, // indigo
  { bg: '#DDD6FE', text: '#5B21B6' }, // violet
  { bg: '#E9D5FF', text: '#6B21A8' }, // purple
  { bg: '#F5D0FE', text: '#86198F' }, // fuchsia
  { bg: '#FBCFE8', text: '#9D174D' }, // pink
];
const colorForUser = id => {
  const idx = (Number(id) || 0) % NAME_COLORS.length;
  return NAME_COLORS[idx];
};

// Detecta se a mensagem tá num grupo (vs DM) — só grupo mostra label colorida
// do nome (em DM os dois interlocutores já se conhecem).
const messageRoom = computed(() =>
  store.getters['internalChatRooms/getRoomById'](props.message.room_id)
);
const isInGroup = computed(() => messageRoom.value?.kind === 'group');
const senderColor = computed(() =>
  colorForUser(props.message.sender?.id)
);
const maxOthersRead = computed(() =>
  store.getters['internalChatRooms/getMaxOthersRead'](
    props.message.room_id,
    currentUserId.value
  )
);
const isRead = computed(() => maxOthersRead.value >= props.message.id);
const emit = defineEmits(['reply', 'jump-to-reply']);

const showStickerPreview = ref(false);
// FE-14 (auditoria 2026-05-18): `stickerActionPending` migrado pra store
// global (`internalChatStickers/isStickerPending`). Antes era per-instance
// — user clicando save no bubble A + remove no bubble B do MESMO sticker
// disparava 2 requests concorrentes com state divergente.
const stickerActionPending = computed(() => {
  const id = props.message.sticker?.id;
  if (!id) return false;
  return store.getters['internalChatStickers/isStickerPending'](id);
});
const stickerActionMsg = ref('');

// Sticker está na coleção do user atual?
const stickerInCollection = computed(() => {
  if (!props.message.sticker?.id) return false;
  return Boolean(
    store.getters['internalChatStickers/getById'](props.message.sticker.id)
  );
});
// Default da Klivy: visível pra todos, não dá pra salvar/remover.
const stickerIsDefault = computed(() => {
  const s = store.getters['internalChatStickers/getById'](
    props.message.sticker?.id
  );
  return Boolean(s?.is_default);
});

const openStickerPreview = () => {
  if (!props.message.sticker?.id) return;
  stickerActionMsg.value = '';
  showStickerPreview.value = true;
};

// FE-14: setters de pending agora vivem no store (commit SET_PENDING
// dentro das actions). Bubble só dispatcha; `stickerActionPending`
// é getter reativo.
const saveSticker = async () => {
  if (stickerActionPending.value) return;
  stickerActionMsg.value = '';
  try {
    await store.dispatch(
      'internalChatStickers/favoriteAndCacheById',
      props.message.sticker.id
    );
    stickerActionMsg.value = 'Figurinha salva nas suas favoritas.';
  } catch {
    stickerActionMsg.value = 'Falha ao salvar.';
  }
};

const removeSticker = async () => {
  if (stickerActionPending.value) return;
  if (!confirm('Remover esta figurinha das suas favoritas?')) return;
  stickerActionMsg.value = '';
  try {
    await store.dispatch(
      'internalChatStickers/toggleFavorite',
      props.message.sticker.id
    );
    stickerActionMsg.value = 'Figurinha removida.';
  } catch {
    stickerActionMsg.value = 'Falha ao remover.';
  }
};

const time = computed(() => {
  const d = new Date(props.message.created_at);
  return d.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
  });
});

const isDeleted = computed(() => Boolean(props.message.deleted_at));
const isSystem = computed(() => props.message.content_type === 'system');
const senderName = computed(() => props.message.sender?.name || 'Sistema');
const isAiSender = computed(() => Boolean(props.message.sender?.is_ai));
const hasAttachments = computed(
  () => Array.isArray(props.message.attachments) && props.message.attachments.length > 0
);
const repliedMessage = computed(() => props.message.in_reply_to_message);
const sticker = computed(() => props.message.sticker);
const isSticker = computed(
  () =>
    props.message.content_type === 'sticker' &&
    !isDeleted.value &&
    sticker.value?.image_url
);
// Mensagem que era sticker mas o sticker foi removido por todos (cascade).
const isOrphanSticker = computed(
  () =>
    props.message.content_type === 'sticker' &&
    !isDeleted.value &&
    !sticker.value?.image_url
);

// Nomes mencionáveis reais da sala (humanos + IAs + "todos") pra construir
// regex específica e evitar falso-positivo do tipo "@Beatriz Oi" — onde "Oi"
// não é parte do nome mas seria capturado por uma regex genérica
// `@palavra (palavra)?`.
const mentionableNames = computed(() => {
  const room = messageRoom.value;
  if (!room?.members) return ['todos'];
  const names = ['todos'];
  for (const m of room.members) {
    if (m.is_ai) names.push('Beatriz');
    else if (m.user_id && m.name) names.push(m.name);
  }
  return names;
});

// Renderiza @nome em destaque, casando SÓ contra nomes reais da sala.
// Match guloso: tenta nome composto (multi-palavras) antes do simples,
// sempre exigindo word boundary depois (espaço, pontuação ou fim).
const renderedHtml = computed(() => {
  const raw = props.message.content || '';
  if (!raw) return '';
  const escaped = raw
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

  // Ordena por tamanho desc pra que "Aline Pereira" tenha precedência sobre "Aline".
  const names = [...mentionableNames.value].sort((a, b) => b.length - a.length);
  if (names.length === 0) return escaped;

  const escapeRe = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const pattern = new RegExp(`@(${names.map(escapeRe).join('|')})(?=\\b|$)`, 'gi');
  return escaped.replace(pattern, (_m, name) => `<span class="ic-mention">@${name}</span>`);
});

// === Edit/Delete ===
const EDIT_WINDOW_MS = 5 * 60 * 1000;
const showActionsMenu = ref(false);
// UX-fix 2026-05-20: refs do botão chevron (2 — sticker e texto, ambos
// usam o mesmo state mas têm DOM elements diferentes). MessageActionsMenu
// usa um deles via Teleport+position fixed pra ancorar sem interferir
// no layout vizinho.
const stickerChevronRef = ref(null);
const bubbleChevronRef = ref(null);
const actionMenuAnchor = computed(() =>
  stickerChevronRef.value || bubbleChevronRef.value
);
const isEditing = ref(false);
const editText = ref('');
const editSaving = ref(false);
const editError = ref('');
// Re-renderiza o canEdit a cada 30s pra "expirar" o botão Editar quando passar
// dos 5 min sem ter que mexer no DOM.
const tick = ref(0);
let tickTimer = null;
if (typeof window !== 'undefined') {
  tickTimer = setInterval(() => { tick.value++; }, 30 * 1000);
}
const closeMenuOnClickOutside = () => {
  if (showActionsMenu.value) showActionsMenu.value = false;
};
if (typeof document !== 'undefined') {
  document.addEventListener('click', closeMenuOnClickOutside);
}
onUnmounted(() => {
  if (tickTimer) clearInterval(tickTimer);
  stopEditTick();
  if (typeof document !== 'undefined') {
    document.removeEventListener('click', closeMenuOnClickOutside);
  }
});

const canEdit = computed(() => {
  // tick.value é só pra invalidar o cache do computed. Sem usar, Vue não
  // re-avalia mesmo se Date.now mudar.
  void tick.value;
  if (!props.isOwn) return false;
  if (isDeleted.value) return false;
  if (props.message.content_type !== 'text') return false;
  const created = new Date(props.message.created_at).getTime();
  return Date.now() - created < EDIT_WINDOW_MS;
});
const canDelete = computed(() => props.isOwn && !isDeleted.value);

// FE-20 (auditoria 2026-05-18): countdown durante edit pra avisar antes
// da janela expirar — user perde texto se janela passa durante digitação
// e backend retorna 422. Tick mais granular (1s) só durante isEditing
// pra evitar re-renders desnecessários quando ninguém tá editando.
let editTick = null;
const startEditTick = () => {
  if (editTick) return;
  editTick = setInterval(() => { tick.value++; }, 1000);
};
const stopEditTick = () => {
  if (editTick) {
    clearInterval(editTick);
    editTick = null;
  }
};

const editTimeRemainingSec = computed(() => {
  void tick.value;
  if (!isEditing.value) return null;
  const created = new Date(props.message.created_at).getTime();
  const remaining = EDIT_WINDOW_MS - (Date.now() - created);
  return remaining > 0 ? Math.ceil(remaining / 1000) : 0;
});

const editWindowWarning = computed(
  () => editTimeRemainingSec.value !== null && editTimeRemainingSec.value <= 60
);

// Conversar com [nome]: cria/encontra DM com o autor da mensagem e navega.
// RoomCreator é idempotente em direct, então repetir o clique abre a mesma sala.
const canConverseWithSender = computed(() => {
  if (props.isOwn) return false;
  if (isDeleted.value) return false;
  if (isAiSender.value) return false; // Bea não tem DM
  return Boolean(props.message.sender?.id);
});
const onConverseWithSender = async () => {
  showActionsMenu.value = false;
  if (!canConverseWithSender.value) return;
  try {
    const room = await store.dispatch('internalChatRooms/create', {
      kind: 'direct',
      member_user_ids: [props.message.sender.id],
    });
    if (room?.id) {
      router.push({
        name: 'internal_chat_room',
        params: { accountId: route.params.accountId, roomId: room.id },
      });
    }
  } catch {
    // silencioso — o usuário tenta de novo se falhar
  }
};

// "Responder no particular": guarda snapshot do quote, abre/cria DM, navega.
// O composer do DM consome o pending reply on mount.
const onReplyPrivately = async () => {
  showActionsMenu.value = false;
  if (!canConverseWithSender.value) return;
  try {
    const room = await store.dispatch('internalChatMessages/preparePrivateReply', {
      sourceMessage: props.message,
    });
    if (room?.id) {
      router.push({
        name: 'internal_chat_room',
        params: { accountId: route.params.accountId, roomId: room.id },
      });
    }
  } catch {
    // silencioso
  }
};

// Snapshot de quote vindo de "Responder no particular" — quando uma mensagem
// no DM tem content_attributes.quoted_message, renderizamos como ReplyPreview.
const quotedSnapshot = computed(() => {
  const q = props.message.content_attributes?.quoted_message;
  return q && typeof q === 'object' ? q : null;
});

const onReply = () => {
  showActionsMenu.value = false;
  emit('reply', props.message);
};

const isFavorited = computed(() => Boolean(props.message.is_favorited));
const favoritePending = ref(false);
const onToggleFavorite = async () => {
  showActionsMenu.value = false;
  if (favoritePending.value) return;
  favoritePending.value = true;
  // Captura estado ANTES do dispatch — store atualiza otimisticamente,
  // então `isFavorited.value` já está invertido após o await.
  const wasAlreadyFavorited = isFavorited.value;
  try {
    await store.dispatch('internalChatMessages/toggleFavorite', {
      roomId: props.message.room_id,
      messageId: props.message.id,
    });
    useAlert(
      t(wasAlreadyFavorited
        ? 'INTERNAL_CHAT.MESSAGE.UNFAVORITED_TOAST'
        : 'INTERNAL_CHAT.MESSAGE.FAVORITED_TOAST')
    );
  } catch {
    // silencioso — o store já reverte o estado otimista
  } finally {
    favoritePending.value = false;
  }
};

// === Reações (estilo WhatsApp) ===
// 6 emojis padrão expostos na quick-row do menu. Mesma lista que o backend
// expõe em InternalChat::MessageReaction::DEFAULT_EMOJIS — manter sincronizado
// se quiser trocar.
const REACTION_EMOJIS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
const reactions = computed(() =>
  Array.isArray(props.message.reactions) ? props.message.reactions : []
);
const canReact = computed(() => !isDeleted.value && !isEditing.value);
const onReact = async emoji => {
  showActionsMenu.value = false;
  if (!canReact.value) return;
  try {
    await store.dispatch('internalChatMessages/toggleReaction', {
      roomId: props.message.room_id,
      messageId: props.message.id,
      emoji,
    });
  } catch {
    // silencioso — store já reverte
  }
};

const startEdit = () => {
  showActionsMenu.value = false;
  if (!canEdit.value) return;
  editText.value = props.message.content || '';
  editError.value = '';
  isEditing.value = true;
  // FE-20: tick 1s durante edit pra atualizar countdown.
  startEditTick();
};
const cancelEdit = () => {
  isEditing.value = false;
  editText.value = '';
  editError.value = '';
  stopEditTick();
};
const saveEdit = async () => {
  const content = editText.value.trim();
  if (!content || editSaving.value) return;
  if (content === (props.message.content || '').trim()) {
    cancelEdit();
    return;
  }
  editSaving.value = true;
  editError.value = '';
  try {
    await store.dispatch('internalChatMessages/edit', {
      roomId: props.message.room_id,
      messageId: props.message.id,
      content,
    });
    isEditing.value = false;
    stopEditTick();
  } catch (e) {
    editError.value = e?.response?.data?.error || 'Falha ao editar';
  } finally {
    editSaving.value = false;
  }
};
const doDelete = async () => {
  showActionsMenu.value = false;
  if (!canDelete.value) return;
  if (!confirm('Apagar esta mensagem para todos? Não dá pra desfazer.')) return;
  try {
    await store.dispatch('internalChatMessages/remove', {
      roomId: props.message.room_id,
      messageId: props.message.id,
    });
  } catch {
    alert('Falha ao apagar');
  }
};
</script>

<template>
  <!-- Mensagem de sistema -->
  <div v-if="isSystem" class="flex justify-center my-2 ic-message-enter">
    <span class="px-3 py-1 text-[11px] rounded-full bg-n-alpha-1 text-n-slate-11">
      {{ message.content }}
    </span>
  </div>

  <!-- Mensagem normal -->
  <div
    v-else
    class="flex gap-2 my-1 group/msg ic-message-enter"
    :class="isOwn ? 'flex-row-reverse' : 'flex-row'"
  >
    <Avatar
      v-if="!isOwn"
      :name="senderName"
      :src="message.sender?.avatar_url || ''"
      :size="28"
      :icon-name="isAiSender ? 'i-lucide-sparkles' : null"
      rounded-full
    />

    <!-- Sticker: imagem flutuante, sem fundo de bolha (estilo WhatsApp) -->
    <div
      v-if="isSticker"
      class="relative w-52 sm:w-60 group/msg"
    >
      <!-- Nome do remetente: pílula off-white com texto colorido único do
           usuário, ocupando a largura inteira da figurinha. Só em grupo. -->
      <!-- FE-6: Tooltip absorve a classe `ic-name-pill` pra preservar visual
           da pílula. `senderName || ''` evita bubble vazio se sender for null. -->
      <Tooltip
        v-if="!isOwn && isInGroup"
        :label="senderName || ''"
        class="ic-name-pill mb-1"
        :style="{ color: senderColor.text }"
      >
        <span class="truncate">{{ senderName }}</span>
      </Tooltip>
      <p
        v-else-if="!isOwn"
        class="text-[11px] font-medium mb-0.5 px-1 text-n-slate-11 truncate"
      >
        {{ senderName }}
      </p>
      <div class="relative inline-block">
        <Tooltip label="Clique para salvar">
          <img
            :src="sticker.image_url"
            class="object-contain w-52 h-52 sm:w-60 sm:h-60 select-none cursor-pointer"
            draggable="false"
            loading="lazy"
            alt="figurinha"
            @click="openStickerPreview"
          >
        </Tooltip>
        <!-- Chevron único no canto superior direito da figurinha -->
        <!-- FE-6: Tooltip absorve o posicionamento absoluto + visibility do
             chevron — assim o bubble do tooltip e o fade-in seguem o mesmo
             elemento. -->
        <Tooltip
          label="Mais ações"
          class="absolute top-1 right-1 opacity-0 group-hover/msg:opacity-100 focus-within:opacity-100"
        >
          <button
            ref="stickerChevronRef"
            type="button"
            class="ic-chevron-floating"
            @click.stop="showActionsMenu = !showActionsMenu"
          >
            <span class="i-lucide-chevron-down text-lg" />
          </button>
        </Tooltip>

        <!-- Menu agora usa Teleport + position fixed calculada do botão
             chevron (anchor-el). Vive fora do DOM da bolha — não interfere
             com mensagens vizinhas nem com scroll do thread. -->
        <MessageActionsMenu
          v-if="showActionsMenu"
          :anchor-el="actionMenuAnchor"
          :reaction-emojis="REACTION_EMOJIS"
          :reactions="reactions"
          :can-react="canReact"
          :can-edit="canEdit"
          :can-delete="canDelete"
          :can-converse-with-sender="canConverseWithSender"
          :is-favorited="isFavorited"
          :favorite-pending="favoritePending"
          :sender-name="senderName"
          :is-own="isOwn"
          @react="onReact"
          @reply="onReply"
          @reply-privately="onReplyPrivately"
          @converse-with-sender="onConverseWithSender"
          @toggle-favorite="onToggleFavorite"
          @edit="startEdit"
          @delete="doDelete"
        />
      </div>
      <!-- Hora: pílula branca abaixo da figurinha (estilo WhatsApp) -->
      <div class="flex justify-end mt-1">
        <span class="ic-time-pill">
          <!-- Indicador "favoritada" estilo WhatsApp: estrela pequena
               âmbar antes da hora. Mesma cor do botão de favoritar
               (text-n-amber-11) pra consistência visual. -->
          <span
            v-if="isFavorited"
            class="i-ri-star-fill text-[11px] text-n-amber-11"
            aria-label="Favoritada"
          />
          <span>{{ time }}</span>
          <ReadReceiptIcon v-if="isOwn" :is-read="isRead" />
        </span>
      </div>
      <!-- Reações: pílulas brancas, sempre alinhadas à direita (junto da hora). -->
      <ReactionsBar
        :reactions="reactions"
        align="end"
        @react="onReact"
      />

      <!-- Preview ao clicar no sticker: salvar nas favoritas / remover -->
      <div
        v-if="showStickerPreview"
        class="fixed inset-0 z-[55] flex items-center justify-center bg-black/60 px-4"
        @click.self="showStickerPreview = false"
      >
        <div class="w-full max-w-md rounded-xl bg-n-solid-1 border border-n-weak shadow-2xl p-6 text-center">
          <img
            :src="sticker.image_url"
            class="object-contain w-72 h-72 sm:w-80 sm:h-80 mx-auto"
          >
          <p class="mt-3 text-xs text-n-slate-11">
            Enviada por <span class="font-medium text-n-slate-12">{{ senderName }}</span>
          </p>
          <div class="flex justify-center gap-2 mt-4">
            <BeclinicButton
              v-if="!stickerIsDefault && !stickerInCollection"
              label="Salvar nas favoritas"
              icon="i-lucide-star"
              size="sm"
              :disabled="stickerActionPending"
              @click="saveSticker"
            />
            <BeclinicButton
              v-else-if="!stickerIsDefault"
              label="Remover das favoritas"
              icon="i-lucide-star-off"
              variant="faded"
              color="amber"
              size="sm"
              :disabled="stickerActionPending"
              @click="removeSticker"
            />
            <BeclinicButton
              label="Fechar"
              variant="ghost"
              color="slate"
              size="sm"
              @click="showStickerPreview = false"
            />
          </div>
          <p
            v-if="stickerActionMsg"
            class="mt-3 text-[11px] text-n-slate-11"
          >
            {{ stickerActionMsg }}
          </p>
          <p
            v-else-if="stickerIsDefault"
            class="mt-3 text-[11px] text-n-slate-10"
          >
            Figurinha padrão da Klivy — disponível em todas as clínicas.
          </p>
          <p
            v-else-if="stickerInCollection"
            class="mt-3 text-[11px] text-n-slate-10"
          >
            Já está na sua coleção.
          </p>
        </div>
      </div>
    </div>

    <!-- Sticker que foi cascade-deletado: placeholder leve -->
    <div
      v-else-if="isOrphanSticker"
      class="px-3 py-2 rounded-2xl bg-n-alpha-1 text-n-slate-10 italic text-xs"
    >
      <span class="i-lucide-sticker align-middle text-sm" />
      <span class="ml-1 align-middle">figurinha removida</span>
    </div>

    <div
      v-else
      class="max-w-[68%] rounded-2xl px-3 py-2 shadow-sm relative ic-bubble"
      :class="
        isOwn
          ? 'ic-bubble-own rounded-tr-sm'
          : 'bg-n-solid-2 text-n-slate-12 rounded-tl-sm'
      "
    >
      <p
        v-if="!isOwn"
        class="text-[11px] font-medium mb-0.5 flex items-center gap-1"
        :class="
          isAiSender
            ? 'text-n-brand'
            : (isInGroup ? '' : 'text-n-slate-11')
        "
        :style="
          !isAiSender && isInGroup ? { color: senderColor.text } : null
        "
      >
        <span class="truncate">{{ senderName }}</span>
        <span
          v-if="isAiSender"
          class="text-[8px] font-bold uppercase tracking-wide px-1 rounded bg-n-brand text-white"
        >
          IA
        </span>
      </p>

      <ReplyPreview
        v-if="repliedMessage"
        :message="repliedMessage"
        compact
        :is-own="isOwn"
        @click="emit('jump-to-reply', repliedMessage.id)"
      />
      <!-- Quote snapshot (vem de "Responder no particular" — origem está em
           outra sala, então não dá pra clicar pra navegar nela). -->
      <ReplyPreview
        v-else-if="quotedSnapshot"
        :message="quotedSnapshot"
        compact
        :is-own="isOwn"
      />

      <p
        v-if="isDeleted"
        class="text-sm italic flex items-center gap-1.5"
        :class="isOwn ? 'ic-own-muted' : 'text-n-slate-10'"
      >
        <span class="i-lucide-ban text-sm" />
        <span>{{ $t('INTERNAL_CHAT.MESSAGE.DELETED') }}</span>
      </p>
      <template v-else-if="isEditing">
        <textarea
          v-model="editText"
          rows="2"
          class="w-full text-sm resize-none rounded-md px-2 py-1 bg-white/60 text-n-slate-12 focus:outline-none focus:ring-2 focus:ring-n-brand"
          :class="isOwn ? '' : 'bg-n-alpha-1'"
          @keydown.enter.exact.prevent="saveEdit"
          @keydown.escape.prevent="cancelEdit"
        />
        <p
          v-if="editError"
          class="mt-1 text-[11px] text-n-ruby-11"
        >{{ editError }}</p>
        <!-- FE-20: countdown da janela de edição. Texto neutro até 60s,
             warning quando faltam <=60s. -->
        <p
          v-if="editTimeRemainingSec !== null"
          class="mt-1 text-[11px]"
          :class="editWindowWarning ? 'text-n-amber-11 font-medium' : 'text-n-slate-10'"
        >
          <template v-if="editTimeRemainingSec > 0">
            Janela de edição: {{ Math.floor(editTimeRemainingSec / 60) }}:{{ String(editTimeRemainingSec % 60).padStart(2, '0') }}
          </template>
          <template v-else>
            ⚠️ Janela de edição expirou. O texto será mantido se você cancelar.
          </template>
        </p>
        <div class="flex justify-end gap-2 mt-1">
          <button
            type="button"
            class="text-[11px] font-medium px-2 py-1 rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1"
            :disabled="editSaving"
            @click="cancelEdit"
          >{{ $t('INTERNAL_CHAT.MESSAGE.EDIT_CANCEL') }}</button>
          <button
            type="button"
            class="text-[11px] font-medium px-2 py-1 rounded bg-n-brand text-white hover:brightness-110 disabled:opacity-50"
            :disabled="editSaving || !editText.trim()"
            @click="saveEdit"
          >{{ editSaving ? $t('INTERNAL_CHAT.MESSAGE.EDIT_SAVING') : $t('INTERNAL_CHAT.MESSAGE.EDIT_SAVE') }}</button>
        </div>
      </template>
      <template v-else>
        <MessageAttachments
          v-if="hasAttachments"
          :attachments="message.attachments"
          :is-own="isOwn"
          :sender="message.sender || {}"
          :message-created-at="message.created_at"
        />
        <!-- eslint-disable-next-line vue/no-v-html -->
        <p
          v-if="message.content"
          class="text-sm whitespace-pre-wrap break-words"
          :class="hasAttachments ? 'mt-2' : ''"
          v-html="renderedHtml"
        />
      </template>

      <p
        class="text-[10px] mt-1 text-end flex items-center justify-end gap-1"
        :class="isOwn ? 'ic-own-muted' : 'text-n-slate-10'"
      >
        <!-- Indicador "favoritada" estilo WhatsApp: estrela pequena âmbar
             antes da hora. Mesma cor do botão de favoritar (n-amber-11). -->
        <span
          v-if="isFavorited"
          class="i-lucide-star text-[11px] text-n-amber-11"
          aria-label="Favoritada"
        />
        <span>{{ time }}</span>
        <span v-if="message.edited_at" class="italic">· editada</span>
        <ReadReceiptIcon v-if="isOwn && !isDeleted" :is-read="isRead" />
      </p>

      <!-- Reações: pílulas clicáveis com emoji + count. Click toggla. -->
      <ReactionsBar
        :reactions="reactions"
        :align="isOwn ? 'end' : 'start'"
        top-spacing="mt-1.5"
        @react="onReact"
      />

      <!-- Chevron único no canto superior direito da bolha (estilo WhatsApp) -->
      <!-- FE-6: Tooltip absorve `absolute top-1 right-1 opacity-0 ...` pra
           preservar posicionamento + visibility do chevron. -->
      <Tooltip
        v-if="!isDeleted && !isEditing"
        label="Mais ações"
        class="absolute top-1 right-1 opacity-0 group-hover/msg:opacity-100 focus-within:opacity-100"
      >
        <button
          ref="bubbleChevronRef"
          type="button"
          class="ic-chevron-bubble"
          :class="isOwn ? 'ic-chevron-on-own' : 'ic-chevron-on-other'"
          @click.stop="showActionsMenu = !showActionsMenu"
        >
          <span class="i-lucide-chevron-down text-base" />
        </button>
      </Tooltip>

      <!-- Menu via Teleport+fixed (ver MessageActionsMenu). Anchor = botão. -->
      <MessageActionsMenu
        v-if="showActionsMenu"
        :anchor-el="actionMenuAnchor"
        :reaction-emojis="REACTION_EMOJIS"
        :reactions="reactions"
        :can-react="canReact"
        :can-edit="canEdit"
        :can-delete="canDelete"
        :can-converse-with-sender="canConverseWithSender"
        :is-favorited="isFavorited"
        :favorite-pending="favoritePending"
        :sender-name="senderName"
        :is-own="isOwn"
        @react="onReact"
        @reply="onReply"
        @reply-privately="onReplyPrivately"
        @converse-with-sender="onConverseWithSender"
        @toggle-favorite="onToggleFavorite"
        @edit="startEdit"
        @delete="doDelete"
      />
    </div>
  </div>
</template>

<style>
/* Mention destacada — só cor azul Klivy no texto, sem badge/background.
   Decisão UX: badge pesava demais visualmente, ficava parecendo botão. */
.ic-mention {
  font-weight: 600;
  color: #1d4ed8;  /* blue-700 */
}
.dark .ic-mention {
  color: #93c5fd;  /* blue-300 — contraste maior no escuro */
}
/* Bolha enviada: verde claro estilo WhatsApp */
.ic-bubble-own {
  background-color: #d8fdd3;
  color: #0f172a;
}
.dark .ic-bubble-own {
  background-color: #005c4b;
  color: #e2e8f0;
}
.ic-own-muted {
  color: rgba(15, 23, 42, 0.55);
}
.dark .ic-own-muted {
  color: rgba(226, 232, 240, 0.7);
}
.ic-tick-read {
  color: #1d4ed8;
}
.dark .ic-tick-read {
  color: #60a5fa;
}

/* Chevron embutido na bolha (estilo WhatsApp): semi-transparente, fade-in
   no hover, contraste diferente entre own (verde claro) e other (cinza). */
/* UX-fix 2026-05-20: container 22→28px + font-size 16px explícito pra
   garantir que o glyph `i-lucide-chevron-down` renderize corretamente.
   Antes o button compacto cortava o ícone em alguns zooms/DPRs. */
.ic-chevron-bubble {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  padding: 0;
  border-radius: 9999px;
  cursor: pointer;
  transition: opacity 120ms ease, background-color 120ms ease;
  font-size: 16px;
}
.ic-chevron-on-own {
  color: rgba(15, 23, 42, 0.55);
}
.ic-chevron-on-own:hover {
  background-color: rgba(15, 23, 42, 0.10);
  color: rgba(15, 23, 42, 0.85);
}
.ic-chevron-on-other {
  color: rgb(var(--n-slate-11));
}
.ic-chevron-on-other:hover {
  background-color: rgb(var(--n-alpha-2));
  color: rgb(var(--n-slate-12));
}
.dark .ic-chevron-on-own {
  color: rgba(226, 232, 240, 0.65);
}
.dark .ic-chevron-on-own:hover {
  background-color: rgba(255, 255, 255, 0.12);
  color: rgba(226, 232, 240, 0.95);
}

/* Chevron flutuante na figurinha (não tem bolha, então usa fundo sólido).
   UX-fix 2026-05-20: aumentado de 26→32px + ícone text-lg pra ser
   visível e confortável de clicar (era invisível em screens pequenas). */
.ic-chevron-floating {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 9999px;
  background-color: rgba(0, 0, 0, 0.55);
  color: #fff;
  cursor: pointer;
  transition: opacity 120ms ease, background-color 120ms ease;
  font-size: 18px;
}
.ic-chevron-floating:hover {
  background-color: rgba(0, 0, 0, 0.75);
}

/* Itens disabled (Em breve) no menu de ações — clarinhos, sem hover. */
[class*="bg-n-solid-1"] button[disabled] {
  opacity: 0.55;
  cursor: not-allowed;
}
[class*="bg-n-solid-1"] button[disabled]:hover {
  background-color: transparent;
}
.ic-soon-tag {
  font-size: 9px;
  font-weight: 600;
  padding: 1px 5px;
  border-radius: 9999px;
  background-color: rgb(var(--n-amber-3));
  color: rgb(var(--n-amber-11));
  margin-left: auto;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

/* Quick reaction picker (row no topo do menu de ações) */
.ic-reaction-pick {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 9999px;
  font-size: 18px;
  cursor: pointer;
  transition: transform 100ms ease, background-color 100ms ease;
}
.ic-reaction-pick:hover {
  background-color: rgb(var(--n-alpha-1));
  transform: scale(1.18);
}
.ic-reaction-pick-active {
  background-color: rgb(var(--n-brand) / 0.18);
}
.dark .ic-reaction-pick-active {
  background-color: rgba(110, 231, 183, 0.22);
}

/* Pílula de reação (emoji + count) — só fundo branco. */
.ic-reaction-badge {
  display: inline-flex;
  align-items: center;
  gap: 3px;
  padding: 2px 9px;
  border-radius: 9999px;
  font-size: 12px;
  line-height: 1.4;
  background-color: #fff;
  color: rgb(var(--n-slate-12));
  cursor: pointer;
}
.ic-reaction-badge-mine {
  color: rgb(var(--n-brand));
}
.dark .ic-reaction-badge {
  background-color: rgb(var(--n-solid-2));
  color: rgb(var(--n-slate-12));
}
.dark .ic-reaction-badge-mine {
  color: #a7f3d0;
}
.ic-reaction-count {
  font-size: 11px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

/* Label do nome do remetente em sticker — só fundo branco. */
.ic-name-pill {
  display: flex;
  align-items: center;
  gap: 4px;
  width: 100%;
  padding: 5px 10px;
  border-radius: 8px;
  font-size: 12px;
  font-weight: 600;
  line-height: 1.3;
  background-color: #fff;
  overflow: hidden;
  white-space: nowrap;
}
.dark .ic-name-pill {
  background-color: rgb(var(--n-solid-2));
}

/* Pílula da hora abaixo da figurinha — só fundo branco. */
.ic-time-pill {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 9px;
  border-radius: 9999px;
  background-color: #fff;
  color: rgb(var(--n-slate-11));
  font-size: 10px;
  line-height: 1.4;
}
.dark .ic-time-pill {
  background-color: rgb(var(--n-solid-2));
  color: rgb(var(--n-slate-11));
}
</style>
