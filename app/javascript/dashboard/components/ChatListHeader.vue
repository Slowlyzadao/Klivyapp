<script setup>
import './chat-list-header.css';
import { ref, computed, nextTick } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { formatNumber } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';
import { useEmitter } from 'dashboard/composables/emitter';

import ConversationBasicFilter from './widgets/conversation/ConversationBasicFilter.vue';
import SwitchLayout from 'dashboard/routes/dashboard/conversation/search/SwitchLayout.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  pageTitle: { type: String, required: true },
  hasAppliedFilters: { type: Boolean, required: true },
  hasActiveFolders: { type: Boolean, required: true },
  activeStatus: { type: String, required: true },
  isOnExpandedLayout: { type: Boolean, required: true },
  conversationStats: { type: Object, required: true },
  isListLoading: { type: Boolean, required: true },
});

const emit = defineEmits([
  'addFolders',
  'deleteFolders',
  'resetFilters',
  'basicFilterChange',
  'filtersModal',
  'searchQuery',
]);

const { uiSettings, updateUISettings } = useUISettings();

const onBasicFilterChange = (value, type) => {
  emit('basicFilterChange', value, type);
};

const hasAppliedFiltersOrActiveFolders = computed(() => {
  return props.hasAppliedFilters || props.hasActiveFolders;
});

const allCount = computed(() => props.conversationStats?.allCount || 0);
const formattedAllCount = computed(() => formatNumber(allCount.value));

// ── Search ───────────────────────────────────────────────────────
const showSearch = ref(false);
const searchQuery = ref('');
const searchInputRef = ref(null);

const toggleSearch = async () => {
  showSearch.value = !showSearch.value;
  if (showSearch.value) {
    await nextTick();
    searchInputRef.value?.focus();
  } else {
    searchQuery.value = '';
    emit('searchQuery', '');
  }
};

const onSearchInput = () => {
  emit('searchQuery', searchQuery.value);
};

const clearSearch = () => {
  searchQuery.value = '';
  emit('searchQuery', '');
  searchInputRef.value?.focus();
};

useEmitter('clearSearchInput', () => {
  showSearch.value = false;
  searchQuery.value = '';
  emit('searchQuery', '');
});
// ─────────────────────────────────────────────────────────────────

const toggleConversationLayout = () => {
  const { LAYOUT_TYPES } = wootConstants;
  const {
    conversation_display_type: conversationDisplayType = LAYOUT_TYPES.CONDENSED,
  } = uiSettings.value;
  const newViewType =
    conversationDisplayType === LAYOUT_TYPES.CONDENSED
      ? LAYOUT_TYPES.EXPANDED
      : LAYOUT_TYPES.CONDENSED;
  updateUISettings({
    conversation_display_type: newViewType,
    previously_used_conversation_display_type: newViewType,
  });
};
</script>

<template>
  <div>
    <!-- Row 1: Title + action icons -->
    <div
      class="flex items-center justify-between gap-2 px-3 h-[3.25rem]"
      :class="{
        'border-b border-n-strong':
          hasAppliedFiltersOrActiveFolders && !showSearch,
      }"
    >
      <div class="flex items-center justify-center min-w-0">
        <h1
          class="text-base font-medium truncate text-n-slate-12"
          :title="pageTitle"
        >
          {{ pageTitle }}
        </h1>
        <span
          v-if="
            allCount > 0 && hasAppliedFiltersOrActiveFolders && !isListLoading
          "
          class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
          :title="allCount"
        >
          {{ formattedAllCount }}
        </span>
        <span
          v-if="!hasAppliedFiltersOrActiveFolders"
          class="px-2 py-1 my-0.5 mx-1 rounded-md capitalize bg-n-slate-3 text-xxs text-n-slate-12 shrink-0"
        >
          {{ $t(`CHAT_LIST.CHAT_STATUS_FILTER_ITEMS.${activeStatus}.TEXT`) }}
        </span>
      </div>
      <div class="flex items-center gap-1">
        <template v-if="hasAppliedFilters && !hasActiveFolders">
          <div class="relative">
            <NextButton
              v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.ADD.SAVE_BUTTON')"
              icon="i-lucide-save"
              slate
              xs
              faded
              @click="emit('addFolders')"
            />
            <div
              id="saveFilterTeleportTarget"
              class="absolute z-50 mt-2"
              :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
            />
          </div>
          <NextButton
            v-tooltip.top-end="$t('FILTER.CLEAR_BUTTON_LABEL')"
            icon="i-lucide-circle-x"
            ruby
            faded
            xs
            @click="emit('resetFilters')"
          />
        </template>
        <template v-if="hasActiveFolders">
          <div class="relative">
            <NextButton
              id="toggleConversationFilterButton"
              v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.EDIT.EDIT_BUTTON')"
              icon="i-lucide-pen-line"
              slate
              xs
              faded
              @click="emit('filtersModal')"
            />
            <div
              id="conversationFilterTeleportTarget"
              class="absolute z-50 mt-2"
              :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
            />
          </div>
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.top-end="$t('FILTER.CUSTOM_VIEWS.DELETE.DELETE_BUTTON')"
            icon="i-lucide-trash-2"
            ruby
            xs
            faded
            @click="emit('deleteFolders')"
          />
        </template>
        <div v-else class="relative">
          <NextButton
            id="toggleConversationFilterButton"
            v-tooltip.right="$t('FILTER.TOOLTIP_LABEL')"
            icon="i-lucide-list-filter"
            slate
            xs
            faded
            @click="emit('filtersModal')"
          />
          <div
            id="conversationFilterTeleportTarget"
            class="absolute z-50 mt-2"
            :class="{ 'ltr:right-0 rtl:left-0': isOnExpandedLayout }"
          />
        </div>
        <ConversationBasicFilter
          v-if="!hasAppliedFiltersOrActiveFolders"
          :is-on-expanded-layout="isOnExpandedLayout"
          @change-filter="onBasicFilterChange"
        />
        <SwitchLayout
          :is-on-expanded-layout="isOnExpandedLayout"
          @toggle="toggleConversationLayout"
        />
        <!-- Search toggle button -->
        <NextButton
          v-tooltip.left="'Buscar contato'"
          icon="i-lucide-search"
          :slate="!showSearch"
          :blue="showSearch"
          xs
          faded
          @click="toggleSearch"
        />
      </div>
    </div>

    <!-- Row 2: Search input (expands below header when active) -->
    <div v-if="showSearch" class="clh-search-row">
      <div class="relative flex-1">
        <input
          ref="searchInputRef"
          v-model="searchQuery"
          type="text"
          placeholder="Buscar por contato..."
          class="clh-search-input"
          @input="onSearchInput"
          @keydown.escape="toggleSearch"
        />
        <button
          v-if="searchQuery"
          class="clh-search-clear"
          @click="clearSearch"
        >
          <i class="i-lucide-x w-3.5 h-3.5" />
        </button>
      </div>
    </div>
  </div>
</template>
