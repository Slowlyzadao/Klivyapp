<script setup>
import { computed, ref } from 'vue';
import { useRoute } from 'vue-router';

import ContactListHeaderWrapper from 'dashboard/components-next/Contacts/ContactsHeader/ContactListHeaderWrapper.vue';
import ContactsActiveFiltersPreview from 'dashboard/components-next/Contacts/ContactsHeader/components/ContactsActiveFiltersPreview.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import ContactsLoadMore from 'dashboard/components-next/Contacts/ContactsLoadMore.vue';

const props = defineProps({
  searchValue: { type: String, default: '' },
  headerTitle: { type: String, default: '' },
  showPaginationFooter: { type: Boolean, default: true },
  currentPage: { type: Number, default: 1 },
  totalItems: { type: Number, default: 100 },
  itemsPerPage: { type: Number, default: 15 },
  pageSizeOptions: { type: Array, default: () => [15, 50, 100] },
  activeSort: { type: String, default: '' },
  activeOrdering: { type: String, default: '' },
  activeSegment: { type: Object, default: null },
  segmentsId: { type: [String, Number], default: 0 },
  hasAppliedFilters: { type: Boolean, default: false },
  isFetchingList: { type: Boolean, default: false },
  useInfiniteScroll: { type: Boolean, default: false },
  hasMore: { type: Boolean, default: false },
  isLoadingMore: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:currentPage',
  'update:sort',
  'update:pageSize',
  'search',
  'applyFilter',
  'clearFilters',
  'loadMore',
]);

const route = useRoute();

const contactListHeaderWrapper = ref(null);

const isNotSegmentView = computed(() => {
  return route.name !== 'contacts_dashboard_segments_index';
});

const isActiveView = computed(() => {
  return route.name === 'contacts_dashboard_active';
});

const isLabelView = computed(
  () => route.name === 'contacts_dashboard_labels_index'
);

const showActiveFiltersPreview = computed(() => {
  return (
    (props.hasAppliedFilters || !isNotSegmentView.value) &&
    !props.isFetchingList &&
    !isLabelView.value &&
    !isActiveView.value
  );
});

const updateCurrentPage = page => {
  emit('update:currentPage', page);
};

const openFilter = () => {
  contactListHeaderWrapper.value?.onToggleFilters();
};

const showLoadMore = computed(() => {
  return props.useInfiniteScroll && props.hasMore;
});

const showPagination = computed(() => {
  return !props.useInfiniteScroll && props.showPaginationFooter;
});
</script>

<template>
  <section
    class="flex w-full h-full gap-4 overflow-hidden justify-evenly bg-n-surface-1"
  >
    <div class="flex flex-col w-full h-full transition-all duration-300">
      <ContactListHeaderWrapper
        ref="contactListHeaderWrapper"
        :show-search="isNotSegmentView && !isActiveView"
        :search-value="searchValue"
        :active-sort="activeSort"
        :active-ordering="activeOrdering"
        :header-title="headerTitle"
        :active-segment="activeSegment"
        :segments-id="segmentsId"
        :has-applied-filters="hasAppliedFilters"
        :is-label-view="isLabelView"
        :is-active-view="isActiveView"
        @update:sort="emit('update:sort', $event)"
        @search="emit('search', $event)"
        @apply-filter="emit('applyFilter', $event)"
        @clear-filters="emit('clearFilters')"
      />
      <main class="flex-1 overflow-y-auto px-6">
        <div class="w-full mx-auto max-w-5xl">
          <ContactsActiveFiltersPreview
            v-if="showActiveFiltersPreview"
            :active-segment="activeSegment"
            @clear-filters="emit('clearFilters')"
            @open-filter="openFilter"
          />
          <slot name="default" />
          <ContactsLoadMore
            v-if="showLoadMore"
            :is-loading="isLoadingMore"
            @load-more="emit('loadMore')"
          />
        </div>
      </main>
      <!-- Rodapé de paginação: componente padrão do Klivy (beclinic_core/
           Pagination) — já integra "X por página" + "Exibindo A–B de N" +
           navegação num único card. Antes era um footer artesanal com
           `max-w-[67rem]` SEM `mx-auto` (encostava à esquerda) embrulhando o
           PaginationFooter full-width como item de flex (layout quebrado).
           Centralizado com `max-w-5xl mx-auto` + `px-6` pra casar com os
           cards acima (`<main class="px-6"><div class="mx-auto max-w-5xl">`). -->
      <footer
        v-if="showPagination"
        class="sticky bottom-0 z-10 px-6 py-3 bg-n-surface-1"
      >
        <div class="w-full mx-auto max-w-5xl">
          <Pagination
            :current-page="currentPage"
            :per-page="itemsPerPage"
            :total-count="totalItems"
            :per-page-options="pageSizeOptions"
            item-label="contatos"
            @update:current-page="updateCurrentPage"
            @update:per-page="emit('update:pageSize', $event)"
          />
        </div>
      </footer>
    </div>
  </section>
</template>
