<script setup>
// TemplateList — versão "list" da coleção. Container white card com header
// fake (column labels) + lista de TemplateListRow.

import { useI18n } from 'vue-i18n';
import TemplateListRow from './TemplateListRow.vue';
import EmptyPlaceholder from './EmptyPlaceholder.vue';

defineProps({
  templates: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  variant: {
    type: String,
    default: 'owned',
    validator: (v) => ['owned', 'klivy'].includes(v),
  },
  emptyTitle: { type: String, default: '' },
  emptyDescription: { type: String, default: '' },
});

const emit = defineEmits(['open', 'menu']);

const { t } = useI18n();
</script>

<template>
  <section class="tpl-list">
    <div
      v-if="loading"
      class="tpl-list__loading"
      role="status"
      aria-live="polite"
    >
      <span class="i-lucide-loader-circle tpl-list__loading-icon" />
    </div>

    <EmptyPlaceholder
      v-else-if="templates.length === 0"
      :title="emptyTitle"
      :description="emptyDescription"
      :icon-class="variant === 'klivy' ? 'i-lucide-library' : 'i-lucide-file-plus'"
    />

    <div v-else class="tpl-list__card">
      <header class="tpl-list__header">
        <span class="tpl-list__col tpl-list__col--name">
          {{ t('DOCUMENT_TEMPLATES.LIST.COL_NAME') }}
        </span>
        <span class="tpl-list__col tpl-list__col--badge">
          {{ t('DOCUMENT_TEMPLATES.LIST.COL_ORIGIN') }}
        </span>
        <span class="tpl-list__col tpl-list__col--meta">
          {{ t('DOCUMENT_TEMPLATES.LIST.COL_VERSION') }}
        </span>
        <span class="tpl-list__col tpl-list__col--menu"></span>
      </header>

      <div class="tpl-list__rows">
        <TemplateListRow
          v-for="template in templates"
          :key="template.id"
          :template="template"
          :variant="variant"
          @open="emit('open', $event)"
          @menu="emit('menu', $event)"
        />
      </div>
    </div>
  </section>
</template>

<style lang="scss" scoped>
@use '../../styles/index/template-list';
</style>
