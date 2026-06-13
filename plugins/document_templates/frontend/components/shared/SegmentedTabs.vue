<script setup>
// SegmentedTabs — controle segmentado reutilizável.
//
// Recebe lista de opções `{ value, label, icon?, count? }` e o valor ativo.
// Emite `update:modelValue` quando troca. Visual: pill com indicador
// deslizando sob a opção ativa.

defineProps({
  modelValue: { type: [String, Number], required: true },
  options: {
    type: Array,
    required: true,
    validator: (arr) => arr.every(o => 'value' in o && 'label' in o),
  },
});

defineEmits(['update:modelValue']);
</script>

<template>
  <div class="seg-tabs" role="tablist">
    <button
      v-for="opt in options"
      :key="opt.value"
      type="button"
      role="tab"
      class="seg-tabs__btn"
      :class="{ 'seg-tabs__btn--active': modelValue === opt.value }"
      :aria-selected="modelValue === opt.value"
      @click="$emit('update:modelValue', opt.value)"
    >
      <span v-if="opt.icon" :class="opt.icon" class="seg-tabs__icon" />
      <span class="seg-tabs__label">{{ opt.label }}</span>
      <span v-if="typeof opt.count === 'number'" class="seg-tabs__count">
        {{ opt.count }}
      </span>
    </button>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/shared/segmented-tabs';
</style>
