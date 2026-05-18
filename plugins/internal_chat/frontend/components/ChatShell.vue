<script setup>
import { computed, onMounted, ref } from 'vue';
import { useStore } from 'vuex';
import { useRoute, useRouter } from 'vue-router';
import RoomList from './RoomList.vue';
import NewRoomModal from './NewRoomModal.vue';
import '@plugins/internal_chat/frontend/styles/internal-chat.css';

const store = useStore();
const route = useRoute();
const router = useRouter();
const showNewRoomModal = ref(false);

const unreadMentions = computed(
  () => store.getters['internalChatMentions/getUnreadCount']
);

const goToMentions = () => {
  router.push({
    name: 'internal_chat_mentions',
    params: { accountId: route.params.accountId },
  });
};

onMounted(async () => {
  await store.dispatch('internalChatRooms/fetch');
  await store.dispatch('internalChatRooms/fetchUnreadSummary');
  store.dispatch('internalChatMentions/fetchUnreadCount');
  // garante carga de agentes da conta para o modal de nova sala
  if (!store.getters['agents/getAgents']?.length) {
    store.dispatch('agents/get');
  }
});
</script>

<template>
  <div class="flex w-full h-full bg-n-background">
    <aside
      class="flex flex-col w-[320px] border-r border-n-weak h-full bg-n-solid-1"
    >
      <header
        class="flex items-center justify-between px-4 py-3 border-b border-n-weak"
      >
        <h2 class="text-base font-semibold text-n-slate-12">Chat interno</h2>
        <div class="flex items-center gap-1">
          <button
            type="button"
            class="relative inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12 transition"
            title="Menções"
            @click="goToMentions"
          >
            <span class="i-lucide-at-sign text-lg" />
            <span
              v-if="unreadMentions > 0"
              class="absolute -top-0.5 -right-0.5 inline-flex items-center justify-center min-w-[16px] h-[16px] px-1 text-[10px] font-semibold rounded-full bg-n-brand text-white"
            >
              {{ unreadMentions > 99 ? '99+' : unreadMentions }}
            </span>
          </button>
          <button
            type="button"
            class="inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-slate-3 hover:text-n-slate-12 transition"
            title="Nova conversa"
            @click="showNewRoomModal = true"
          >
            <span class="i-lucide-square-pen text-lg" />
          </button>
        </div>
      </header>
      <RoomList />
    </aside>

    <main class="flex-1 flex flex-col h-full bg-n-background">
      <router-view />
    </main>

    <NewRoomModal
      v-if="showNewRoomModal"
      @close="showNewRoomModal = false"
    />
  </div>
</template>
