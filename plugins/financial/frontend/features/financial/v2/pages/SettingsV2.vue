<script setup>
/**
 * Configurações financeiro v2 — wireframe 2026-05-23 (sidebar vertical).
 *
 * Layout em 2 colunas dentro do `.finv2-page` canônico (que ocupa
 * `position: absolute; inset: 0;` do <main> pai via regra global de
 * _layout.scss):
 *
 *   ┌─ finv2-page ─────────────────────────────────────────────┐
 *   │ finv2-page__header (sticky)                              │
 *   ├──────────────┬───────────────────────────────────────────┤
 *   │ settings-    │ settings-main                             │
 *   │ sidebar      │ (component da tab atual)                  │
 *   │ (240px)      │ flex: 1                                   │
 *   └──────────────┴───────────────────────────────────────────┘
 *
 * Sidebar tem 3 seções: Configurações, Governança, Sistema.
 *
 * Mobile (≤900px): sidebar vira drawer (off-canvas) com botão "Configurações"
 * pra abrir. Em desktop fica sempre visível.
 *
 * URL: /financial/v2/settings/<key>
 */
import { computed, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import SettingsCategoriesTab from '../components/settings/SettingsCategoriesTab.vue';
import SettingsBankAccountsTab from '../components/settings/SettingsBankAccountsTab.vue';
import SettingsCommissionTab from '../components/settings/SettingsCommissionTab.vue';
import SettingsRecurringTab from '../components/settings/SettingsRecurringTab.vue';
import SettingsGoalsTab from '../components/settings/SettingsGoalsTab.vue';
import SettingsServicesTab from '../components/settings/SettingsServicesTab.vue';
import SettingsAgentProfilesTab from '../components/settings/SettingsAgentProfilesTab.vue';
import SettingsPaymentMethodsTab from '../components/settings/SettingsPaymentMethodsTab.vue';
import ReclassifyV2 from '../pages/ReclassifyV2.vue';
import AccountantExportV2 from '../pages/AccountantExportV2.vue';
import AuditLogsV2 from '../pages/AuditLogsV2.vue';
import BackupsV2 from '../pages/BackupsV2.vue';
import LgpdV2 from '../pages/LgpdV2.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const route = useRoute();
const router = useRouter();

// ── Sidebar sections (wireframe canon §4) ───────────────────────────
const SIDEBAR_SECTIONS = [
  {
    title: 'Início',
    items: [
      // Reabre o assistente de configuração (wizard de onboarding) a qualquer
      // momento. Antes ele só era alcançável via redirect quando o setup
      // obrigatório estava incompleto — depois de concluído, sumia e o usuário
      // perdia a visão dos passos recomendados/opcionais. `route` (em vez de
      // `key`) sinaliza pro selectItem navegar por nome de rota.
      {
        key: 'setup-wizard',
        label: 'Assistente de configuração',
        icon: 'i-lucide-list-checks',
        route: 'financial_v2_setup',
      },
    ],
  },
  {
    title: 'Configurações',
    items: [
      { key: 'agents',           label: 'Profissionais',      icon: 'i-lucide-users',          component: SettingsAgentProfilesTab },
      { key: 'categories',       label: 'Plano de Contas',    icon: 'i-lucide-folder-tree',    component: SettingsCategoriesTab },
      { key: 'payment-methods',  label: 'Formas Pagamento',   icon: 'i-lucide-credit-card',    component: SettingsPaymentMethodsTab },
      { key: 'bank-accounts',    label: 'Contas Bancárias',   icon: 'i-lucide-landmark',       component: SettingsBankAccountsTab },
      { key: 'commission',       label: 'Regras Comissão',    icon: 'i-lucide-percent',        component: SettingsCommissionTab },
      { key: 'services',         label: 'Procedimentos e Serviços', icon: 'i-lucide-scissors', component: SettingsServicesTab },
      { key: 'recurring',        label: 'Despesas Fixas',     icon: 'i-lucide-rotate-cw',      component: SettingsRecurringTab },
      { key: 'goals',            label: 'Metas',              icon: 'i-lucide-target',         component: SettingsGoalsTab },
    ],
  },
  {
    title: 'Governança',
    items: [
      { key: 'reclassify',        label: 'Reclassificar', icon: 'i-lucide-tags',          component: ReclassifyV2,        props: { embedded: true } },
      { key: 'accountant-export', label: 'Contador',      icon: 'i-lucide-file-spreadsheet', component: AccountantExportV2, props: { embedded: true } },
      { key: 'audit',             label: 'Auditoria',     icon: 'i-lucide-history',       component: AuditLogsV2,         props: { embedded: true } },
    ],
  },
  {
    title: 'Sistema',
    items: [
      { key: 'backups', label: 'Dados & Backup', icon: 'i-lucide-database-backup', component: BackupsV2, props: { embedded: true } },
      { key: 'lgpd',    label: 'LGPD',           icon: 'i-lucide-shield-check',    component: LgpdV2,    props: { embedded: true } },
    ],
  },
];

const ALL_ITEMS = SIDEBAR_SECTIONS.flatMap(s => s.items);
// Só itens com `component` são tabs renderizáveis no main. O item de rota
// (Assistente) navega pra fora, então fica de fora do fallback de currentItem.
const ENABLED_ITEMS = ALL_ITEMS.filter(i => !i.disabled && i.component);

const currentItem = computed(() => {
  const requested = route.params.tab;
  return ENABLED_ITEMS.find(i => i.key === requested) || ENABLED_ITEMS[0];
});

const drawerOpen = ref(false);

function selectItem(item) {
  if (item.disabled) return;
  drawerOpen.value = false;
  // Item de rota (ex.: Assistente de configuração) navega por nome de rota em
  // vez de trocar a tab de Configurações.
  if (item.route) {
    router.push({ name: item.route, params: { accountId: route.params.accountId } });
    return;
  }
  router.push({
    name: 'financial_v2_settings_tab',
    params: { ...route.params, tab: item.key },
  });
}

watch(() => route.params.tab, () => {
  drawerOpen.value = false;
});
</script>

<template>
  <!-- finv2-page é canônico: regra global em _layout.scss aplica
       `<main>:has(.finv2-page)` → position: relative, e .finv2-page →
       position: absolute; inset: 0 (single source de scroll, largura total).
       Modifier `--settings` ajusta o layout interno (body sem padding pra
       sidebar encostar nas bordas). -->
  <div class="finv2-page finv2-page--settings">
    <header class="finv2-page__header">
      <div>
        <h1 class="finv2-page__title">Configurações financeiras</h1>
        <p class="finv2-page__subtitle">
          Setup e governança do módulo. Profissionais, plano de contas, formas
          de pagamento e demais grupos canon necessários antes de qualquer operação.
        </p>
      </div>
      <button
        class="finset__drawer-toggle"
        type="button"
        :aria-label="drawerOpen ? 'Fechar configurações' : 'Abrir configurações'"
        :aria-expanded="drawerOpen"
        @click="drawerOpen = !drawerOpen"
      >
        <i class="i-lucide-menu" />
      </button>
    </header>

    <div class="finv2-page__body finset__layout-body">
      <!-- Sidebar -->
      <aside class="finset__sidebar" :class="{ 'finset__sidebar--open': drawerOpen }">
        <div
          v-for="section in SIDEBAR_SECTIONS"
          :key="section.title"
          class="finset__sidebar-section"
        >
          <h3 class="finset__sidebar-title">{{ section.title }}</h3>
          <ul class="finset__sidebar-list">
            <li v-for="item in section.items" :key="item.key">
              <button
                type="button"
                class="finset__sidebar-item"
                :class="{
                  'finset__sidebar-item--active': currentItem.key === item.key,
                  'finset__sidebar-item--disabled': item.disabled,
                }"
                :disabled="item.disabled"
                @click="selectItem(item)"
              >
                <i :class="item.icon" class="finset__sidebar-icon" />
                <span class="finset__sidebar-label">{{ item.label }}</span>
                <span v-if="item.disabled" class="finset__sidebar-soon">em breve</span>
              </button>
            </li>
          </ul>
        </div>
      </aside>

      <!-- Backdrop mobile -->
      <div
        v-if="drawerOpen"
        class="finset__backdrop"
        @click="drawerOpen = false"
        aria-hidden="true"
      />

      <!-- Conteúdo -->
      <main class="finset__main">
        <component
          :is="currentItem.component"
          v-bind="currentItem.props || {}"
        />
      </main>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* ── Settings page override ────────────────────────────────────
   Layout de 2 colunas com scroll independente em cada uma.

   Trio de regras pra fazer 2 colunas verticais com scrolls separados
   dentro de um pai com altura constrita:

   1. `.finv2-page.finv2-page--settings`: trava `overflow: hidden` no pai
      raiz (que por default é `overflow-y: auto` no global do financeiro).
      Sem isso o scroll externo faria sidebar e main rolarem juntos.

   2. `.finset__layout-body` (= .finv2-page__body modificado): flex row,
      `min-height: 0` pra permitir filhos com overflow funcionarem.
      NÃO pode ter `overflow: hidden` próprio — só o pai e os filhos têm.

   3. `.finset__sidebar` e `.finset__main`: `min-height: 0` + `overflow-y: auto`.
      O `min-height: 0` é CRÍTICO em flex item — sem ele o conteúdo "empurra"
      e o overflow nunca dispara.
