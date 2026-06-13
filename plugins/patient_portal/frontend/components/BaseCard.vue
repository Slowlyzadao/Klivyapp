<template>
  <section class="pp-card">
    <header v-if="title || $slots.header" class="pp-card__header">
      <slot name="header">
        <h2 class="pp-card__title">{{ title }}</h2>
        <p v-if="subtitle" class="pp-card__subtitle">{{ subtitle }}</p>
      </slot>
    </header>
    <div class="pp-card__body"><slot /></div>
    <footer v-if="$slots.footer" class="pp-card__footer"><slot name="footer" /></footer>
  </section>
</template>

<script setup>
defineProps({
  title:    String,
  subtitle: String
});
</script>

<style scoped>
.pp-card {
  background: var(--pp-color-surface);
  border: 1px solid var(--pp-color-border);
  border-radius: 16px;
  box-shadow: 0 1px 2px rgba(15, 23, 42, .04);
  overflow: hidden;
}
.pp-card__header  { padding: 20px 24px 0; }
.pp-card__title   { margin: 0; font-size: 18px; font-weight: 700; color: var(--pp-color-text); }
.pp-card__subtitle { margin: 4px 0 0; font-size: 13px; color: var(--pp-color-text-muted); }
.pp-card__body    { padding: 20px 24px; }
.pp-card__footer  { padding: 16px 24px; border-top: 1px solid var(--pp-color-border); background: #f8fafc; }
</style>
