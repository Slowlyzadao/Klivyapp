<script setup>
// Select estilizado da toolbar (fonte / tamanho) — estilo Google Docs.
// Native <select> (acessível) com chevron e largura configurável.

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
    <select
      class="tb-select__el"
      :value="modelValue"
      :aria-label="ariaLabel"
      :title="ariaLabel"
      @change="$emit('update:modelValue', $event.target.value)"
    >
      <option v-for="opt in options" :key="opt.value" :value="opt.value">
        {{ opt.label }}
      </option>
    </select>
    <span class="i-lucide-chevron-down tb-select__chevron" />
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/toolbar-select';
</style>
