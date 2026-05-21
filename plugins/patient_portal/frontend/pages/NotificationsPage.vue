<template>
  <AppShell>
    <PageHeader title="Notificações" back @back="$router.back()">
      <template #action>
        <button
          v-if="notifications.unreadCount > 0"
          type="button"
          class="pp-notifs__mark"
          @click="onMarkAll"
        >
          Marcar todas
        </button>
      </template>
    </PageHeader>

    <div class="pp-notifs">
      <div v-if="notifications.loading" class="pp-notifs__loading">Carregando…</div>

      <ul v-else-if="notifications.items.length > 0" class="pp-notifs__list">
        <li
          v-for="item in notifications.items"
          :key="item.id"
          class="pp-notifs__item"
          :class="{ 'pp-notifs__item--unread': !item.read }"
          @click="onTap(item)"
        >
          <div class="pp-notifs__icon" :style="iconStyle(item.kind)">
            <component :is="iconFor(item.kind)" :size="18" />
          </div>
          <div class="pp-notifs__body">
            <div class="pp-notifs__title">{{ item.title }}</div>
            <div v-if="item.body" class="pp-notifs__text">{{ item.body }}</div>
            <div class="pp-notifs__time">{{ formatRelative(item.created_at) }}</div>
          </div>
          <div v-if="!item.read" class="pp-notifs__unread-dot" />
        </li>
      </ul>

      <EmptyState
        v-else
        title="Tudo em dia por aqui"
        description="Você ainda não tem notificações. Avisaremos sobre confirmações, novos documentos e cobranças."
      >
        <template #icon><IconBell :size="28" /></template>
      </EmptyState>
    </div>
  </AppShell>
</template>

<script setup>
import { onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useNotificationsStore } from '../store/notifications';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import EmptyState from '../components/EmptyState.vue';
import IconBell from '../components/icons/IconBell.vue';
import IconCalendar from '../components/icons/IconCalendar.vue';
import IconDocument from '../components/icons/IconDocument.vue';
import IconShield from '../components/icons/IconShield.vue';
import IconHeart from '../components/icons/IconHeart.vue';
import IconMessage from '../components/icons/IconMessage.vue';
import IconWallet from '../components/icons/IconWallet.vue';
import IconInfo from '../components/icons/IconInfo.vue';
import { formatRelative } from '../utils/format';

const notifications = useNotificationsStore();
const router = useRouter();

const KIND_MAP = {
  appointment_confirmed: { icon: IconCalendar, color: '#10b981', route: 'appointments' },
  appointment_canceled:  { icon: IconCalendar, color: '#ef4444', route: 'appointments' },
  appointment_reminder:  { icon: IconCalendar, color: '#2563eb', route: 'appointments' },
  document_ready:        { icon: IconDocument, color: '#f59e0b', route: 'health' },
  consent_pending:       { icon: IconShield,   color: '#8b5cf6', route: 'consent-records' },
  consent_signed:        { icon: IconShield,   color: '#10b981', route: 'consent-records' },
  recall:                { icon: IconHeart,    color: '#ef4444', route: 'home' },
  message_received:      { icon: IconMessage,  color: '#8b5cf6', route: 'messages' },
  financial_charge:      { icon: IconWallet,   color: '#f59e0b', route: 'financial' },
  financial_overdue:     { icon: IconWallet,   color: '#dc2626', route: 'financial' },
  generic:               { icon: IconInfo,     color: '#64748b', route: null }
};

function iconFor(kind)  { return (KIND_MAP[kind] || KIND_MAP.generic).icon; }
function iconStyle(kind) {
  const c = (KIND_MAP[kind] || KIND_MAP.generic).color;
  return { background: `${c}1a`, color: c };
}

async function onTap(item) {
  if (!item.read) await notifications.markRead(item.id);
  const cfg = KIND_MAP[item.kind] || KIND_MAP.generic;
  if (cfg.route) {
    // Payload pode trazer rota específica (ex: ?id=42); por ora, navegamos pra lista.
    router.push({ name: cfg.route });
  }
}

function onMarkAll() { notifications.markAllRead(); }

onMounted(() => { notifications.fetch(); });
</script>

<style scoped>
.pp-notifs__mark {
  background: transparent; border: none; cursor: pointer;
  color: var(--pp-color-primary); font-size: 13px; font-weight: 600;
}
.pp-notifs { padding: 8px 16px 24px; }
.pp-notifs__loading { padding: 32px; text-align: center; color: var(--pp-color-text-muted); font-size: 14px; }

.pp-notifs__list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }
.pp-notifs__item {
  display: flex; gap: 12px; padding: 14px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  cursor: pointer; transition: transform 80ms ease, border-color 120ms ease;
  position: relative;
}
.pp-notifs__item:hover { border-color: var(--pp-color-primary); }
.pp-notifs__item:active { transform: scale(0.99); }
.pp-notifs__item--unread { background: #fafbff; border-color: rgba(37, 99, 235, .25); }

.pp-notifs__icon {
  width: 36px; height: 36px; border-radius: 10px; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
}

.pp-notifs__body { flex: 1; min-width: 0; }
.pp-notifs__title { font-weight: 600; font-size: 14px; color: var(--pp-color-text); }
.pp-notifs__text  { font-size: 13px; color: #475569; margin-top: 2px; }
.pp-notifs__time  { font-size: 11px; color: var(--pp-color-text-muted); margin-top: 6px; }

.pp-notifs__unread-dot {
  position: absolute; right: 12px; top: 16px;
  width: 8px; height: 8px; border-radius: 50%;
  background: var(--pp-color-primary);
}
</style>
