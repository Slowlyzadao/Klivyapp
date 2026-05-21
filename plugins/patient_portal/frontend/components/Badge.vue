<template>
  <span class="pp-badge" :class="[`pp-badge--${variant}`, `pp-badge--${size}`]">
    <slot />
  </span>
</template>

<script setup>
defineProps({
  variant: { type: String, default: 'neutral' }, // neutral | primary | success | warning | danger
  size:    { type: String, default: 'md' }       // sm | md
});
</script>

<style scoped>
.pp-badge {
  display: inline-flex; align-items: center; gap: 4px;
  font-weight: 600; line-height: 1; white-space: nowrap;
  border-radius: 999px; border: 1px solid transparent;
}
.pp-badge--sm { padding: 3px 8px;  font-size: 11px; }
.pp-badge--md { padding: 5px 10px; font-size: 12px; }

.pp-badge--neutral { background: #f1f5f9; color: #475569; }
.pp-badge--primary { background: #dbeafe; color: #1e40af; }
.pp-badge--success { background: #d1fae5; color: #047857; }
.pp-badge--warning { background: #fef3c7; color: #92400e; }
.pp-badge--danger  { background: #fee2e2; color: #991b1b; }
</style>
