<template>
  <button
    :type="type"
    :disabled="disabled || loading"
    :class="classes"
    @click="$emit('click', $event)"
  >
    <span v-if="loading" class="pp-btn__spinner" aria-hidden="true" />
    <slot />
  </button>
</template>

<script setup>
import { computed } from 'vue';

const props = defineProps({
  type:    { type: String, default: 'button' },
  variant: { type: String, default: 'primary' }, // primary | secondary | ghost | danger | ghost-danger
  size:    { type: String, default: 'md' },      // sm | md | lg
  disabled: Boolean,
  loading:  Boolean,
  block:    Boolean
});

defineEmits(['click']);

const classes = computed(() => [
  'pp-btn',
  `pp-btn--${props.variant}`,
  `pp-btn--${props.size}`,
  props.block && 'pp-btn--block'
]);
</script>

<style scoped>
.pp-btn {
  display: inline-flex; align-items: center; justify-content: center; gap: 8px;
  font-weight: 600; line-height: 1; cursor: pointer;
  border-radius: 10px; border: 1px solid transparent;
  transition: background 120ms ease, transform 80ms ease, opacity 120ms ease;
}
.pp-btn:disabled { opacity: .55; cursor: not-allowed; }
.pp-btn--sm { padding: 8px 12px; font-size: 13px; }
.pp-btn--md { padding: 12px 16px; font-size: 14px; }
.pp-btn--lg { padding: 14px 20px; font-size: 15px; }
.pp-btn--block { width: 100%; }
.pp-btn--primary   { background: var(--pp-color-primary); color: #fff; }
.pp-btn--primary:hover:not(:disabled) { background: var(--pp-color-primary-hover); }
.pp-btn--secondary { background: #fff; color: var(--pp-color-text); border-color: var(--pp-color-border); }
.pp-btn--secondary:hover:not(:disabled) { background: #f1f5f9; }
.pp-btn--ghost     { background: transparent; color: var(--pp-color-text-muted); }
.pp-btn--ghost:hover:not(:disabled) { color: var(--pp-color-text); }
.pp-btn--danger    { background: #dc2626; color: #fff; }
.pp-btn--danger:hover:not(:disabled) { background: #b91c1c; }
.pp-btn--ghost-danger { background: transparent; color: #dc2626; border-color: #fecaca; }
.pp-btn--ghost-danger:hover:not(:disabled) { background: #fef2f2; }
.pp-btn__spinner {
  width: 14px; height: 14px; border-radius: 50%;
  border: 2px solid currentColor; border-top-color: transparent;
  animation: pp-spin .8s linear infinite;
}
@keyframes pp-spin { to { transform: rotate(360deg); } }
</style>
