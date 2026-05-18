<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import PresenceDot from './PresenceDot.vue';

const props = defineProps({
  room: { type: Object, required: true },
});

const store = useStore();
const route = useRoute();
const router = useRouter();
const showMenu = ref(false);

const isActive = computed(
  () => Number(route.params.roomId) === Number(props.room.id)
);

const unread = computed(
  () => store.getters['internalChatRooms/getUnreadByRoom'](props.room.id)
);
// Indicador @ no badge (estilo WhatsApp) — só aparece se eu fui mencionado
// e ainda não li. Independente do contador de mensagens normal.
const unreadMentions = computed(
  () => store.getters['internalChatMentions/getUnreadCountByRoom'](props.room.id)
);

const isMuted = computed(() => {
  if (!props.room.muted_until) return false;
  return new Date(props.room.muted_until).getTime() > Date.now();
});

const PREVIEW_LABELS = {
  image: '📷 Imagem',
  audio: '🎵 Áudio',
  video: '🎬 Vídeo',
  file: '📎 Arquivo',
};
const lastPreview = computed(() => {
  const msg = props.room.last_message;
  if (!msg) return 'Sem mensagens ainda';
  if (msg.deleted_at) return 'Mensagem apagada';
  if (msg.content_type === 'system') return msg.content || '';
  if (msg.content_type !== 'text') {
    return PREVIEW_LABELS[msg.content_type] || `[${msg.content_type}]`;
  }
  if (msg.content) return msg.content;
  if (msg.attachments?.length) {
    const first = msg.attachments[0];
    return PREVIEW_LABELS[first.file_type] || '📎 Anexo';
  }
  return '';
});

const otherUserId = computed(() => {
  if (props.room.kind !== 'direct') return null;
  const me = store.getters.getCurrentUserID;
  return props.room.members?.find(m => m.user_id !== me)?.user_id || null;
});

const formattedTime = computed(() => {
  const ts = props.room.last_message_at || props.room.created_at;
  if (!ts) return '';
  const d = new Date(ts);
  const today = new Date();
  if (d.toDateString() === today.toDateString()) {
    return d.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    });
  }
  return d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' });
});

const open = () => {
  router.push({
    name: 'internal_chat_room',
    params: { accountId: route.params.accountId, roomId: props.room.id },
  });
};

const toggleMenu = e => {
  e.stopPropagation();
  showMenu.value = !showMenu.value;
};
const closeMenu = () => {
  showMenu.value = false;
};

const toggleMute = async () => {
  if (isMuted.value) {
    await store.dispatch('internalChatRooms/unmute', props.room.id);
  } else {
    await store.dispatch('internalChatRooms/mute', { roomId: props.room.id });
  }
  closeMenu();
};
const archive = async () => {
  await store.dispatch('internalChatRooms/archive', props.room.id);
  closeMenu();
};
</script>

<template>
  <li class="relative group/item">
    <button
      type="button"
      class="flex items-start w-full gap-3 px-3 py-3 transition border-b border-n-weak text-start hover:bg-n-alpha-1"
      :class="isActive ? 'bg-n-alpha-2' : ''"
      @click="open"
    >
      <div class="relative shrink-0">
        <Avatar
          :name="room.name || 'Conversa'"
          :src="room.avatar_url || ''"
          :size="40"
          rounded-full
        />
        <PresenceDot
          v-if="otherUserId"
          :user-id="otherUserId"
          :size="11"
          class="absolute bottom-0 right-0"
        />
      </div>

      <div class="flex-1 min-w-0">
        <div class="flex items-center justify-between gap-2">
          <p class="text-sm font-medium truncate text-n-slate-12 flex items-center gap-1">
            <span class="truncate">{{ room.name || 'Conversa' }}</span>
            <span v-if="isMuted" class="i-lucide-bell-off text-xs text-n-slate-10" />
          </p>
          <span class="text-[11px] text-n-slate-10 shrink-0">
            {{ formattedTime }}
          </span>
        </div>
        <div class="flex items-center justify-between gap-2 mt-0.5">
          <p class="text-xs truncate text-n-slate-11">{{ lastPreview }}</p>
          <div class="flex items-center gap-1 shrink-0">
            <span
              v-if="unreadMentions > 0"
              class="inline-flex items-center justify-center w-[18px] h-[18px] text-[11px] font-semibold rounded-full text-white"
              :class="isMuted ? 'bg-n-slate-9' : 'bg-n-brand'"
              title="Você foi mencionado"
            >
              @
            </span>
            <span
              v-if="unread > 0"
              class="inline-flex items-center justify-center min-w-[18px] h-[18px] px-1 text-[10px] font-semibold rounded-full text-white"
              :class="isMuted ? 'bg-n-slate-9' : 'bg-n-brand'"
            >
              {{ unread > 99 ? '99+' : unread }}
            </span>
          </div>
        </div>
      </div>
    </button>

    <button
      type="button"
      class="absolute top-2 right-2 opacity-0 group-hover/item:opacity-100 transition w-7 h-7 rounded-md flex items-center justify-center bg-n-solid-1 border border-n-weak text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1"
      title="Mais ações"
      @click="toggleMenu"
    >
      <span class="i-lucide-more-horizontal text-base" />
    </button>

    <div
      v-if="showMenu"
      class="absolute z-20 right-2 top-10 w-44 rounded-lg shadow-2xl bg-n-solid-1 border border-n-weak overflow-hidden"
      @click.stop
    >
      <button
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
        @click="toggleMute"
      >
        <span :class="isMuted ? 'i-lucide-bell' : 'i-lucide-bell-off'" class="text-base" />
        {{ isMuted ? 'Reativar notificações' : 'Silenciar' }}
      </button>
      <button
        type="button"
        class="flex items-center w-full gap-2 px-3 py-2 text-sm text-n-slate-12 hover:bg-n-alpha-1"
        @click="archive"
      >
        <span class="i-lucide-archive text-base" />
        Arquivar
      </button>
    </div>

    <div
      v-if="showMenu"
      class="fixed inset-0 z-10"
      @click="closeMenu"
    />
  </li>
</template>
