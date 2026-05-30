<script setup>
import { computed } from 'vue';
import { useAuthStore } from '../store/auth';
import { useNotificationsStore } from '../store/notifications';
import Avatar from './Avatar.vue';
import IconBell from './icons/IconBell.vue';
import KlivyLogo from './KlivyLogo.vue';

const auth = useAuthStore();
const notifications = useNotificationsStore();

const firstName = computed(
  () => auth.patient?.name?.split(/\s+/)?.[0] || 'Paciente'
);

const greeting = computed(() => {
  const h = new Date().getHours();
  if (h < 12) return 'Bom dia';
  if (h < 18) return 'Boa tarde';
  return 'Boa noite';
});
</script>

<template>
  <header class="pp-app-header">
    <router-link
      to="/"
      class="pp-app-header__brand"
      aria-label="Klivy Você — início"
    >
      <KlivyLogo variant="full" />
    </router-link>

    <div class="pp-app-header__row">
      <div class="pp-app-header__left">
        <Avatar :name="auth.patient?.name" size="md" />
        <div class="pp-app-header__greeting">
          <div class="pp-app-header__hello">{{ greeting }},</div>
          <div class="pp-app-header__name">{{ firstName }}</div>
        </div>
      </div>

      <div class="pp-app-header__actions">
        <router-link
          to="/notifications"
          class="pp-app-header__icon-btn"
          aria-label="Notificações"
        >
          <IconBell :size="22" />
          <span
            v-if="notifications.unreadCount > 0"
            class="pp-app-header__badge"
          >
            {{
              notifications.unreadCount > 9 ? '9+' : notifications.unreadCount
            }}
          </span>
        </router-link>
      </div>
    </div>
  </header>
</template>

<style scoped>
.pp-app-header {
  position: sticky;
  top: 0;
  z-index: 10;
  width: 100%;
  display: flex;
  flex-direction: column;
  align-items: stretch;
  gap: 8px;
  padding: 12px var(--pp-content-pad-x) 12px;
  background: var(--pp-color-bg);
  backdrop-filter: saturate(180%) blur(8px);
}
.pp-app-header__brand {
  align-self: flex-start;
  padding: 4px 0;
  border-radius: 8px;
  text-decoration: none;
  color: var(--pp-color-text);
}
.pp-app-header__brand :deep(.pp-klivy-logo) {
  height: 26px;
}
.pp-app-header__row {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}
@media (min-width: 768px) {
  .pp-app-header__brand :deep(.pp-klivy-logo) {
    height: 30px;
  }
}
@media (min-width: 1024px) {
  .pp-app-header {
    padding-top: 24px;
    padding-bottom: 12px;
    width: 1080px !important;
  }
  /* Desktop: sidebar já mostra a logo. Esconde aqui pra evitar duplicar. */
  .pp-app-header__brand {
    display: none;
  }
  .pp-app-header__hello {
    font-size: 14px;
  }
  .pp-app-header__name {
    font-size: 18px;
    max-width: 320px;
  }
}
.pp-app-header__left {
  display: flex;
  align-items: center;
  gap: 12px;
}
.pp-app-header__greeting {
  line-height: 1.2;
}
.pp-app-header__hello {
  font-size: 13px;
  color: var(--pp-color-text-muted);
}
.pp-app-header__name {
  font-size: 16px;
  font-weight: 700;
  color: var(--pp-color-text);
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.pp-app-header__actions {
  display: flex;
  gap: 4px;
}
.pp-app-header__icon-btn {
  position: relative;
  width: 40px;
  height: 40px;
  border-radius: 12px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: var(--pp-color-text);
  background: #fff;
  border: 1px solid var(--pp-color-border);
  box-shadow: 0 1px 2px rgba(15, 23, 42, 0.04);
  transition:
    background 120ms ease,
    transform 80ms ease;
  text-decoration: none;
}
.pp-app-header__icon-btn:hover {
  background: #f8fafc;
}
.pp-app-header__icon-btn:active {
  transform: scale(0.97);
}
.pp-app-header__badge {
  position: absolute;
  top: -4px;
  right: -4px;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  font-weight: 700;
  line-height: 1;
  color: #fff;
  background: #ef4444;
  border-radius: 999px;
  border: 2px solid var(--pp-color-bg);
}
</style>
