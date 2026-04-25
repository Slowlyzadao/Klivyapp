import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES } from 'dashboard/constants/permissions.js';

const FinancialDashboard = () => import('./pages/FinancialDashboard.vue');
const CashFlow = () => import('./pages/CashFlow.vue');
const Receivables = () => import('./pages/Receivables.vue');
const Payables = () => import('./pages/Payables.vue');
const DRE = () => import('./pages/DRE.vue');
const Reports = () => import('./pages/Reports.vue');
const CashRegister = () => import('./pages/CashRegister.vue');
const FinancialSettings = () => import('./pages/FinancialSettings.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/financial'),
    name: 'financial_dashboard_index',
    meta: { permissions: [...ROLES] },
    component: FinancialDashboard,
  },
  {
    path: frontendURL('accounts/:accountId/financial/cash-flow'),
    name: 'financial_cash_flow',
    meta: { permissions: [...ROLES] },
    component: CashFlow,
  },
  {
    path: frontendURL('accounts/:accountId/financial/receivables'),
    name: 'financial_receivables',
    meta: { permissions: [...ROLES] },
    component: Receivables,
  },
  {
    path: frontendURL('accounts/:accountId/financial/payables'),
    name: 'financial_payables',
    meta: { permissions: [...ROLES] },
    component: Payables,
  },
  {
    path: frontendURL('accounts/:accountId/financial/dre'),
    name: 'financial_dre',
    meta: { permissions: [...ROLES] },
    component: DRE,
  },
  {
    path: frontendURL('accounts/:accountId/financial/reports'),
    name: 'financial_reports',
    meta: { permissions: [...ROLES] },
    component: Reports,
  },
  {
    path: frontendURL('accounts/:accountId/financial/cash-register'),
    name: 'financial_cash_register',
    meta: { permissions: [...ROLES] },
    component: CashRegister,
  },
  {
    path: frontendURL('accounts/:accountId/financial/settings'),
    name: 'financial_settings',
    meta: { permissions: [...ROLES] },
    component: FinancialSettings,
  },
];
