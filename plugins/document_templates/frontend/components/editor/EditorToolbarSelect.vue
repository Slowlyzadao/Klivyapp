<script setup>
// Select da toolbar (estilo/fonte/espaçamento). Usa o FormSelect moderno do
// beclinic_core — dropdown teleportado, theme-aware (dark/light) e com busca
// opcional — no lugar do <select> nativo (cujo dropdown ignorava o tema).
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';

defineProps({
  modelValue: { type: [String, Number], default: '' },
  options: { type: Array, required: true },
  ariaLabel: { type: String, default: '' },
  width: { type: String, default: 'auto' },
});

defineEmits(['update:modelValue']);
</script>

<template>
  <div class="tb-select" :style="{ width }">
    <FormSelect
      :model-value="modelValue"
      :options="options"
      :placeholder="ariaLabel"
      @update:model-value="$emit('update:modelValue', $event)"
    />
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/toolbar-select';
</style>
