<script setup>
import { useRouter } from 'vue-router';
import { useAuthStore } from '../store/auth';
import AppShell from '../components/AppShell.vue';
import PageHeader from '../components/PageHeader.vue';
import Avatar from '../components/Avatar.vue';
import ListItem from '../components/ListItem.vue';
import IconUser from '../components/icons/IconUser.vue';
import IconDocument from '../components/icons/IconDocument.vue';
import IconShield from '../components/icons/IconShield.vue';
import IconMessage from '../components/icons/IconMessage.vue';
import IconBell from '../components/icons/IconBell.vue';
import IconGift from '../components/icons/IconGift.vue';
import IconChevronRight from '../components/icons/IconChevronRight.vue';
import IconLogout from '../components/icons/IconLogout.vue';
import IconInfo from '../components/icons/IconInfo.vue';
import PushSubscriptionToggle from '../components/PushSubscriptionToggle.vue';
import DependentSwitcher from '../components/DependentSwitcher.vue';
import { useDependentsStore } from '../store/dependents';
import { computed, onMounted } from 'vue';

const deps = useDependentsStore();
onMounted(() => {
  if (!deps.acting) deps.fetch();
});
const hasDependents = computed(() => deps.hasDependents);

const auth = useAuthStore();
const router = useRouter();

const account = [
  {
    key: 'profile',
    label: 'Meus dados',
    hint: 'Nome, contatos, endereço',
    icon: IconUser,
    color: '#2563eb',
    route: 'profile',
  },
  {
    key: 'documents',
    label: 'Documentos',
    hint: 'Atestados, recibos, exames',
    icon: IconDocument,
    color: '#f59e0b',
    route: 'health',
  },
];

const communication = [
  {
    key: 'messages',
    label: 'Conversa com a clínica',
    hint: 'Tirar dúvidas, pedir reagendamento',
    icon: IconMessage,
    color: '#8b5cf6',
    route: 'messages',
  },
  {
    key: 'notifications',
    label: 'Notificações',
    hint: 'Histórico de avisos',
    icon: IconBell,
    color: '#06b6d4',
    route: 'notifications',
  },
];

const privacy = [
  {
    key: 'consents',
    label: 'Termos clínicos',
    hint: 'Procedimentos que assinou',
    icon: IconShield,
    color: '#10b981',
    route: 'consent-records',
  },
  {
    key: 'lgpd-export',
    label: 'Exportar meus dados',
    hint: 'LGPD — receber em JSON',
    icon: IconDocument,
    color: '#06b6d4',
    action: 'lgpd-export',
  },
  {
    key: 'about',
    label: 'Sobre o Portal',
    hint: 'Versão, ajuda',
    icon: IconInfo,
    color: '#64748b',
    action: 'about',
  },
];

async function onItem(item) {
  if (item.route) return router.push({ name: item.route });
  if (item.action === 'lgpd-export') return doLgpdExport();
  if (item.action === 'about') return showAbout();
}

