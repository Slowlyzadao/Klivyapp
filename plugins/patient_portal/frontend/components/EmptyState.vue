<template>
  <div class="pp-empty">
    <div v-if="$slots.icon" class="pp-empty__icon"><slot name="icon" /></div>
    <h3 v-if="title" class="pp-empty__title">{{ title }}</h3>
    <p v-if="description" class="pp-empty__description">{{ description }}</p>
    <div v-if="$slots.action" class="pp-empty__action"><slot name="action" /></div>
  </div>
</template>

<script setup>
defineProps({
  title:       String,
  description: String
});
</script>

<style scoped>
.pp-empty {
  display: flex; flex-direction: column; align-items: center; text-align: center;
  padding: 40px 24px; color: var(--pp-color-text-muted);
}
.pp-empty__icon {
  width: 56px; height: 56px; margin-bottom: 16px;
  display: flex; align-items: center; justify-content: center;
  border-radius: 50%; background: #f1f5f9; color: #94a3b8;
}
.pp-empty__title {
  margin: 0 0 6px; font-size: 16px; font-weight: 600; color: var(--pp-color-text);
}
.pp-empty__description { margin: 0; font-size: 14px; max-width: 320px; }
.pp-empty__action { margin-top: 20px; }
</style>
