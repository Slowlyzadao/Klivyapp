<template>
  <button type="button" class="pp-pay-method" :class="{ 'pp-pay-method--disabled': disabled }" :disabled="disabled" @click="$emit('click')">
    <div class="pp-pay-method__icon" :style="{ background: bg, color }">
      <component :is="icon" :size="22" />
    </div>
    <div class="pp-pay-method__body">
      <div class="pp-pay-method__label">{{ label }}</div>
      <div class="pp-pay-method__hint">{{ hint }}</div>
    </div>
    <IconChevronRight :size="18" class="pp-pay-method__chevron" />
  </button>
</template>

<script setup>
import { computed } from 'vue';
import IconChevronRight from './icons/IconChevronRight.vue';

const props = defineProps({
  label:   { type: String, required: true },
  hint:    { type: String, default: '' },
  icon:    { type: Object, required: true },
  color:   { type: String, default: '#2563eb' },
  disabled:{ type: Boolean, default: false }
});

defineEmits(['click']);

const bg = computed(() => `${props.color}1a`);
</script>

<style scoped>
.pp-pay-method {
  display: flex; align-items: center; gap: 12px;
  width: 100%; padding: 14px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  text-align: left; cursor: pointer; font: inherit; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-pay-method:hover:not(:disabled) { box-shadow: 0 4px 12px rgba(15, 23, 42, .06); border-color: var(--pp-color-primary); }
.pp-pay-method:active:not(:disabled) { transform: scale(0.99); }
.pp-pay-method--disabled { opacity: .55; cursor: not-allowed; }

.pp-pay-method__icon {
  width: 44px; height: 44px; border-radius: 12px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
}
.pp-pay-method__body { flex: 1; min-width: 0; }
.pp-pay-method__label { font-weight: 700; font-size: 15px; color: var(--pp-color-text); }
.pp-pay-method__hint  { font-size: 12px; color: var(--pp-color-text-muted); margin-top: 2px; }
.pp-pay-method__chevron { color: var(--pp-color-text-muted); flex-shrink: 0; }
</style>