async function doLgpdExport() {
  try {
    const { useProfileStore } = await import('../store/profile');
    const profile = useProfileStore();
    const data = await profile.exportLgpd();
    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: 'application/json',
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `meus-dados-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 60_000);
  } catch (e) {
    window.alert(
      'Não foi possível gerar o export. Tente de novo em alguns instantes.'
    );
  }
}

function showAbout() {
  window.alert(
    'Klivy Patient Portal · Sprint E · v0.5\n\nDúvidas? Use a aba "Conversa com a clínica".'
  );
}

async function onLogout() {
  await auth.logout();
  router.replace({ name: 'login' });
}
</script>

<template>
  <AppShell>
    <PageHeader title="Mais" />

    <!-- Patient identity card -->
    <section class="pp-more__identity">
      <Avatar :name="auth.patient?.name" size="lg" />
      <div class="pp-more__identity-text">
        <div class="pp-more__name">{{ auth.patient?.name }}</div>
        <div class="pp-more__email">
          {{ auth.patient?.email || auth.patient?.phone }}
        </div>
        <div class="pp-more__clinic">{{ auth.account?.name }}</div>
      </div>
    </section>

    <!-- Section: Conta -->
    <section class="pp-more__section">
      <h3 class="pp-more__section-title">Conta</h3>
      <div class="pp-more__list">
        <ListItem
          v-for="item in account"
          :key="item.key"
          :title="item.label"
          :subtitle="item.hint"
          interactive
          @click="onItem(item)"
        >
          <template #leading>
            <div
              class="pp-more__icon"
              :style="{ background: `${item.color}1a`, color: item.color }"
            >
              <component :is="item.icon" :size="20" />
            </div>
          </template>
          <template #trailing><IconChevronRight :size="18" /></template>
        </ListItem>
      </div>
    </section>

    <!-- Section: Comunicação -->
    <section class="pp-more__section">
      <h3 class="pp-more__section-title">Comunicação</h3>
      <div class="pp-more__list">
        <ListItem
          v-for="item in communication"
          :key="item.key"
          :title="item.label"
          :subtitle="item.hint"
          interactive
          @click="onItem(item)"
        >
          <template #leading>
            <div
              class="pp-more__icon"
              :style="{ background: `${item.color}1a`, color: item.color }"
            >
              <component :is="item.icon" :size="20" />
            </div>
          </template>
          <template #trailing><IconChevronRight :size="18" /></template>
        </ListItem>
      </div>
    </section>

    <!-- Web Push toggle (Sprint G) -->
    <PushSubscriptionToggle />

    <!-- Sprint I — Switcher de dependente (só aparece se houver dependentes) -->
    <DependentSwitcher v-if="hasDependents" />

    <!-- Section: Privacidade -->
    <section class="pp-more__section">
      <h3 class="pp-more__section-title">Privacidade</h3>
      <div class="pp-more__list">
        <ListItem
          v-for="item in privacy"
          :key="item.key"
          :title="item.label"
          :subtitle="item.hint"
          interactive
          @click="onItem(item)"
        >
          <template #leading>
            <div
              class="pp-more__icon"
              :style="{ background: `${item.color}1a`, color: item.color }"
            >
              <component :is="item.icon" :size="20" />
            </div>
          </template>
          <template #trailing><IconChevronRight :size="18" /></template>
        </ListItem>
      </div>
    </section>

    <!-- Sair -->
    <button type="button" class="pp-more__logout" @click="onLogout">
      <IconLogout :size="18" />
      <span>Sair da conta</span>
    </button>

    <p class="pp-more__version">Klivy Patient Portal · Sprint I · v0.9</p>
  </AppShell>
</template>

<style scoped>
.pp-more__identity {
  margin: 8px var(--pp-content-pad-x) 24px;
  padding: 20px;
  background: #fff;
  border: 1px solid var(--pp-color-border);
  border-radius: 18px;
  display: flex;
  align-items: center;
  gap: 14px;
}
@media (min-width: 1024px) {
  .pp-more__identity {
    padding: 24px 28px;
  }
  .pp-more__section {
    max-width: 100%;
  }
}
.pp-more__identity-text {
  flex: 1;
  min-width: 0;
}
.pp-more__name {
  font-size: 17px;
  font-weight: 700;
  color: var(--pp-color-text);
}
.pp-more__email {
  font-size: 13px;
  color: var(--pp-color-text-muted);
  margin-top: 2px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.pp-more__clinic {
  font-size: 12px;
  font-weight: 600;
  color: var(--pp-color-primary);
  margin-top: 6px;
}

.pp-more__section {
  margin: 0 var(--pp-content-pad-x) 20px;
}
.pp-more__section-title {
  margin: 0 0 8px;
  font-size: 12px;
  font-weight: 700;
  color: var(--pp-color-text-muted);
  text-transform: uppercase;
  letter-spacing: 0.5px;
}
.pp-more__list {
  background: #fff;
  border: 1px solid var(--pp-color-border);
  border-radius: 16px;
  overflow: hidden;
}

.pp-more__icon {
  width: 36px;
  height: 36px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.pp-more__logout {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  margin: 16px var(--pp-content-pad-x) 8px;
  width: calc(100% - 2 * var(--pp-content-pad-x));
  padding: 14px;
  background: #fff;
  border: 1px solid #fecaca;
  color: #b91c1c;
  border-radius: 14px;
  font-size: 14px;
  font-weight: 600;
  cursor: pointer;
  transition: background 120ms ease;
}
.pp-more__logout:hover {
  background: #fef2f2;
}

.pp-more__version {
  text-align: center;
  padding: 16px;
  font-size: 11px;
  color: var(--pp-color-text-muted);
}
</style>
