<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue';
import { useStore } from 'vuex';
// PERF-25 (auditoria 2026-05-19): virtualização via vue-virtual-scroller
// (mesma lib que o Chatwoot core usa em ChatList.vue). RecycleScroller
// porque item height é razoavelmente constante (~76px por RoomListItem).
// Sem isso, conta com 500 salas renderiza 500 nodes DOM mesmo quando só
// 12 estão visíveis — slow scroll + scroll lag.
import { RecycleScroller } from 'vue-virtual-scroller';
import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';
import RoomListItem from './RoomListItem.vue';
// FE-X: usa o SearchInput padrão do beclinic_core em vez de input cru +
// ícone absoluto (que tinha overlap visual com o placeholder em algumas
// fontes/densidades). Componente compartilhado já trata posicionamento
// do ícone, foco, e cor.
import SearchInput from '@plugins/beclinic_core/frontend/components/SearchInput.vue';

const store = useStore();
const search = ref('');
// PERF-26 (auditoria 2026-05-18): debounce 150ms no input — antes cada
// keystroke disparava re-filter de TODAS as salas. Conta com 500 salas
// e digitação rápida (5 keys/s) gerava 2500 filter ops/s. Agora o
// computed só recalcula 150ms após o último keystroke.
const debouncedSearch = ref('');
let debounceTimer = null;
watch(search, val => {
  clearTimeout(debounceTimer);
  debounceTimer = setTimeout(() => {
    debouncedSearch.value = val;
  }, 150);
});
onBeforeUnmount(() => clearTimeout(debounceTimer));

const rooms = computed(() => store.getters['internalChatRooms/getAllRooms']);
const archivedRooms = computed(
  () => store.getters['internalChatRooms/getArchivedRooms']
);
const isFetching = computed(
  () => store.getters['internalChatRooms/getUIFlags'].isFetching
);

// Aba "Conversas" (ativas) vs "Arquivadas". As arquivadas são recarregadas
// toda vez que a aba é aberta (dado fresco, barato; reflete desarquivamentos).
const activeTab = ref('active');
const selectTab = async tab => {
  activeTab.value = tab;
  if (tab === 'archived') {
    await store.dispatch('internalChatRooms/fetchArchived');
  }
};

const sourceRooms = computed(() =>
  activeTab.value === 'archived' ? archivedRooms.value : rooms.value
);

const filtered = computed(() => {
  if (!debouncedSearch.value) return sourceRooms.value;
  const q = debouncedSearch.value.toLowerCase();
  return sourceRooms.value.filter(r => (r.name || '').toLowerCase().includes(q));
});
</script>

<template>
  <div class="flex flex-col flex-1 overflow-hidden">
    <div class="px-3 py-2">
      <SearchInput
        v-model="search"
        class="ic-roomlist-search"
        :placeholder="$t('INTERNAL_CHAT.SIDEBAR.SEARCH_PLACEHOLDER')"
      />
    </div>

    <!-- Abas Conversas / Arquivadas — caminho de volta pra desarquivar. -->
    <div class="flex gap-1 px-3 pb-2">
      <button
        type="button"
        class="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition"
        :class="activeTab === 'active'
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:bg-n-alpha-1'"
        @click="selectTab('active')"
      >
        {{ $t('INTERNAL_CHAT.SIDEBAR.TAB_ACTIVE') }}
      </button>
      <button
        type="button"
        class="flex-1 px-3 py-1.5 text-xs font-medium rounded-md transition"
        :class="activeTab === 'archived'
          ? 'bg-n-alpha-2 text-n-slate-12'
          : 'text-n-slate-11 hover:bg-n-alpha-1'"
        @click="selectTab('archived')"
      >
        {{ $t('INTERNAL_CHAT.SIDEBAR.TAB_ARCHIVED') }}
      </button>
    </div>

    <div
      v-if="isFetching && rooms.length === 0"
      class="flex items-center justify-center flex-1 text-sm text-n-slate-11"
    >
      {{ $t('INTERNAL_CHAT.SIDEBAR.LOADING') }}
    </div>

    <div
      v-else-if="filtered.length === 0"
      class="flex flex-col items-center justify-center flex-1 px-6 text-center text-n-slate-11"
    >
      <span
        :class="activeTab === 'archived' ? 'i-lucide-archive' : 'i-lucide-messages-square'"
        class="text-4xl mb-2 text-n-slate-9"
      />
      <p class="text-sm">
        {{ activeTab === 'archived'
          ? $t('INTERNAL_CHAT.SIDEBAR.EMPTY_ARCHIVED')
          : $t('INTERNAL_CHAT.SIDEBAR.EMPTY') }}
      </p>
      <p v-if="activeTab !== 'archived'" class="mt-1 text-xs text-n-slate-10">
        {{ $t('INTERNAL_CHAT.SIDEBAR.EMPTY_HINT') }}
      </p>
    </div>

    <!-- PERF-25: RecycleScroller renderiza apenas os items visíveis +
         buffer; `key-field="id"` evita remount em mudanças de ordem.
         `item-size=66` ≈ height real do RoomListItem (avatar 40 + py-2.5
         interno = 60) + 6px de respiro entre cards. Reduzir item-size
         encosta os cards (apertado) — aumentar dá ar a mais. -->
    <RecycleScroller
      v-else
      class="flex-1 ic-thread-scroll"
      :items="filtered"
      :item-size="66"
      key-field="id"
    >
      <template #default="{ item }">
        <RoomListItem :room="item" />
      </template>
    </RecycleScroller>
  </div>
</template>

<style scoped lang="scss">
/* SearchInput por padrão tem min-width:220px / max-width:380px (uso em
   toolbars largas tipo /patients). Aqui ele vive na sidebar de ~300px de
   largura — força 100% pra ocupar o espaço disponível sem clamps. */
.ic-roomlist-search {
  min-width: 0;
  max-width: none;
  width: 100%;
}
</style>
