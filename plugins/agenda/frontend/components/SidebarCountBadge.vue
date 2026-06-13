<script setup>
defineProps({
  count: { type: [Number, String], required: true },
});
</script>

<template>
  <span class="sidebar-count-badge">{{ count }}</span>
</template>

<style scoped>
.sidebar-count-badge {
  margin-left: auto;
  @apply text-xs;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-9));
  background: rgb(var(--slate-3));
  padding: 1px 6px;
  border-radius: 8px;
  min-width: 22px;
  text-align: center;
}
</style>
