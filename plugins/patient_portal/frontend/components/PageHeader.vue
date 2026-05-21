<template>
  <header class="pp-page-header">
    <div class="pp-page-header__top">
      <button
        v-if="back"
        type="button"
        class="pp-page-header__back"
        @click="$emit('back')"
        aria-label="Voltar"
      >
        <IconChevronLeft :size="20" />
      </button>
      <h1 class="pp-page-header__title">{{ title }}</h1>
      <div class="pp-page-header__action"><slot name="action" /></div>
    </div>
    <p v-if="subtitle" class="pp-page-header__subtitle">{{ subtitle }}</p>
  </header>
</template>

<script setup>
import IconChevronLeft from './icons/IconChevronLeft.vue';
defineProps({
  title:    String,
  subtitle: String,
  back:     Boolean
});
defineEmits(['back']);
</script>

<style scoped>
.pp-page-header { padding: 16px 20px 8px; background: var(--pp-color-bg); }
.pp-page-header__top { display: flex; align-items: center; gap: 8px; }
.pp-page-header__back {
  width: 36px; height: 36px; border-radius: 10px;
  display: flex; align-items: center; justify-content: center;
  border: none; background: transparent; cursor: pointer;
  color: var(--pp-color-text); transition: background 120ms ease;
}
.pp-page-header__back:hover { background: #e2e8f0; }
.pp-page-header__title {
  margin: 0; flex: 1; font-size: 22px; font-weight: 700; color: var(--pp-color-text);
  line-height: 1.2;
}
.pp-page-header__action { display: flex; gap: 8px; flex-shrink: 0; }
.pp-page-header__subtitle { margin: 4px 0 0 0; font-size: 13px; color: var(--pp-color-text-muted); }
</style>
