<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import MessageThread from './MessageThread.vue';
import MessageComposer from './MessageComposer.vue';
import GroupSettingsDrawer from './GroupSettingsDrawer.vue';
import FavoritesPanel from './FavoritesPanel.vue';
import PresenceDot from './PresenceDot.vue';
import TypingIndicator from './TypingIndicator.vue';

const props = defineProps({
  roomId: { type: [String, Number], required: true },
});

const store = useStore();
const route = useRoute();
const router = useRouter();
const showSettings = ref(false);
const settingsTab = ref('members'); // 'members' | 'edit' | 'favorites'
const showDmFavorites = ref(false); // drawer simples só pra DMs
const replyTarget = ref(null);
const wasLoaded = ref(false);

const openSettings = (tab = 'members') => {
  settingsTab.value = tab;
  showSettings.value = true;
};

const room = computed(() =>
  store.getters['internalChatRooms/getRoomById'](props.roomId)
);
const currentUserId = computed(() => store.getters.getCurrentUserID);

const otherUserId = computed(() => {
  if (!room.value || room.value.kind !== 'direct') return null;
  return (
    room.value.members?.find(m => m.user_id !== currentUserId.value)?.user_id ||
    null
  );
});

const onlineMembersCount = computed(() => {
  if (!room.value || room.value.kind !== 'group') return 0;
  return (room.value.members || []).filter(m => {
    if (!m.user_id || m.user_id === currentUserId.value) return false;
    const agent = store.getters['agents/getAgentById'](m.user_id);
    return agent?.availability_status === 'online';
  }).length;
});

const subtitleText = computed(() => {
  if (!room.value) return '';
  if (room.value.kind === 'group') {
    const total = room.value.members?.length || 0;
    return onlineMembersCount.value > 0
      ? `${total} membros · ${onlineMembersCount.value} online`
      : `${total} membros`;
  }
  const status = otherUserId.value
    ? store.getters['agents/getAgentById'](otherUserId.value)?.availability_status
    : null;
  if (status === 'online') return 'Online agora';
  if (status === 'busy') return 'Ocupado';
  return 'Offline';
});

const loadRoom = async id => {
  if (!id) return;
  if (!store.getters['internalChatRooms/getRoomById'](id)) {
    await store.dispatch('internalChatRooms/show', id);
  }
  await store.dispatch('internalChatMessages/fetch', { roomId: id });
  await store.dispatch('internalChatRooms/clearUnread', id);
  // Quando abre uma sala, marca menções dela como lidas (via fetch geral só atualiza unreadCount)
  await store.dispatch('internalChatMentions/fetch');

  // "Responder no particular": se outro componente preparou um snapshot
  // pendente pra esta sala, consome e seta como replyTarget no composer.
  const pending = await store.dispatch(
    'internalChatMessages/consumePendingPrivateReply',
    Number(id)
  );
  if (pending?.snapshot) {
    replyTarget.value = pending.snapshot;
  }
};

onMounted(() => loadRoom(props.roomId));
watch(
  () => props.roomId,
  id => {
    replyTarget.value = null;
    wasLoaded.value = false;
    loadRoom(id);
  }
);

// Se a sala foi removida da store (cable: room.deleted) enquanto eu estava
// olhando ela, volta pra home — senão o usuário fica com tela em branco.
watch(room, val => {
  if (val) {
    wasLoaded.value = true;
  } else if (wasLoaded.value) {
    showSettings.value = false;
    router.push({
      name: 'internal_chat_home',
      params: { accountId: route.params.accountId },
    });
  }
});

const onReply = msg => {
  replyTarget.value = msg;
};
const cancelReply = () => {
  replyTarget.value = null;
};
const onSent = () => {
  replyTarget.value = null;
};
</script>

<template>
  <div v-if="room" class="flex flex-col flex-1 h-full">
    <header
      class="flex items-center gap-3 px-4 py-3 border-b border-n-weak bg-n-solid-1"
    >
      <button
        type="button"
        class="flex items-center flex-1 min-w-0 gap-3 text-start rounded-md px-1 py-1 -mx-1 transition"
        :class="room.kind === 'group' ? 'hover:bg-n-alpha-1 cursor-pointer' : 'cursor-default'"
        :disabled="room.kind !== 'group'"
        :title="room.kind === 'group' ? 'Abrir detalhes do grupo' : null"
        @click="room.kind === 'group' && openSettings('edit')"
      >
        <span class="relative shrink-0">
          <Avatar :name="room.name || 'Conversa'" :src="room.avatar_url || ''" :size="36" rounded-full />
          <PresenceDot
            v-if="otherUserId"
            :user-id="otherUserId"
            :size="10"
            class="absolute bottom-0 right-0"
          />
        </span>
        <span class="flex-1 min-w-0">
          <span class="block text-sm font-semibold truncate text-n-slate-12">
            {{ room.name || 'Conversa' }}
          </span>
          <span class="block text-xs text-n-slate-11">
            {{ subtitleText }}
          </span>
        </span>
      </button>
      <button
        v-if="room.kind === 'direct'"
        type="button"
        class="inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
        title="Mensagens favoritas"
        @click="showDmFavorites = true"
      >
        <span class="i-lucide-star text-lg" />
      </button>
      <button
        v-if="room.kind === 'group'"
        type="button"
        class="inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
        title="Mensagens favoritas"
        @click="openSettings('favorites')"
      >
        <span class="i-lucide-star text-lg" />
      </button>
      <button
        v-if="room.kind === 'group'"
        type="button"
        class="inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
        title="Configurações do grupo"
        @click="openSettings('members')"
      >
        <span class="i-lucide-settings text-lg" />
      </button>
    </header>

    <MessageThread :room-id="Number(props.roomId)" @reply="onReply" />

    <TypingIndicator :room-id="Number(props.roomId)" />

    <MessageComposer
      :room-id="Number(props.roomId)"
      :members="room.members || []"
      :reply-target="replyTarget"
      @cancel-reply="cancelReply"
      @sent="onSent"
    />

    <GroupSettingsDrawer
      v-if="showSettings && room.kind === 'group'"
      :room="room"
      :initial-tab="settingsTab"
      @close="showSettings = false"
    />

    <!-- Drawer simples de Favoritos para DM (grupo usa o GroupSettingsDrawer) -->
    <div
      v-if="showDmFavorites && room.kind === 'direct'"
      class="fixed inset-0 z-50 flex"
    >
      <div
        class="flex-1 bg-black/40"
        @click="showDmFavorites = false"
      />
      <aside class="w-[380px] max-w-full bg-n-solid-1 border-l border-n-weak shadow-2xl flex flex-col">
        <header class="flex items-center justify-between px-5 py-3 border-b border-n-weak">
          <p class="text-sm font-semibold text-n-slate-12 flex items-center gap-2">
            <span class="i-lucide-star text-base text-n-amber-11" />
            Favoritos
          </p>
          <button
            type="button"
            class="inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
            @click="showDmFavorites = false"
          >
            <span class="i-lucide-x text-lg" />
          </button>
        </header>
        <FavoritesPanel
          :room-id="Number(props.roomId)"
          @jump-to-message="showDmFavorites = false"
        />
      </aside>
    </div>
  </div>
  <div v-else class="flex items-center justify-center flex-1 text-sm text-n-slate-11">
    Carregando conversa…
  </div>
</template>
