import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions.js';
import FinancialV2 from './v2/api/financialV2';

// Guard: bloqueia rotas operacionais do v2 quando setup obrigatório incompleto.
// Aplicado nas rotas via `beforeEnter`. Setup wizard e Settings ficam isentos
// (operador precisa acessá-los pra completar o setup).
async function requireFinancialSetup(to, _from, next) {
  try {
    const { data } = await FinancialV2.setup.show();
    if (!data?.required_steps_done) {
      return next({
        name: 'financial_v2_setup',
        params: { accountId: to.params.accountId },
      });
    }
  } catch (e) {
    // Backend offline ou erro de auth: deixa passar pra UI mostrar o erro
    // real em vez de loop de redirect.
  }
  return next();
}

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
const CashFlowV2 = () => import('./v2/pages/CashFlowV2.vue');
const CommissionsV2 = () => import('./v2/pages/CommissionsV2.vue');
const ReportsHubV2 = () => import('./v2/pages/ReportsHubV2.vue');
const SetupWizardV2 = () => import('./v2/components/SetupWizardV2.vue');
// F2 do PaymentPlanWizardV2 — página dev oculta (não exposta em menu).
// Permite QA/dev validarem o wizard contra um budget real antes da F3
// plugar nos entry points reais atrás de feature flag.
const PaymentPlanWizardPreview = () => import('./v2/pages/PaymentPlanWizardPreview.vue');
// PR audit 2026-05-21: AuditLogsV2, BackupsV2, AccountantExportV2, LgpdV2 e
// ReclassifyV2 não são mais importados aqui — viraram tabs dentro de
// SettingsV2 e são importados lá direto. As rotas com esses names viraram
// redirect (preservam URLs antigas pra bookmarks).

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
  // Wizard de setup — única rota operacional SEM `beforeEnter` (seria recursivo).
  {
    path: frontendURL('accounts/:accountId/financial/v2/setup'),
    name: 'financial_v2_setup',
    meta: { permissions: [...ROLES] },
    component: SetupWizardV2,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2'),
    name: 'financial_v2_dashboard',
    meta: { permissions: [...ROLES] },
    component: DashboardV2,
    beforeEnter: requireFinancialSetup,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/cash-flow'),
    name: 'financial_v2_cash_flow',
    meta: { permissions: [...ROLES] },
    component: CashFlowV2,
    beforeEnter: requireFinancialSetup,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/receivables'),
    name: 'financial_v2_receivables',
    meta: { permissions: [...ROLES] },
    component: ReceivablesV2,
    beforeEnter: requireFinancialSetup,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/payables'),
    name: 'financial_v2_payables',
    meta: { permissions: [...ROLES] },
    component: PayablesV2,
    beforeEnter: requireFinancialSetup,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/dre'),
    name: 'financial_v2_dre',
    meta: { permissions: [...ROLES] },
    component: DreV2,
    beforeEnter: requireFinancialSetup,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/commissions'),
    name: 'financial_v2_commissions',
    meta: { permissions: [...ROLES] },
    component: CommissionsV2,
    beforeEnter: requireFinancialSetup,
  },
  // Hub de relatórios — refator card-grid 2026-05-23.
  // `/financial/v2/reports` agora renderiza o LANDING (8 cards em 3 grupos);
  // `/financial/v2/reports/:tab` abre o detalhe do relatório específico.
  // Antes redirecionava pra primeira tab; agora a landing é uma página
  // legítima (sem redirect), pra usuário escolher o relatório.
  {
    path: frontendURL('accounts/:accountId/financial/v2/reports'),
    name: 'financial_v2_reports_hub',
    meta: { permissions: [...ROLES] },
    component: ReportsHubV2,
    beforeEnter: requireFinancialSetup,
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/reports/:tab'),
    name: 'financial_v2_reports_hub_tab',
    meta: { permissions: [...ROLES] },
    component: ReportsHubV2,
    props: true,
    beforeEnter: requireFinancialSetup,
  },
  // PR audit 2026-05-21: 5 telas (Auditoria/Backups/Contador/LGPD/Reclassificar)
  // foram movidas pra dentro de Configurações como tabs. URLs antigas
  // continuam funcionando via redirect 302 — preserva bookmarks, links em
  // emails e referências em documentação. Quando o redirect aciona, o
  // SettingsV2 renderiza a page correspondente com `embedded=true`
  // (esconde o header próprio da page pra não duplicar com o header de
  // Configurações). Componentes seguem importados acima porque agora são
  // renderizados via TABS dentro de SettingsV2.vue.
  {
    path: frontendURL('accounts/:accountId/financial/v2/audit'),
    name: 'financial_v2_audit',
    redirect: to => ({ name: 'financial_v2_settings_tab', params: { ...to.params, tab: 'audit' } }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/backups'),
    name: 'financial_v2_backups',
    redirect: to => ({ name: 'financial_v2_settings_tab', params: { ...to.params, tab: 'backups' } }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/accountant-export'),
    name: 'financial_v2_accountant_export',
    redirect: to => ({ name: 'financial_v2_settings_tab', params: { ...to.params, tab: 'accountant-export' } }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/lgpd'),
    name: 'financial_v2_lgpd',
    redirect: to => ({ name: 'financial_v2_settings_tab', params: { ...to.params, tab: 'lgpd' } }),
  },
  {
    path: frontendURL('accounts/:accountId/financial/v2/cash-register'),
    name: 'financial_v2_cash_register',
    meta: { permissions: [...ROLES] },
    component: CashRegisterV2,
    beforeEnter: requireFinancialSetup,
  },
  // Reclassificação em massa de lançamentos sem categoria — canon F-28.
  // Movida pra Configurações junto com Auditoria/Backups/etc. na mesma PR.
  {
    path: frontendURL('accounts/:accountId/financial/v2/reclassify'),
    name: 'financial_v2_reclassify',
    redirect: to => ({ name: 'financial_v2_settings_tab', params: { ...to.params, tab: 'reclassify' } }),
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
  // ─────────────────────────────────────────────────────────────────────────
  // F2 do PaymentPlanWizardV2 — rota oculta de preview/QA
  //
  // Acesso direto por URL: /app/accounts/:accountId/financial/v2/_dev/payment-plan-wizard?budget_id=X
  // Não exposta em nenhum menu — F3 plugará o wizard nos entry points reais
  // (aba do paciente, A Receber) atrás de feature flag `payment_plan_wizard_v2`.
  // Sem `beforeEnter: requireFinancialSetup` porque é dev preview — pode rodar
  // mesmo com setup incompleto pra testar UI.
  // ─────────────────────────────────────────────────────────────────────────
  {
    path: frontendURL('accounts/:accountId/financial/v2/_dev/payment-plan-wizard'),
    name: 'financial_v2_dev_payment_plan_wizard',
    meta: { permissions: [...ROLES] },
    component: PaymentPlanWizardPreview,
  },
];
