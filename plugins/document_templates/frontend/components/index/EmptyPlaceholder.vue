<script setup>
defineProps({
  title: { type: String, required: true },
  description: { type: String, default: '' },
  iconClass: { type: String, default: 'i-lucide-file-text' },
});
</script>

<template>
  <div class="empty-placeholder">
    <span :class="iconClass" class="empty-placeholder__icon" />
    <h2 class="empty-placeholder__title">{{ title }}</h2>
    <p v-if="description" class="empty-placeholder__description">
      {{ description }}
    </p>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/index/empty-placeholder';
</style>
