<template>
  <div class="pp-avatar" :class="[`pp-avatar--${size}`]" :style="bgStyle" :title="name">
    <img v-if="src" :src="src" :alt="name" class="pp-avatar__img" />
    <span v-else class="pp-avatar__initials">{{ initials }}</span>
  </div>
</template>

<script setup>
import { computed } from 'vue';

const props = defineProps({
  name: { type: String, default: '' },
  src:  { type: String, default: '' },
  size: { type: String, default: 'md' } // sm | md | lg
});

const initials = computed(() => {
  if (!props.name) return '?';
  const parts = props.name.trim().split(/\s+/);
  const first = parts[0]?.[0] || '';
  const last  = parts.length > 1 ? parts[parts.length - 1][0] : '';
  return (first + last).toUpperCase();
});

// Cor derivada do nome — visual consistente entre renders, sem precisar persistir.
const bgStyle = computed(() => {
  const palette = ['#2563eb', '#0ea5e9', '#06b6d4', '#10b981', '#f59e0b', '#ef4444', '#8b5cf6', '#ec4899'];
  let hash = 0;
  for (const c of props.name) hash = (hash * 31 + c.charCodeAt(0)) >>> 0;
  return { backgroundColor: palette[hash % palette.length] };
});
</script>

<style scoped>
.pp-avatar {
  border-radius: 50%; overflow: hidden;
  display: inline-flex; align-items: center; justify-content: center;
  color: #fff; font-weight: 700; line-height: 1;
  flex-shrink: 0;
}
.pp-avatar--sm { width: 32px; height: 32px; font-size: 12px; }
.pp-avatar--md { width: 40px; height: 40px; font-size: 14px; }
.pp-avatar--lg { width: 56px; height: 56px; font-size: 18px; }
.pp-avatar__img { width: 100%; height: 100%; object-fit: cover; }
.pp-avatar__initials { user-select: none; }
</style>
