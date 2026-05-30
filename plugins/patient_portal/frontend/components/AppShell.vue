<script setup>
import AppHeader from './AppHeader.vue';
import BottomNav from './BottomNav.vue';
import SideNav from './SideNav.vue';

defineProps({
  showHeader: { type: Boolean, default: true },
  showBottomNav: { type: Boolean, default: true },
});
</script>

<template>
  <div class="pp-shell">
    <SideNav v-if="showBottomNav" />
    <div class="pp-shell__body">
      <AppHeader v-if="showHeader" />
      <main class="pp-shell__main">
        <slot />
      </main>
      <BottomNav v-if="showBottomNav" />
    </div>
  </div>
</template>

<style scoped>
.pp-shell {
  min-height: 100vh;
  background: var(--pp-color-bg);
  display: flex;
}

.pp-shell__body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  align-items: center !important;
}

.pp-shell__main {
  flex: 1;
  overflow-x: hidden;
  padding-bottom: 8px;
}

/* Mobile: shell em coluna única, content cola nas bordas */
@media (max-width: 767px) {
  .pp-shell {
    flex-direction: column;
  }
}

/* Tablet: content ganha respiro lateral e fica centralizado */
@media (min-width: 768px) and (max-width: 1023px) {
  .pp-shell {
    flex-direction: column;
  }
  .pp-shell__body {
    max-width: 100%;
    margin: 0 auto;
    width: 100%;
  }
}

/* Desktop: sidebar à esquerda + main com largura confortável */
@media (min-width: 1024px) {
  .pp-shell__main {
    max-width: var(--pp-content-max);
    width: 100%;
    margin: 0 auto;
  }
}
</style>
