<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import RoomList from './RoomList.vue';
import NewRoomModal from './NewRoomModal.vue';
// FE-6 (auditoria 2026-05-18): Tooltip moderno do beclinic_core
// substituindo `title="..."` HTML nativo (lento, dispensável em screen
// readers, quebra em containers com overflow:hidden).
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
// RT-5 (auditoria 2026-05-18): reconciliation no reconnect — mensagens
// que chegaram durante disconnect ficavam silenciosamente faltando.
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import '@plugins/internal_chat/frontend/styles/internal-chat.css';

const store = useStore();
const route = useRoute();
const router = useRouter();
const showNewRoomModal = ref(false);

// Responsividade estilo WhatsApp Web (<768px): com sala aberta ou tela de
// menções aberta, esconde a sidebar e mostra só o conteúdo (full width).
// Sem nada aberto, mostra só a lista (sidebar full width, main escondido).
// Em desktop (md+), layout normal lado-a-lado com sidebar fixa de 320px.
const isInRoom = computed(() => {
  // Qualquer rota que carrega conteúdo na <main> (não só salas) faz a
  // sidebar sumir no mobile. Atualmente: salas + menções.
  return (
    !!route.params.roomId ||
    route.name === 'internal_chat_mentions'
  );
});

const unreadMentions = computed(
  () => store.getters['internalChatMentions/getUnreadCount']
);

const goToMentions = () => {
  router.push({
    name: 'internal_chat_mentions',
    params: { accountId: route.params.accountId },
  });
};

// MT-14 a MT-19 — defesa em profundidade pra account-switch. Hoje o
// SidebarAccountSwitcher faz full reload (window.location.href), o que zera
// os stores automaticamente. Esse watcher cobre o cenário em que algum dia o
// switcher passe a usar router.push (SPA navigation) — sem o reset, dados de
// uma clínica vazariam pra outra. Cada store reseta seu próprio state
// (módulo namespaced) ao detectar mudança de accountId.
const STORES_TO_RESET = [
  'internalChatRooms',
  'internalChatMessages',
  'internalChatMentions',
  'internalChatTyping',
  'internalChatStickers',
];

watch(
  () => Number(route.params.accountId),
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      STORES_TO_RESET.forEach(ns => store.dispatch(`${ns}/reset`));
    }
  }
);

// RT-5: reconciliação ao reconectar WebSocket. Cenário: user fica com
// laptop dormindo / rede instável → cable disconnect → outras pessoas
// mandam msgs no chat interno → cable reconnect → mensagens que chegaram
// durante o disconnect ficavam invisíveis até reload manual da página.
// Ao receber `WEBSOCKET_RECONNECT`, refetch rooms + unread summary +
// mentions count. A sala aberta (RoomView) também listenará independente
// — esse handler aqui cobre o caso de nenhuma sala estar aberta.
const onWebsocketReconnect = () => {
  store.dispatch('internalChatRooms/fetch');
  store.dispatch('internalChatRooms/fetchUnreadSummary');
  store.dispatch('internalChatMentions/fetchUnreadCount');
};

onMounted(async () => {
  await store.dispatch('internalChatRooms/fetch');
  await store.dispatch('internalChatRooms/fetchUnreadSummary');
  store.dispatch('internalChatMentions/fetchUnreadCount');
  // garante carga de agentes da conta para o modal de nova sala
  if (!store.getters['agents/getAgents']?.length) {
    store.dispatch('agents/get');
  }
  emitter.on(BUS_EVENTS.WEBSOCKET_RECONNECT, onWebsocketReconnect);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.WEBSOCKET_RECONNECT, onWebsocketReconnect);
});
</script>

<template>
  <!-- Class `ic-app`: scope do reset de margens default <p>/<h*> definido
       em internal-chat.css. Cobre RoomList, RoomView, MentionsView, DM e
       GroupSettingsDrawer (todos descendentes). Teleports (NewRoomModal,
       MessageActionsMenu) aplicam a class separadamente. -->
  <div class="ic-app flex w-full h-full bg-n-background">
    <aside
      class="flex-col w-full md:w-[320px] md:shrink-0 border-r border-n-weak h-full bg-n-solid-1"
      :class="isInRoom ? 'hidden md:flex' : 'flex'"
    >
      <header
        class="flex items-center justify-between px-4 py-3 min-h-[60px] border-b border-n-weak"
      >
        <h2 class="text-base font-semibold text-n-slate-12">{{ $t('INTERNAL_CHAT.SIDEBAR.TITLE') }}</h2>
        <div class="flex items-center gap-4">
          <Tooltip :label="$t('INTERNAL_CHAT.SIDEBAR.MENTIONS_TOOLTIP')" position="bottom">
            <button
              type="button"
              class="relative inline-flex items-center justify-center p-0 rounded-md text-n-slate-11 hover:text-n-slate-12 transition"
              @click="goToMentions"
            >
              <span class="i-lucide-at-sign text-lg" />
              <!-- Sem padding no botão, o badge precisa de offset maior pra
                   ficar no canto superior-direito sem tampar o @. Half-out
                   pattern (Material/iOS): metade do badge fica fora do
                   ícone, criando o efeito de "selo" sem cobrir o glifo. -->
              <span
                v-if="unreadMentions > 0"
                class="absolute -top-2 -right-2 inline-flex items-center justify-center min-w-[16px] h-[16px] px-1 text-[10px] font-semibold rounded-full bg-n-brand text-white ring-2 ring-n-solid-1"
              >
                {{ unreadMentions > 99 ? '99+' : unreadMentions }}
              </span>
            </button>
          </Tooltip>
          <Tooltip :label="$t('INTERNAL_CHAT.SIDEBAR.NEW_ROOM_TOOLTIP')" position="bottom">
            <button
              type="button"
              class="inline-flex items-center justify-center p-0 rounded-md text-n-slate-11 hover:text-n-slate-12 transition"
              @click="showNewRoomModal = true"
            >
              <span class="i-lucide-message-square-plus text-lg" />
            </button>
          </Tooltip>
        </div>
      </header>
      <RoomList />
    </aside>

    <main
      class="flex-1 flex-col h-full bg-n-background min-w-0"
      :class="isInRoom ? 'flex' : 'hidden md:flex'"
    >
      <router-view />
    </main>

    <NewRoomModal
      v-if="showNewRoomModal"
      @close="showNewRoomModal = false"
    />
  </div>
</template>
