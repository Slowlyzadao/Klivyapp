<script setup>
// Grid de TemplateCard. Stateless — recebe lista filtrada, mostra estado
// vazio quando lista é nula, propaga eventos pra cima.
//
// Aceita textos customizados de empty state via prop pra cobrir tabs
// diferentes (Meus / Klivy).

import TemplateCard from './TemplateCard.vue';
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

const emit = defineEmits(['open', 'menu', 'use-klivy']);
</script>

<template>
  <section class="template-grid">
    <div
      v-if="loading"
      class="template-grid__loading"
      role="status"
      aria-live="polite"
    >
      <span class="i-lucide-loader-circle template-grid__loading-icon" />
    </div>

    <EmptyPlaceholder
      v-else-if="templates.length === 0"
      :title="emptyTitle"
      :description="emptyDescription"
      :icon-class="variant === 'klivy'
        ? 'i-lucide-library'
        : 'i-lucide-file-plus'"
    />

    <div v-else class="template-grid__cards">
      <TemplateCard
        v-for="template in templates"
        :key="template.id"
        :template="template"
        :variant="variant"
        @open="emit('open', $event)"
        @menu="emit('menu', $event)"
        @use-klivy="emit('use-klivy', $event)"
      />
    </div>
  </section>
</template>

<style lang="scss" scoped>
@use '../../styles/index/template-grid';
</style>
