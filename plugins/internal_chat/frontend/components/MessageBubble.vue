<script setup>
import { computed, onUnmounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MessageAttachments from './MessageAttachments.vue';
import ReplyPreview from './ReplyPreview.vue';

const props = defineProps({
  message: { type: Object, required: true },
  isOwn: { type: Boolean, default: false },
});

const store = useStore();
const route = useRoute();
const router = useRouter();
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
const stickerActionPending = ref(false);
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

const saveSticker = async () => {
  if (stickerActionPending.value) return;
  stickerActionPending.value = true;
  stickerActionMsg.value = '';
  try {
    await store.dispatch(
      'internalChatStickers/favoriteAndCacheById',
      props.message.sticker.id
    );
    stickerActionMsg.value = 'Figurinha salva nas suas favoritas.';
  } catch {
    stickerActionMsg.value = 'Falha ao salvar.';
  } finally {
    stickerActionPending.value = false;
  }
};

const removeSticker = async () => {
  if (stickerActionPending.value) return;
  if (!confirm('Remover esta figurinha das suas favoritas?')) return;
  stickerActionPending.value = true;
  stickerActionMsg.value = '';
  try {
    await store.dispatch(
      'internalChatStickers/toggleFavorite',
      props.message.sticker.id
    );
    stickerActionMsg.value = 'Figurinha removida.';
  } catch {
    stickerActionMsg.value = 'Falha ao remover.';
  } finally {
    stickerActionPending.value = false;
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
  try {
    await store.dispatch('internalChatMessages/toggleFavorite', {
      roomId: props.message.room_id,
      messageId: props.message.id,
    });
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
};
const cancelEdit = () => {
  isEditing.value = false;
  editText.value = '';
  editError.value = '';
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
      <div
        v-if="!isOwn && isInGroup"
        class="ic-name-pill mb-1"
        :style="{ color: senderColor.text }"
        :title="senderName"
      >
        <span class="truncate">{{ senderName }}</span>
      </div>
      <p
        v-else-if="!isOwn"
        class="text-[11px] font-medium mb-0.5 px-1 text-n-slate-11 truncate"
      >
        {{ senderName }}
      </p>
      <div class="relative inline-block">
        <img
          :src="sticker.image_url"
          class="object-contain w-52 h-52 sm:w-60 sm:h-60 select-none cursor-pointer"
          draggable="false"
          loading="lazy"
          alt="figurinha"
          title="Clique para salvar"
          @click="openStickerPreview"
        >
        <!-- Chevron único no canto superior direito da figurinha -->
        <button
          type="button"
          class="absolute top-1 right-1 ic-chevron-floating opacity-0 group-hover/msg:opacity-100 focus:opacity-100"
          title="Mais ações"
          @click.stop="showActionsMenu = !showActionsMenu"
        >
          <span class="i-lucide-chevron-down text-base" />
        </button>
      </div>
      <!-- Hora: pílula branca abaixo da figurinha (estilo WhatsApp) -->
      <div class="flex justify-end mt-1">
        <span class="ic-time-pill">
          <span>{{ time }}</span>
          <span
            v-if="isOwn"
            class="inline-flex items-center"
            :class="isRead ? 'ic-tick-read' : ''"
            :title="isRead ? 'Lida' : 'Enviada'"
          >
            <span v-if="isRead" class="i-lucide-check-check text-sm" />
            <span v-else class="i-lucide-check text-sm" />
          </span>
        </span>
      </div>
      <!-- Reações: pílulas brancas, sempre alinhadas à direita (junto da hora). -->
      <div
        v-if="reactions.length"
        class="flex flex-wrap gap-1 mt-1 justify-end"
      >
        <button
          v-for="r in reactions"
          :key="r.emoji"
          type="button"
          class="ic-reaction-badge"
          :class="r.by_me ? 'ic-reaction-badge-mine' : ''"
          :title="r.by_me ? 'Remover minha reação' : `Reagir com ${r.emoji}`"
          @click="onReact(r.emoji)"
        >
          <span>{{ r.emoji }}</span>
          <span class="ic-reaction-count">{{ r.count }}</span>
        </button>
      </div>
      <!-- Dropdown unificado — aparece AO LADO da figurinha (estilo WhatsApp) -->
      <div
        v-if="showActionsMenu"
        class="absolute z-30 top-0 w-52 rounded-lg shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden"
        :class="isOwn ? 'right-full mr-2' : 'left-full ml-2'"
        @click.stop
      >
        <!-- Quick reactions row (estilo WhatsApp) — 6 emojis padrão -->
        <div
          v-if="canReact"
          class="flex items-center justify-between gap-1 px-2 py-2 border-b border-n-weak"
        >
          <button
            v-for="e in REACTION_EMOJIS"
            :key="e"
            type="button"
            class="ic-reaction-pick"
            :class="reactions.find(r => r.emoji === e && r.by_me) ? 'ic-reaction-pick-active' : ''"
            :title="`Reagir com ${e}`"
            @click="onReact(e)"
          >
            {{ e }}
          </button>
        </div>
        <button
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
          @click="onReply"
        >
          <span class="i-lucide-corner-up-left text-sm" />
          <span>Responder</span>
        </button>
        <button
          v-if="canConverseWithSender"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
          @click="onReplyPrivately"
        >
          <span class="i-lucide-reply text-sm" />
          <span class="truncate flex-1">Responder no particular</span>
        </button>
        <button
          v-if="canConverseWithSender"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
          @click="onConverseWithSender"
        >
          <span class="i-lucide-message-circle text-sm" />
          <span class="truncate">Conversar com {{ senderName }}</span>
        </button>
        <button
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start hover:bg-n-alpha-1"
          :class="isFavorited ? 'text-n-amber-11' : 'text-n-slate-12'"
          :disabled="favoritePending"
          @click="onToggleFavorite"
        >
          <span :class="isFavorited ? 'i-lucide-star-off' : 'i-lucide-star'" class="text-sm" />
          <span class="flex-1">{{ isFavorited ? 'Remover dos favoritos' : 'Favoritar' }}</span>
        </button>
        <button
          v-if="canDelete"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-ruby-11 hover:bg-n-ruby-3 border-t border-n-weak"
          @click="doDelete"
        >
          <span class="i-lucide-trash-2 text-sm" />
          <span>Apagar pra todos</span>
        </button>
      </div>

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
            <button
              v-if="!stickerIsDefault && !stickerInCollection"
              type="button"
              class="px-4 py-2 text-sm font-medium text-white rounded-md bg-n-brand hover:brightness-110 disabled:opacity-50"
              :disabled="stickerActionPending"
              @click="saveSticker"
            >
              <span class="i-lucide-star align-middle text-base" />
              <span class="ml-1 align-middle">Salvar nas favoritas</span>
            </button>
            <button
              v-else-if="!stickerIsDefault"
              type="button"
              class="px-4 py-2 text-sm font-medium rounded-md text-n-amber-11 hover:bg-n-amber-3 disabled:opacity-50"
              :disabled="stickerActionPending"
              @click="removeSticker"
            >
              <span class="i-lucide-star-off align-middle text-base" />
              <span class="ml-1 align-middle">Remover das favoritas</span>
            </button>
            <button
              type="button"
              class="px-3 py-2 text-sm rounded-md text-n-slate-11 hover:bg-n-alpha-1"
              @click="showStickerPreview = false"
            >
              Fechar
            </button>
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
        <span>Mensagem apagada pelo usuário</span>
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
        <div class="flex justify-end gap-2 mt-1">
          <button
            type="button"
            class="text-[11px] font-medium px-2 py-1 rounded text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1"
            :disabled="editSaving"
            @click="cancelEdit"
          >Cancelar</button>
          <button
            type="button"
            class="text-[11px] font-medium px-2 py-1 rounded bg-n-brand text-white hover:brightness-110 disabled:opacity-50"
            :disabled="editSaving || !editText.trim()"
            @click="saveEdit"
          >{{ editSaving ? 'Salvando…' : 'Salvar' }}</button>
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
        <span>{{ time }}</span>
        <span v-if="message.edited_at" class="italic">· editada</span>
        <span
          v-if="isOwn && !isDeleted"
          class="inline-flex items-center"
          :class="isRead ? 'ic-tick-read' : ''"
          :title="isRead ? 'Lida' : 'Enviada'"
        >
          <span v-if="isRead" class="i-lucide-check-check text-sm" />
          <span v-else class="i-lucide-check text-sm" />
        </span>
      </p>

      <!-- Reações: pílulas clicáveis com emoji + count. Click toggla. -->
      <div
        v-if="reactions.length"
        class="flex flex-wrap gap-1 mt-1.5"
        :class="isOwn ? 'justify-end' : 'justify-start'"
      >
        <button
          v-for="r in reactions"
          :key="r.emoji"
          type="button"
          class="ic-reaction-badge"
          :class="r.by_me ? 'ic-reaction-badge-mine' : ''"
          :title="r.by_me ? 'Remover minha reação' : `Reagir com ${r.emoji}`"
          @click="onReact(r.emoji)"
        >
          <span>{{ r.emoji }}</span>
          <span class="ic-reaction-count">{{ r.count }}</span>
        </button>
      </div>

      <!-- Chevron único no canto superior direito da bolha (estilo WhatsApp) -->
      <button
        v-if="!isDeleted && !isEditing"
        type="button"
        class="absolute top-1 right-1 ic-chevron-bubble opacity-0 group-hover/msg:opacity-100 focus:opacity-100"
        :class="isOwn ? 'ic-chevron-on-own' : 'ic-chevron-on-other'"
        title="Mais ações"
        @click.stop="showActionsMenu = !showActionsMenu"
      >
        <span class="i-lucide-chevron-down text-base" />
      </button>

      <!-- Dropdown unificado — aparece AO LADO da bolha (estilo WhatsApp) -->
      <div
        v-if="showActionsMenu"
        class="absolute z-30 top-0 w-52 rounded-lg shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden"
        :class="isOwn ? 'right-full mr-2' : 'left-full ml-2'"
        @click.stop
      >
        <!-- Quick reactions row (estilo WhatsApp) — 6 emojis padrão -->
        <div
          v-if="canReact"
          class="flex items-center justify-between gap-1 px-2 py-2 border-b border-n-weak"
        >
          <button
            v-for="e in REACTION_EMOJIS"
            :key="e"
            type="button"
            class="ic-reaction-pick"
            :class="reactions.find(r => r.emoji === e && r.by_me) ? 'ic-reaction-pick-active' : ''"
            :title="`Reagir com ${e}`"
            @click="onReact(e)"
          >
            {{ e }}
          </button>
        </div>
        <button
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
          @click="onReply"
        >
          <span class="i-lucide-corner-up-left text-sm" />
          <span>Responder</span>
        </button>
        <button
          v-if="canConverseWithSender"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
          @click="onReplyPrivately"
        >
          <span class="i-lucide-reply text-sm" />
          <span class="truncate flex-1">Responder no particular</span>
        </button>
        <button
          v-if="canConverseWithSender"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1"
          @click="onConverseWithSender"
        >
          <span class="i-lucide-message-circle text-sm" />
          <span class="truncate">Conversar com {{ senderName }}</span>
        </button>
        <button
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start hover:bg-n-alpha-1"
          :class="isFavorited ? 'text-n-amber-11' : 'text-n-slate-12'"
          :disabled="favoritePending"
          @click="onToggleFavorite"
        >
          <span :class="isFavorited ? 'i-lucide-star-off' : 'i-lucide-star'" class="text-sm" />
          <span class="flex-1">{{ isFavorited ? 'Remover dos favoritos' : 'Favoritar' }}</span>
        </button>
        <button
          v-if="canEdit"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-slate-12 hover:bg-n-alpha-1 border-t border-n-weak"
          @click="startEdit"
        >
          <span class="i-lucide-pencil text-sm" />
          <span>Editar</span>
        </button>
        <button
          v-if="canDelete"
          type="button"
          class="flex items-center w-full gap-2 px-3 py-2 text-xs text-start text-n-ruby-11 hover:bg-n-ruby-3"
          :class="canEdit ? '' : 'border-t border-n-weak'"
          @click="doDelete"
        >
          <span class="i-lucide-trash-2 text-sm" />
          <span>Apagar pra todos</span>
        </button>
      </div>
    </div>
  </div>
</template>

<style>
.ic-mention {
  font-weight: 600;
  background: rgb(var(--n-brand) / 0.15);
  color: rgb(var(--n-brand));
  padding: 0 4px;
  border-radius: 4px;
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
.ic-bubble-own .ic-mention {
  background: rgba(15, 23, 42, 0.08);
  color: #1d4ed8;
}
.dark .ic-bubble-own .ic-mention {
  background: rgba(255, 255, 255, 0.18);
  color: #93c5fd;
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
.ic-chevron-bubble {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 22px;
  height: 22px;
  border-radius: 9999px;
  cursor: pointer;
  transition: opacity 120ms ease, background-color 120ms ease;
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

/* Chevron flutuante na figurinha (não tem bolha, então usa fundo sólido). */
.ic-chevron-floating {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 26px;
  height: 26px;
  border-radius: 9999px;
  background-color: rgba(0, 0, 0, 0.5);
  color: #fff;
  cursor: pointer;
  transition: opacity 120ms ease, background-color 120ms ease;
}
.ic-chevron-floating:hover {
  background-color: rgba(0, 0, 0, 0.7);
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
