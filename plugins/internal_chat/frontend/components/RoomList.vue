<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import RoomListItem from './RoomListItem.vue';

const store = useStore();
const search = ref('');

const rooms = computed(() => store.getters['internalChatRooms/getAllRooms']);
const isFetching = computed(
  () => store.getters['internalChatRooms/getUIFlags'].isFetching
);

const filtered = computed(() => {
  if (!search.value) return rooms.value;
  const q = search.value.toLowerCase();
  return rooms.value.filter(r => (r.name || '').toLowerCase().includes(q));
});
</script>

<template>
  <div class="flex flex-col flex-1 overflow-hidden">
    <div class="px-3 py-2 border-b border-n-weak">
      <div class="relative">
        <span
          class="absolute -translate-y-1/2 i-lucide-search left-3 top-1/2 text-n-slate-10"
        />
        <input
          v-model="search"
          type="text"
          placeholder="Buscar conversa..."
          class="w-full py-2 pl-9 pr-3 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
        >
      </div>
    </div>

    <div
      v-if="isFetching && rooms.length === 0"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      Carregando…
    </div>

    <div
      v-else-if="filtered.length === 0"
      class="flex flex-col items-center justify-center flex-1 px-6 text-center text-n-slate-11"
    >
      <span class="i-lucide-messages-square text-4xl mb-2 text-n-slate-9" />
      <p class="text-sm">Nenhuma conversa ainda</p>
      <p class="mt-1 text-xs text-n-slate-10">
        Clique no ícone acima para iniciar
      </p>
    </div>

    <ul
      v-else
      class="flex-1 overflow-y-auto ic-thread-scroll"
    >
      <RoomListItem
        v-for="room in filtered"
        :key="room.id"
        :room="room"
      />
    </ul>
  </div>
</template>
