<script setup>
import { useRoute } from 'vue-router';
import IconHome from './icons/IconHome.vue';
import IconCalendar from './icons/IconCalendar.vue';
import IconHeart from './icons/IconHeart.vue';
import IconWallet from './icons/IconWallet.vue';
import IconGrid from './icons/IconGrid.vue';

const route = useRoute();

const items = [
  { to: '/', label: 'Início', icon: IconHome, match: ['home'] },
  {
    to: '/appointments',
    label: 'Consultas',
    icon: IconCalendar,
    match: ['appointments', 'appointment-detail'],
  },
  { to: '/health', label: 'Saúde', icon: IconHeart, match: ['health'] },
  {
    to: '/financial',
    label: 'Financeiro',
    icon: IconWallet,
    match: ['financial'],
  },
  {
    to: '/more',
    label: 'Mais',
    icon: IconGrid,
    match: ['more', 'profile', 'documents'],
  },
];

function isActive(item) {
  return item.match.includes(route.name);
}
</script>

<template>
  <nav class="pp-bottom-nav" aria-label="Navegação principal">
    <router-link
      v-for="item in items"
      :key="item.to"
      :to="item.to"
      class="pp-bottom-nav__item"
      :class="{ 'pp-bottom-nav__item--active': isActive(item) }"
    >
      <component :is="item.icon" :size="22" />
      <span class="pp-bottom-nav__label">{{ item.label }}</span>
    </router-link>
  </nav>
</template>

<style scoped>
.pp-bottom-nav {
  position: sticky;
  bottom: 0;
  z-index: 10;
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 4px;
  padding: 8px 8px calc(8px + env(safe-area-inset-bottom));
  background: rgba(255, 255, 255, 0.92);
  backdrop-filter: saturate(180%) blur(12px);
  border-top: 1px solid var(--pp-color-border);
}
.pp-bottom-nav__item {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 4px;
  padding: 8px 4px;
  min-height: 56px;
  color: var(--pp-color-text-muted);
  text-decoration: none;
  border-radius: 12px;
  transition:
    color 120ms ease,
    background 120ms ease,
    transform 80ms ease;
}
.pp-bottom-nav__item:active {
  transform: scale(0.95);
}
.pp-bottom-nav__item--active {
  color: var(--pp-color-primary);
  background: rgba(37, 99, 235, 0.08);
}
.pp-bottom-nav__label {
  font-size: 11px;
  font-weight: 600;
  line-height: 1;
}

@media (min-width: 1024px) {
  .pp-bottom-nav {
    display: none;
  }
}
</style>
