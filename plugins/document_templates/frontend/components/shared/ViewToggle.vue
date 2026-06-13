<script setup>
// ViewToggle — alternador Grade/Lista pra coleções.
// Visual: container rounded-lg sobre bg surface-low, botão ativo em
// primary blue. Modelo v-model:modelValue padrão.

import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

defineProps({
  modelValue: {
    type: String,
    required: true,
    validator: (v) => ['grid', 'list'].includes(v),
  },
});

const emit = defineEmits(['update:modelValue']);

const { t } = useI18n();

const options = computed(() => [
  { value: 'grid', label: t('DOCUMENT_TEMPLATES.VIEW.GRID'), icon: 'i-lucide-layout-grid' },
  { value: 'list', label: t('DOCUMENT_TEMPLATES.VIEW.LIST'), icon: 'i-lucide-list' },
]);
</script>

<template>
  <div
    class="view-toggle"
    role="radiogroup"
    :aria-label="t('DOCUMENT_TEMPLATES.VIEW.TOGGLE_LABEL')"
  >
    <button
      v-for="opt in options"
      :key="opt.value"
      type="button"
      role="radio"
      class="view-toggle__btn"
      :class="{ 'view-toggle__btn--active': modelValue === opt.value }"
      :aria-checked="modelValue === opt.value"
      @click="emit('update:modelValue', opt.value)"
    >
      <span :class="opt.icon" class="view-toggle__icon" />
      <span class="view-toggle__label">{{ opt.label }}</span>
    </button>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/shared/view-toggle';
</style>
