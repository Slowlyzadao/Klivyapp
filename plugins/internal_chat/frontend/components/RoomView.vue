<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
// FE-6: Tooltip moderno em vez de title="..." nativo.
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// RT-5: reconciliação ao reconectar WebSocket (mensagens que chegaram
// durante disconnect ficavam invisíveis na sala aberta).
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import MessageThread from './MessageThread.vue';
import MessageComposer from './MessageComposer.vue';
import GroupSettingsDrawer from './GroupSettingsDrawer.vue';
import DmUserDrawer from './DmUserDrawer.vue';
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
// DM: drawer unificado de "Dados do contato" — substitui o antigo showDmFavorites.
// Tem 3 sub-views: 'main' (perfil + ações), 'files', 'favorites'.
const showDmDrawer = ref(false);
const dmDrawerView = ref('main');
const replyTarget = ref(null);
const wasLoaded = ref(false);

const openSettings = (tab = 'members') => {
  settingsTab.value = tab;
  showSettings.value = true;
};

const openDmDrawer = (subView = 'main') => {
  dmDrawerView.value = subView;
  showDmDrawer.value = true;
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

// RT-5: reconciliação no reconnect. Quando WebSocket reconnecta, refetcha
// mensagens da sala atual a partir do zero — eventos perdidos durante o
// disconnect (room.updated, message.created) entram via re-fetch. ChatShell
// também listenera; este handler aqui foca em recarregar a thread da sala
// aberta (refetch de messages é mais caro que rooms list).
const onWebsocketReconnect = () => {
  if (!props.roomId) return;
  store.dispatch('internalChatMessages/fetch', { roomId: Number(props.roomId) });
};

onMounted(() => {
  loadRoom(props.roomId);
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, onWebsocketReconnect);
});
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
//
// FE-23 (auditoria 2026-05-18): debounce 300ms protege contra redirects em
// `room === null` transiente — situação que rolava durante refetch após
// cable `room.updated` (a sala "some" do getter por ~50ms enquanto o
// upsert no store é processado) e durante account-switch.
let redirectTimer = null;
watch(room, val => {
  if (val) {
    wasLoaded.value = true;
    if (redirectTimer) {
      clearTimeout(redirectTimer);
      redirectTimer = null;
    }
  } else if (wasLoaded.value) {
    redirectTimer = setTimeout(() => {
      if (!room.value) {
        showSettings.value = false;
        router.push({
          name: 'internal_chat_home',
          params: { accountId: route.params.accountId },
        });
      }
      redirectTimer = null;
    }, 300);
  }
});
onBeforeUnmount(() => {
  if (redirectTimer) clearTimeout(redirectTimer);
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, onWebsocketReconnect);
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

// Mobile: botão "voltar" no header volta pra lista de salas (sem ele, em
// telas <768px o user fica preso na sala sem caminho de volta visível).
const goBackToList = () => {
  router.push({
    name: 'internal_chat_home',
    params: { accountId: route.params.accountId },
  });
};
</script>

<template>
  <div v-if="room" class="flex flex-col flex-1 h-full">
    <header
      class="flex items-center gap-2 px-2 md:px-3 h-[60px] border-b border-n-weak bg-n-solid-1"
    >
      <!-- Mobile: voltar pra lista de salas. Some em md+ onde a sidebar
           já está visível ao lado. -->
      <button
        type="button"
        class="md:hidden inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition shrink-0"
        @click="goBackToList"
      >
        <span class="i-lucide-arrow-left text-xl" />
      </button>
      <!-- Header clicável: avatar+nome abrem o drawer (group: settings;
           DM: dados do contato). Sem tooltip, sem hover-bg, sem outline
           no foco — affordância visual já é clara (avatar+nome clicáveis
           = padrão WhatsApp/Telegram). -->
      <div class="flex-1 min-w-0">
        <button
          type="button"
          class="flex items-center w-full min-w-0 gap-3 text-start cursor-pointer outline-none focus:outline-none"
          @click="room.kind === 'group' ? openSettings('edit') : openDmDrawer('main')"
        >
          <span class="relative shrink-0">
            <Avatar :key="room.avatar_updated_at || 'no-avatar'" :name="room.name || $t('INTERNAL_CHAT.ROOM.DEFAULT_TITLE')" :src="room.avatar_url || ''" :size="36" rounded-full />
            <PresenceDot
              v-if="otherUserId"
              :user-id="otherUserId"
              :size="10"
              class="absolute bottom-0 right-0"
            />
          </span>
          <span class="flex-1 min-w-0">
            <span class="block text-sm font-semibold truncate text-n-slate-12">
              {{ room.name || $t('INTERNAL_CHAT.ROOM.DEFAULT_TITLE') }}
            </span>
            <span class="block text-xs text-n-slate-11">
              {{ subtitleText }}
            </span>
          </span>
        </button>
      </div>
      <Tooltip v-if="room.kind === 'direct'" :label="$t('INTERNAL_CHAT.ROOM.FAVORITES_TOOLTIP')">
        <button
          type="button"
          class="inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
          @click="openDmDrawer('favorites')"
        >
          <span class="i-lucide-star text-lg" />
        </button>
      </Tooltip>
      <Tooltip v-if="room.kind === 'group'" :label="$t('INTERNAL_CHAT.ROOM.FAVORITES_TOOLTIP')">
        <button
          type="button"
          class="inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
          @click="openSettings('favorites')"
        >
          <span class="i-lucide-star text-lg" />
        </button>
      </Tooltip>
      <Tooltip v-if="room.kind === 'group'" :label="$t('INTERNAL_CHAT.ROOM.SETTINGS_TOOLTIP')">
        <button
          type="button"
          class="inline-flex items-center justify-center w-9 h-9 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition"
          @click="openSettings('members')"
        >
          <span class="i-lucide-settings text-lg" />
        </button>
      </Tooltip>
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

    <!-- Transition `ic-drawer` (CSS em styles/internal-chat.css):
         backdrop fade + aside slide-in da direita. Tempo curto (200ms
         fade / 280ms slide) pra não atrasar interação. Mesma animação
         pros 2 drawers — consistência visual. -->
    <Transition name="ic-drawer">
      <GroupSettingsDrawer
        v-if="showSettings && room.kind === 'group'"
        :room="room"
        :initial-tab="settingsTab"
        @close="showSettings = false"
      />
    </Transition>

    <!-- DM: drawer unificado de "Dados do contato" — substituiu o drawer
         simples antigo de Favoritos. Contém: perfil + arquivos + favoritos +
         ações (silenciar/arquivar). -->
    <Transition name="ic-drawer">
      <DmUserDrawer
        v-if="showDmDrawer && room.kind === 'direct' && otherUserId"
        :room="room"
        :other-user-id="otherUserId"
        :initial-view="dmDrawerView"
        @close="showDmDrawer = false"
      />
    </Transition>
  </div>
  <div v-else class="flex items-center justify-center flex-1 text-sm text-n-slate-11">
    {{ $t('INTERNAL_CHAT.ROOM.LOADING_CONVERSATION') }}
  </div>
</template>
