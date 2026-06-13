<template>
  <label class="pp-input">
    <span v-if="label" class="pp-input__label">{{ label }}</span>
    <input
      :type="type"
      :value="modelValue"
      :placeholder="placeholder"
      :disabled="disabled"
      :autocomplete="autocomplete"
      :inputmode="inputmode"
      class="pp-input__field"
      @input="$emit('update:modelValue', $event.target.value)"
    />
    <span v-if="hint && !error" class="pp-input__hint">{{ hint }}</span>
    <span v-if="error" class="pp-input__error">{{ error }}</span>
  </label>
</template>

<script setup>
defineProps({
  modelValue:   [String, Number],
  label:        String,
  placeholder:  String,
  hint:         String,
  error:        String,
  type:         { type: String, default: 'text' },
  autocomplete: String,
  inputmode:    String,
  disabled:     Boolean
});
defineEmits(['update:modelValue']);
</script>

<style scoped>
.pp-input { display: flex; flex-direction: column; gap: 6px; width: 100%; }
.pp-input__label { font-size: 13px; font-weight: 600; color: var(--pp-color-text); }
.pp-input__field {
  width: 100%; padding: 12px 14px; font-size: 15px;
  background: #fff; color: var(--pp-color-text);
  border: 1px solid var(--pp-color-border); border-radius: 10px;
  transition: border 120ms ease, box-shadow 120ms ease;
}
.pp-input__field:focus {
  outline: none; border-color: var(--pp-color-primary);
  box-shadow: 0 0 0 3px rgba(37, 99, 235, .12);
}
.pp-input__field:disabled { background: #f8fafc; cursor: not-allowed; }
.pp-input__hint  { font-size: 12px; color: var(--pp-color-text-muted); }
.pp-input__error { font-size: 12px; color: #dc2626; }
</style>