*/
/* `.finv2-page` global é `position: absolute; inset: 0; overflow-y: auto`
   (não flex). Pra ter sidebar sticky + main com scroll independente,
   precisamos:
   1. Tirar o scroll da raiz (overflow: hidden)
   2. Torná-la flex column pra que o `.finset__layout-body` (flex: 1) tenha
      altura calculada
   3. Filhos da row (sidebar/main) com `min-height: 0 + overflow-y: auto`
      têm seus próprios scrolls. */
.finv2-page--settings {
  overflow: hidden;
  display: flex;
  flex-direction: column;
}

.finset__layout-body {
  flex-direction: row !important;
  padding: 0 !important;
  gap: 0 !important;
  min-height: 0;
}

/* Drawer toggle — só visível em mobile, quadrado 40×40 com ícone centralizado.
   Sem label (só ícone) pra economizar espaço no header mobile. */
.finset__drawer-toggle {
  display: none;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  padding: 0;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  cursor: pointer;
  flex-shrink: 0;

  i { width: 18px; height: 18px; display: block; }
  &:hover { background: rgb(var(--slate-4)); }
}

@media (max-width: 900px) {
  .finset__drawer-toggle { display: inline-flex; }
}

/* ── Sidebar ───────────────────────────────────────────────── */
.finset__sidebar {
  width: 240px;
  flex-shrink: 0;
  min-height: 0;           /* CRÍTICO em flex item pra overflow disparar */
  background: rgb(var(--slate-2) / 0.4);
  border-right: 1px solid rgb(var(--slate-4));
  padding: 20px 12px;
  overflow-y: auto;
  overscroll-behavior: contain;
}

