<script setup>
// Seção horizontal de modelos Klivy no topo da DocumentsIndex.
// Mostra até `limit` cards (default 6) com link "Ver biblioteca completa".
// Click no card abre drawer ou modal de uso (gerenciado no pai).

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import TemplateCard from './TemplateCard.vue';

const props = defineProps({
  templates: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  limit: { type: Number, default: 6 },
});

const emit = defineEmits(['use-klivy', 'open-library']);

const { t } = useI18n();

const visibleTemplates = computed(() => props.templates.slice(0, props.limit));
const hasMore = computed(() => props.templates.length > props.limit);
</script>

<template>
  <section
    v-if="loading || visibleTemplates.length > 0"
    class="klivy-library-section"
  >
    <header class="klivy-library-section__header">
      <h2 class="klivy-library-section__title">
        <span class="i-lucide-library klivy-library-section__title-icon" />
        {{ t('DOCUMENT_TEMPLATES.INDEX.KLIVY_TITLE') }}
      </h2>
      <button
        v-if="hasMore || visibleTemplates.length > 0"
        type="button"
        class="klivy-library-section__see-all"
        @click="emit('open-library')"
      >
        {{ t('DOCUMENT_TEMPLATES.INDEX.SEE_ALL_KLIVY') }}
        <span class="i-lucide-arrow-right" />
      </button>
    </header>

    <div v-if="loading" class="klivy-library-section__loading">
      <span class="i-lucide-loader-circle" />
    </div>

    <div v-else class="klivy-library-section__cards">
      <TemplateCard
        v-for="template in visibleTemplates"
        :key="template.id"
        :template="template"
        variant="klivy"
        @use-klivy="emit('use-klivy', $event)"
      />
    </div>
  </section>
</template>

<style lang="scss" scoped>
@use '../../styles/index/klivy-library-section';
</style>
