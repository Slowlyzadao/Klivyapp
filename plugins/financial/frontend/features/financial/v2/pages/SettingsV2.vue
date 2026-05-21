<script setup>
/**
 * Configurações financeiro v2 — 5 tabs (canon §4 Grupo A).
 * Cada tab carrega um componente filho dedicado.
 *
 * Acesso por URL direta: /financial/v2/settings/<tab> onde tab ∈
 *   categories | bank-accounts | commission | recurring | goals
 *
 * UI premium:
 *   - Layout `.finv2-page` (scroll + sticky header).
 *   - Tabs usando TabBar global do Chatwoot (mesmo visual do contato:
 *     pílula com indicador deslizante animado).
 *   - Mobile: TabBar tem scroll horizontal nativo do navegador.
 *   - Body com card slate + radius.
 */
import { computed, ref, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import SettingsCategoriesTab from '../components/settings/SettingsCategoriesTab.vue';
import SettingsBankAccountsTab from '../components/settings/SettingsBankAccountsTab.vue';
import SettingsCommissionTab from '../components/settings/SettingsCommissionTab.vue';
import SettingsRecurringTab from '../components/settings/SettingsRecurringTab.vue';
import SettingsGoalsTab from '../components/settings/SettingsGoalsTab.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const route = useRoute();
const router = useRouter();

const TABS = [
  { key: 'categories',    label: 'Categorias',           component: SettingsCategoriesTab },
  { key: 'bank-accounts', label: 'Contas e Caixa',       component: SettingsBankAccountsTab },
  { key: 'commission',    label: 'Comissões',            component: SettingsCommissionTab },
  { key: 'recurring',     label: 'Despesas Recorrentes', component: SettingsRecurringTab },
  { key: 'goals',         label: 'Metas',                component: SettingsGoalsTab },
];

const currentTab = computed(() => {
  const requested = route.params.tab;
  return TABS.find(t => t.key === requested) || TABS[0];
});

const activeTabIndex = computed(() => {
  const idx = TABS.findIndex(t => t.key === currentTab.value.key);
  return idx >= 0 ? idx : 0;
});

// Ref do wrapper das tabs — usamos pra centralizar a tab ativa no mobile
// quando o usuário troca (scrollIntoView no botão clicado).
const tabsWrapRef = ref(null);

function scrollActiveTabIntoView() {
  nextTick(() => {
    if (!tabsWrapRef.value) return;
    // O TabBar marca a tab ativa com a cor `text-n-blue-11`. Usamos isso pra
    // achar o botão sem precisar mexer no componente compartilhado.
    const activeBtn = tabsWrapRef.value.querySelector('button.text-n-blue-11');
    if (!activeBtn || typeof activeBtn.scrollIntoView !== 'function') return;
    activeBtn.scrollIntoView({
      block: 'nearest',
      inline: 'center',
      behavior: 'smooth',
    });
  });
}

// Centraliza ao montar (caso o usuário entre direto numa tab que não a primeira)
// e a cada troca de tab.
watch(activeTabIndex, scrollActiveTabIntoView, { immediate: true });

function onTabChanged(tab) {
  router.push({
    name: 'financial_v2_settings_tab',
    params: { ...route.params, tab: tab.key },
  });
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Configurações financeiras</h1>
        <p class="finv2-page__subtitle">
          Cinco grupos que sustentam o módulo. Sem categorias e contas
          cadastradas, lançamentos caem em "Sem categoria" e o DRE fica
          inutilizável.
        </p>
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- TabBar global (Chatwoot components-next) — mesmo visual da página de
           contato: pílula com indicador deslizante animado, mais premium que
           tabs com border-bottom. Container faz scroll horizontal no mobile
           sem barra visível e centraliza a tab ativa quando trocada. -->
      <div ref="tabsWrapRef" class="set-v2__tabs-wrap">
        <TabBar
          :tabs="TABS"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>

      <!-- Conteúdo da tab atual -->
      <section class="set-v2__panel">
        <component :is="currentTab.component" />
      </section>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Layout vem do _layout.scss global. TabBar usa classes Tailwind n-* do
   Chatwoot — não precisa de CSS extra aqui. */

/* Wrapper das tabs: scroll horizontal sem barra visível + respiro vertical
   pra que o outline+shadow do indicador da TabBar não fiquem cortados nas
   bordas (sem padding, a pílula ativa parecia "achatada" no mobile). */
.set-v2__tabs-wrap {
  overflow-x: auto;
  /* Hide scrollbar (Firefox) */
  scrollbar-width: none;
  /* Hide scrollbar (IE/Edge legacy) */
  -ms-overflow-style: none;
  /* Hide scrollbar (Chrome/Safari/Edge moderno) */
  &::-webkit-scrollbar { display: none; }
  /* Respiro vertical (4px topo+base) absorve o `outline-1 outline` e o
     `shadow-sm` do indicador, evitando corte no mobile. */
  padding: 4px 0;
}

/* ── Painel ───────────────────────────────────────────────────── */
.set-v2__panel {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 20px;
  min-height: 240px;
}
@media (max-width: 640px) {
  .set-v2__panel { padding: 14px; }
}
</style>
