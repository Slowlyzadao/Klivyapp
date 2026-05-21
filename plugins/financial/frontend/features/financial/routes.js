import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions.js';

// Código legacy v1 removido em 2026-05-11 (Deprecation Etapa 1 + A).
// As rotas v1 abaixo viram apenas redirects pra v2 pra manter bookmarks
// e links externos funcionando — não há mais componente v1 carregável.

// v2 (canon Financial::*)
const DashboardV2 = () => import('./v2/pages/DashboardV2.vue');
const ReceivablesV2 = () => import('./v2/pages/ReceivablesV2.vue');
const PayablesV2 = () => import('./v2/pages/PayablesV2.vue');
const DreV2 = () => import('./v2/pages/DreV2.vue');
const CashRegisterV2 = () => import('./v2/pages/CashRegisterV2.vue');
const SettingsV2 = () => import('./v2/pages/SettingsV2.vue');
const ReclassifyV2 = () => import('./v2/pages/ReclassifyV2.vue');
const CashFlowV2 = () => import('./v2/pages/CashFlowV2.vue');
const CommissionsV2 = () => import('./v2/pages/CommissionsV2.vue');
const ReportsHubV2 = () => import('./v2/pages/ReportsHubV2.vue');
const AuditLogsV2 = () => import('./v2/pages/AuditLogsV2.vue');
const BackupsV2 = () => import('./v2/pages/BackupsV2.vue');
const AccountantExportV2 = () => import('./v2/pages/AccountantExportV2.vue');
const LgpdV2 = () => import('./v2/pages/LgpdV2.vue');

export const routes = [
  // ─────────────────────────────────────────────────────────────────────────
  // Redirects legados v1 → v2 (Deprecation Etapa 1+A, 2026-05-11)
  //
  // URLs antigas (`/financial`, `/financial/cash-flow`, etc) redirecionam
  // para v2 — bookmarks, links externos e referências em emails continuam
  // funcionando. Componentes v1 já deletados; os redirects sobrevivem só
  // pra preservar URLs públicas.
  // ─────────────────────────────────────────────────────────────────────────
  {
    path: frontendURL('accounts/:accountId/financial'),
    name: 'financial_dashboard_index',
    redirect: to => ({ name: 'financial_v2_dashboard', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/cash-flow'),
    name: 'financial_cash_flow',
    redirect: to => ({ name: 'financial_v2_cash_flow', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/receivables'),
    name: 'financial_receivables',
    redirect: to => ({ name: 'financial_v2_receivables', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/payables'),
    name: 'financial_payables',
    redirect: to => ({ name: 'financial_v2_payables', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/dre'),
    name: 'financial_dre',
    redirect: to => ({ name: 'financial_v2_dre', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/reports'),
    name: 'financial_reports',
    redirect: to => ({
      name: 'financial_v2_reports_hub_tab',
      params: { ...to.params, tab: 'expenses' },
    }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/cash-register'),
    name: 'financial_cash_register',
    redirect: to => ({ name: 'financial_v2_cash_register', params: to.params }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/settings'),
    name: 'financial_settings',
    redirect: to => ({
      name: 'financial_v2_settings_tab',
      params: { ...to.params, tab: 'categories' },
    }),
  },
  // ----- v2 (canon Financial::*) -----
  {
    path: frontendURL('accounts/:accountId/financial/v2'),
    name: 'financial_v2_dashboard',
    meta: { permissions: [...ROLES] },
    component: DashboardV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/cash-flow'),
    name: 'financial_v2_cash_flow',
    meta: { permissions: [...ROLES] },
    component: CashFlowV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/receivables'),
    name: 'financial_v2_receivables',
    meta: { permissions: [...ROLES] },
    component: ReceivablesV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/payables'),
    name: 'financial_v2_payables',
    meta: { permissions: [...ROLES] },
    component: PayablesV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/dre'),
    name: 'financial_v2_dre',
    meta: { permissions: [...ROLES] },
    component: DreV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/commissions'),
    name: 'financial_v2_commissions',
    meta: { permissions: [...ROLES] },
    component: CommissionsV2,
  },
  // Hub de relatórios — espelha o padrão de Settings com URL-driven tabs.
  // /financial/v2/reports → redireciona pra primeira tab.
  {
    path: frontendURL('accounts/:accountId/financial/v2/reports'),
    name: 'financial_v2_reports_hub',
    redirect: to => ({
      name: 'financial_v2_reports_hub_tab',
      params: { ...to.params, tab: 'expenses' },
    }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/reports/:tab'),
    name: 'financial_v2_reports_hub_tab',
    meta: { permissions: [...ROLES] },
    component: ReportsHubV2,
    props: true,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/audit'),
    name: 'financial_v2_audit',
    meta: { permissions: [...ROLES] },
    component: AuditLogsV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/backups'),
    name: 'financial_v2_backups',
    meta: { permissions: [...ROLES] },
    component: BackupsV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/accountant-export'),
    name: 'financial_v2_accountant_export',
    meta: { permissions: [...ROLES] },
    component: AccountantExportV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/lgpd'),
    name: 'financial_v2_lgpd',
    meta: { permissions: [...ROLES] },
    component: LgpdV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/cash-register'),
    name: 'financial_v2_cash_register',
    meta: { permissions: [...ROLES] },
    component: CashRegisterV2,
  },
  // Reclassificação em massa de lançamentos sem categoria — canon F-28
  {
    path: frontendURL('accounts/:accountId/financial/v2/reclassify'),
    name: 'financial_v2_reclassify',
    meta: { permissions: [...ROLES] },
    component: ReclassifyV2,
  },
  // Configurações v2 — 5 tabs (Categorias, Contas, Comissão, Recorrentes, Metas) — canon §4
  {
    path: frontendURL('accounts/:accountId/financial/v2/settings'),
    name: 'financial_v2_settings',
    redirect: to => ({ name: 'financial_v2_settings_tab', params: { ...to.params, tab: 'categories' } }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/settings/:tab'),
    name: 'financial_v2_settings_tab',
    meta: { permissions: [...ROLES] },
    component: SettingsV2,
    props: true,
  },
];
