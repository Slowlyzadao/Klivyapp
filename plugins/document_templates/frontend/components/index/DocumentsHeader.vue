<script setup>
// Header da DocumentsIndex.
//
// Layout (alinhado ao mockup oficial Klivy M3):
//   Row 1: título "Documentos" + subtítulo                 [+ Novo modelo]
//   Row 2: [Meus modelos N][Biblioteca Klivy M]   [🔍 search] [Grade|Lista] [Tipo ▼]
//
// Componente "burro" — todo o estado vem por props/v-model. CTA "Novo
// modelo" só aparece pra admin (showNewButton) — visível em ambas as tabs
// pra dar acesso direto à criação a partir de qualquer contexto.

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { DOCUMENT_TYPE_LABELS } from '../../constants/documentTypes';
import SegmentedTabs from '../shared/SegmentedTabs.vue';
import ViewToggle from '../shared/ViewToggle.vue';

const props = defineProps({
  search: { type: String, default: '' },
  documentTypeFilter: { type: String, default: '' },
  activeTab: {
    type: String,
    default: 'owned',
    validator: (v) => ['owned', 'all', 'klivy'].includes(v),
  },
  viewMode: {
    type: String,
    default: 'grid',
    validator: (v) => ['grid', 'list'].includes(v),
  },
  ownedCount: { type: Number, default: 0 },
  allCount: { type: Number, default: 0 },
  klivyCount: { type: Number, default: 0 },
  showNewButton: { type: Boolean, default: true },
});

const emit = defineEmits([
  'update:search',
  'update:documentTypeFilter',
  'update:activeTab',
  'update:viewMode',
  'click-new',
]);

const { t } = useI18n();

const tabs = computed(() => [
  {
    value: 'owned',
    label: t('DOCUMENT_TEMPLATES.INDEX.TAB_OWNED'),
    icon: 'i-lucide-folder',
    count: props.ownedCount,
  },
  {
    value: 'all',
    label: t('DOCUMENT_TEMPLATES.INDEX.TAB_ALL'),
    icon: 'i-lucide-layers',
    count: props.allCount,
  },
  {
    value: 'klivy',
    label: t('DOCUMENT_TEMPLATES.INDEX.TAB_KLIVY'),
    icon: 'i-lucide-library',
    count: props.klivyCount,
  },
]);

const documentTypeOptions = computed(() => [
  { value: '', label: t('DOCUMENT_TEMPLATES.FILTERS.ALL_TYPES') },
  ...Object.entries(DOCUMENT_TYPE_LABELS).map(([value, label]) => ({ value, label })),
]);
</script>

<template>
  <header class="docs-header">
    <!-- Row 1: título + CTA primário -->
    <div class="docs-header__hero">
      <div class="docs-header__hero-text">
        <h1 class="docs-header__title">
          {{ t('DOCUMENT_TEMPLATES.INDEX.TITLE') }}
        </h1>
        <p class="docs-header__subtitle">
          {{ t('DOCUMENT_TEMPLATES.INDEX.SUBTITLE') }}
        </p>
      </div>
      <button
        v-if="showNewButton"
        type="button"
        class="docs-header__cta"
        @click="emit('click-new')"
      >
        <span class="i-lucide-plus docs-header__cta-icon" />
        <span>{{ t('DOCUMENT_TEMPLATES.INDEX.NEW_TEMPLATE') }}</span>
      </button>
    </div>

    <!-- Row 2: tabs + filtros -->
    <div class="docs-header__toolbar">
      <SegmentedTabs
        :model-value="activeTab"
        :options="tabs"
        @update:model-value="(v) => emit('update:activeTab', v)"
      />

      <div class="docs-header__filters">
        <label class="docs-header__search">
          <span class="i-lucide-search docs-header__search-icon" />
          <input
            :value="search"
            type="search"
            class="docs-header__search-input"
            :placeholder="t('DOCUMENT_TEMPLATES.INDEX.SEARCH_PLACEHOLDER')"
            @input="(e) => emit('update:search', e.target.value)"
          />
        </label>

        <ViewToggle
          :model-value="viewMode"
          @update:model-value="(v) => emit('update:viewMode', v)"
        />

        <div class="docs-header__select-wrap">
          <select
            :value="documentTypeFilter"
            class="docs-header__select"
            @change="(e) => emit('update:documentTypeFilter', e.target.value)"
          >
            <option
              v-for="option in documentTypeOptions"
              :key="option.value"
              :value="option.value"
            >
              {{ option.label }}
            </option>
          </select>
          <span class="i-lucide-chevron-down docs-header__select-chevron" />
        </div>
      </div>
    </div>
  </header>
</template>

<style lang="scss" scoped>
@use '../../styles/index/documents-header';
</style>
