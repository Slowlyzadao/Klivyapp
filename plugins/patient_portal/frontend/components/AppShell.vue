<template>
  <div class="pp-shell">
    <AppHeader v-if="showHeader" />
    <main class="pp-shell__main">
      <slot />
    </main>
    <BottomNav v-if="showBottomNav" />
  </div>
</template>

<script setup>
import AppHeader from './AppHeader.vue';
import BottomNav from './BottomNav.vue';

defineProps({
  showHeader:    { type: Boolean, default: true },
  showBottomNav: { type: Boolean, default: true }
});
</script>

<style scoped>
.pp-shell {
  min-height: 100vh; display: flex; flex-direction: column;
  background: var(--pp-color-bg);
  max-width: 480px; margin: 0 auto;
  /* Em telas maiores, o app fica em uma "moldura" — efeito de mobile preview no desktop */
  position: relative;
}
@media (min-width: 720px) {
  .pp-shell {
    margin: 24px auto;
    min-height: calc(100vh - 48px);
    border-radius: 28px;
    overflow: hidden;
    box-shadow: 0 20px 60px rgba(15, 23, 42, .08), 0 1px 3px rgba(15, 23, 42, .04);
  }
}
.pp-shell__main {
  flex: 1; overflow-y: auto; overflow-x: hidden;
  padding-bottom: 8px;
}
</style>