.finset__sidebar-section {
  margin-bottom: 20px;
  &:last-child { margin-bottom: 0; }
}

.finset__sidebar-title {
  margin: 0 0 8px;
  padding: 0 8px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: rgb(var(--slate-9));
}

.finset__sidebar-list {
  margin: 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.finset__sidebar-item {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  padding: 8px 10px;
  background: transparent;
  border: 0;
  border-radius: 6px;
  text-align: left;
  cursor: pointer;
  font-size: 13px;
  color: rgb(var(--slate-11));
  transition: background-color .12s ease, color .12s ease;

  &:hover:not(:disabled) {
    background: rgb(var(--slate-3));
    color: rgb(var(--slate-12));
  }

  &--active {
    background: rgba(16, 185, 129, 0.12);
    color: rgb(var(--emerald-11));
    font-weight: 600;
    i { color: rgb(var(--emerald-10)); }
  }

  &--disabled {
    color: rgb(var(--slate-8));
    cursor: not-allowed;
    opacity: 0.6;
  }
}

.finset__sidebar-icon {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  color: rgb(var(--slate-10));
}

.finset__sidebar-label {
  flex: 1;
}

.finset__sidebar-soon {
  font-size: 9px;
  color: rgb(var(--slate-8));
  background: rgb(var(--slate-3));
  padding: 1px 6px;
  border-radius: 4px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

/* ── Main content ──────────────────────────────────────────── */
.finset__main {
  flex: 1;
  min-width: 0;            /* sem isso flex-item vaza horizontal */
  min-height: 0;           /* sem isso flex-item vaza vertical (scroll não dispara) */
  background: rgb(var(--slate-1));
  overflow-y: auto;
  overscroll-behavior: contain;
  /* Padding unificado pra todas as tabs. Tabs antigas (BankAccounts,
     Commission, Recurring, Goals) dependiam de padding do parent panel;
     agora vem daqui. Tabs novas (SettingsCategoriesTab .cat-plan e
     SettingsServicesTab .proctab) tiveram o padding interno removido
     pra não duplicar (scoped CSS não atravessa).
     Ajuste 2026-05-24: padding-left reduzido de 24→16 pra dar título e
     tabela mais perto da borda da sidebar (UX request). */
  padding: 20px 16px 28px;
}

@media (max-width: 640px) {
  .finset__main {
    padding: 14px 12px 24px;
  }
}

/* ── Mobile drawer ─────────────────────────────────────────── */
@media (max-width: 900px) {
  .finset__sidebar {
    position: fixed;
    top: 0;
    left: 0;
    bottom: 0;
    z-index: 50;
    transform: translateX(-100%);
    transition: transform 0.2s ease;
    box-shadow: 4px 0 24px rgba(0, 0, 0, 0.3);
    width: 280px;
    /* Background sólido no mobile — não pode ser translúcido porque a tela
       atrás (conteúdo) vai vazar visualmente. O backdrop já é translúcido
       e fica entre as duas camadas. */
    background: rgb(var(--slate-1));
  }
  .finset__sidebar--open {
    transform: translateX(0);
  }
}

.finset__backdrop {
  display: none;
}
@media (max-width: 900px) {
  .finset__backdrop {
    display: block;
    position: fixed;
    inset: 0;
    background: rgba(15, 23, 42, 0.5);
    backdrop-filter: blur(2px);
    z-index: 40;
  }
}
</style>
