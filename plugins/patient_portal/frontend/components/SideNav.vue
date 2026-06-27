<script setup>
import { useRoute } from 'vue-router';
import { useAuthStore } from '../store/auth';
import IconHome from './icons/IconHome.vue';
import IconCalendar from './icons/IconCalendar.vue';
import IconHeart from './icons/IconHeart.vue';
import IconWallet from './icons/IconWallet.vue';
import IconGrid from './icons/IconGrid.vue';
import KlivyLogo from './KlivyLogo.vue';

const route = useRoute();
const auth = useAuthStore();

const items = [
  { to: '/', label: 'Início', icon: IconHome, match: ['home'] },
  {
    to: '/appointments',
    label: 'Consultas',
    icon: IconCalendar,
    match: ['appointments', 'appointment-detail', 'appointment-new'],
  },
  {
    to: '/health',
    label: 'Saúde',
    icon: IconHeart,
    match: ['health', 'anamnesis-detail', 'document-request'],
  },
  {
    to: '/financial',
    label: 'Financeiro',
    icon: IconWallet,
    match: ['financial', 'installment-detail', 'payment'],
  },
  {
    to: '/more',
    label: 'Mais',
    icon: IconGrid,
    match: [
      'more',
      'profile',
      'documents',
      'messages',
      'notifications',
      'consent-records',
    ],
  },
];

function isActive(item) {
  return item.match.includes(route.name);
}
</script>

<template>
  <aside class="pp-side-nav" aria-label="Navegação principal">
    <router-link
      to="/"
      class="pp-side-nav__brand"
      aria-label="Klivy Você — início"
    >
      <KlivyLogo variant="full" />
    </router-link>

    <nav class="pp-side-nav__list">
      <router-link
        v-for="item in items"
        :key="item.to"
        :to="item.to"
        class="pp-side-nav__item"
        :class="{ 'pp-side-nav__item--active': isActive(item) }"
      >
        <component :is="item.icon" :size="20" />
        <span class="pp-side-nav__label">{{ item.label }}</span>
      </router-link>
    </nav>

    <div class="pp-side-nav__footer">
      <div v-if="auth.account?.name" class="pp-side-nav__account">
        <div class="pp-side-nav__account-label">Sua clínica</div>
        <div class="pp-side-nav__account-name">{{ auth.account.name }}</div>
      </div>
    </div>
  </aside>
</template>

<style scoped>
.pp-side-nav {
  display: none;
}

@media (min-width: 1024px) {
  .pp-side-nav {
    display: flex;
    flex-direction: column;
    position: sticky;
    top: 0;
    width: var(--pp-sidenav-width);
    height: 100vh;
    padding: 24px 16px;
    background: var(--pp-color-surface);
    border-right: 1px solid var(--pp-color-border);
    flex-shrink: 0;
  }
}

.pp-side-nav__brand {
  display: inline-flex;
  align-items: center;
  padding: 4px 12px;
  margin-bottom: 24px;
  border-radius: 10px;
  text-decoration: none;
  color: var(--pp-color-text);
  transition: background 120ms ease;
}
.pp-side-nav__brand:hover {
  background: #f1f5f9;
}
.pp-side-nav__brand :deep(.pp-klivy-logo) {
  height: 40px;
}

.pp-side-nav__list {
  display: flex;
  flex-direction: column;
  gap: 4px;
  flex: 1;
}
.pp-side-nav__item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  border-radius: 10px;
  color: var(--pp-color-text-muted);
  text-decoration: none;
  font-size: 14px;
  font-weight: 500;
  transition:
    color 120ms ease,
    background 120ms ease;
}
.pp-side-nav__item:hover {
  background: #f1f5f9;
  color: var(--pp-color-text);
}
.pp-side-nav__item--active {
  color: var(--pp-color-primary);
  background: rgba(37, 99, 235, 0.08);
  font-weight: 600;
}
.pp-side-nav__label {
  line-height: 1;
}

.pp-side-nav__footer {
  padding-top: 16px;
  border-top: 1px solid var(--pp-color-border);
}
.pp-side-nav__account {
  padding: 8px 12px;
}
.pp-side-nav__account-label {
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  color: var(--pp-color-text-muted);
}
.pp-side-nav__account-name {
  font-size: 13px;
  font-weight: 600;
  color: var(--pp-color-text);
  margin-top: 2px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
</style>
