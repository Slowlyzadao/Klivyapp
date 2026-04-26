import {
  hasPermissions,
  getUserPermissions,
  getCurrentAccount,
} from './permissionsHelper';

import {
  ROLES,
  CONVERSATION_PERMISSIONS,
  CONTACT_PERMISSIONS,
  REPORTS_PERMISSIONS,
  PORTAL_PERMISSIONS,
} from 'dashboard/constants/permissions.js';

export const routeIsAccessibleFor = (route, userPermissions = []) => {
  const { meta: { permissions: routePermissions = [] } = {} } = route;
  return hasPermissions(routePermissions, userPermissions);
};

// Klivy Custom Roles: route-name → [module, action] override map.
// When Chatwoot's role-based check rejects a route but the user's Klivy
// permissions grant the corresponding capability, the route is allowed.
// Mirrors the CHILD_GATES table in Sidebar.vue so visibility (sidebar) and
// access (router guard) stay in sync.
const KLIVY_EXACT_ROUTE_RULES = {
  // Agenda
  agenda_dashboard_index: ['agenda', 'view'],
  agenda_settings_index: ['agenda', 'view_settings'],
  agenda_custom_attributes_index: ['agenda', 'manage_custom_attributes'],
  // Settings — top-level
  general_settings_index: ['settings', 'account_view'],
  agent_list: ['settings', 'users_view'],
  labels_list: ['settings', 'labels_view'],
  attributes_list: ['settings', 'custom_attributes_view'],
  automation_list: ['settings', 'automation_view'],
  agent_bots: ['settings', 'agent_bots_view'],
  macros_wrapper: ['settings', 'macros_view'],
  macros_new: ['settings', 'macros_create'],
  macros_edit: ['settings', 'macros_edit'],
  canned_list: ['settings', 'canned_view'],
  auditlogs_list: ['settings', 'audit_view'],
  sla_list: ['settings', 'sla_view'],
  conversation_workflow_index: ['settings', 'workflow_view'],
  security_settings_index: ['settings', 'security_view'],
  billing_settings_index: ['settings', 'billing_view'],
  // Relatórios — meta.permissions é `['administrator', 'report_manage']` no
  // routes.js, então sem override o Klivy não-admin nunca acessa, mesmo com
  // a perm `reports.view_*` ligada. Estas regras dizem ao guard pra liberar
  // quando a perm Klivy correspondente está ativa.
  account_overview_reports: ['reports', 'view_overview'],
  conversation_reports: ['reports', 'view_conversation'],
  agent_reports_index: ['reports', 'view_agent'],
  agent_reports_show: ['reports', 'view_agent'],
  label_reports_index: ['reports', 'view_label'],
  label_reports_show: ['reports', 'view_label'],
  inbox_reports_index: ['reports', 'view_inbox'],
  inbox_reports_show: ['reports', 'view_inbox'],
  team_reports_index: ['reports', 'view_team'],
  team_reports_show: ['reports', 'view_team'],
  csat_reports: ['reports', 'view_csat'],
  sla_reports: ['reports', 'view_sla'],
  bot_reports: ['reports', 'view_bot'],
  agenda_reports: ['reports', 'view_agenda'],
  // Campanhas — `meta.permissions: ['administrator']` no campaigns.routes.js.
  // Sem o override aqui, Klivy não-admin com `campaigns.view` ligado bate
  // no router e é redirecionado pro dashboard padrão.
  campaigns_livechat_index: ['campaigns', 'view'],
  campaigns_sms_index: ['campaigns', 'view'],
  campaigns_whatsapp_index: ['campaigns', 'view'],
  campaigns_ongoing_index: ['campaigns', 'view'],
  campaigns_one_off_index: ['campaigns', 'view'],
  // Central de Ajuda — `portals_index` hospeda as 4 abas (artigos, categorias,
  // localidades, configurações) na mesma rota. Liberamos o acesso quando o
  // usuário tem qualquer permissão do módulo `help_center` via wildcard `*`.
  portals_index: ['help_center', '*'],
  portals_new: ['help_center', 'manage_portals'],
};

// Prefixes for grouped routes that share permission semantics.
const KLIVY_PREFIX_ROUTE_RULES = [
  ['settings_teams', ['settings', 'teams_view']],
  ['settings_inbox', ['settings', 'inboxes_view']],
  ['settings_applications', ['settings', 'integrations_view']],
  ['klivy_roles', ['settings', 'roles_view']],
  ['agent_assignment_policy', ['settings', 'users_view']],
  ['agent_capacity_policy', ['settings', 'users_view']],
  ['assignment_policy', ['settings', 'users_view']],
];

// Klivy "deny" rules: routes que o Chatwoot original libera pra qualquer
// agent, mas que o Klivy precisa restringir por sub-permissão. Se o usuário
// não for admin e não tiver a permissão Klivy listada, redireciona pro
// dashboard padrão.
const KLIVY_REQUIRED_ROUTE_RULES = {
  conversation_mentions: ['chat', 'view_mentions'],
  conversation_through_mentions: ['chat', 'view_mentions'],
  conversation_unattended: ['chat', 'view_unassigned'],
  conversation_through_unattended: ['chat', 'view_unassigned'],
  // BEA (Captain) — cada sub-página exige sub-permissão Klivy específica
  captain_assistants_responses_index: ['captain', 'manage_faqs'],
  captain_assistants_responses_pending: ['captain', 'manage_faqs'],
  captain_assistants_documents_index: ['captain', 'manage_documents'],
  captain_assistants_scenarios_index: ['captain', 'manage_scenarios'],
  captain_assistants_playground_index: ['captain', 'use_playground'],
  captain_assistants_inboxes_index: ['captain', 'manage_inboxes'],
  captain_tools_index: ['captain', 'manage_tools'],
  captain_assistants_settings_index: ['captain', 'manage_settings'],
  captain_assistants_guidelines_index: ['captain', 'manage_settings'],
  captain_assistants_guardrails_index: ['captain', 'manage_settings'],
  // Financeiro — cada subpágina exige sub-permissão Klivy específica.
  // Sem a permissão, o reload em /financial/cash-flow etc. cai em /forbidden
  // em vez de carregar a página silenciosamente.
  financial_dashboard_index: ['financial', 'view_dashboard'],
  financial_cash_flow: ['financial', 'view_cashflow'],
  financial_receivables: ['financial', 'view_receivables'],
  financial_payables: ['financial', 'view_payables'],
  financial_dre: ['financial', 'view_dre'],
  financial_reports: ['financial', 'view_reports'],
  financial_cash_register: ['financial', 'view_cash_register'],
  financial_settings: ['financial', 'manage_settings'],
  // Contatos — abas e visualizações.
  contacts_dashboard_index: ['contacts', 'view_all'],
  contacts_dashboard_active: ['contacts', 'view_active'],
  contacts_dashboard_segments_index: ['contacts', 'manage_segments'],
  contacts_dashboard_labels_index: ['contacts', 'manage_tags'],
  // Relatórios — cada aba tem sua sub-perm específica.
  account_overview_reports: ['reports', 'view_overview'],
  conversation_reports: ['reports', 'view_conversation'],
  agent_reports_index: ['reports', 'view_agent'],
  agent_reports_show: ['reports', 'view_agent'],
  label_reports_index: ['reports', 'view_label'],
  label_reports_show: ['reports', 'view_label'],
  inbox_reports_index: ['reports', 'view_inbox'],
  inbox_reports_show: ['reports', 'view_inbox'],
  team_reports_index: ['reports', 'view_team'],
  team_reports_show: ['reports', 'view_team'],
  csat_reports: ['reports', 'view_csat'],
  sla_reports: ['reports', 'view_sla'],
  bot_reports: ['reports', 'view_bot'],
  agenda_reports: ['reports', 'view_agenda'],
  // Campanhas — exige `campaigns.view`. Reload em /campaigns/sms etc.
  // sem a perm cai em /forbidden.
  campaigns_livechat_index: ['campaigns', 'view'],
  campaigns_sms_index: ['campaigns', 'view'],
  campaigns_whatsapp_index: ['campaigns', 'view'],
  campaigns_ongoing_index: ['campaigns', 'view'],
  campaigns_one_off_index: ['campaigns', 'view'],
  // Central de Ajuda — `portals_index` é a rota real (as 4 abas usam
  // navigationPath). Exige qualquer permissão do módulo help_center.
  portals_index: ['help_center', '*'],
  portals_new: ['help_center', 'manage_portals'],
};

const klivyRuleFor = routeName => {
  if (!routeName) return null;
  if (KLIVY_EXACT_ROUTE_RULES[routeName]) {
    return KLIVY_EXACT_ROUTE_RULES[routeName];
  }
  const prefix = KLIVY_PREFIX_ROUTE_RULES.find(([p]) => routeName.startsWith(p));
  return prefix ? prefix[1] : null;
};

export const routeIsAccessibleByKlivy = (route, klivyPermissions) => {
  const rule = klivyRuleFor(route?.name);
  if (!rule) return false;
  const modulePerms = klivyPermissions?.[rule[0]];
  if (!modulePerms) return false;
  // wildcard `*` — qualquer sub-permissão do módulo libera a rota.
  if (rule[1] === '*') {
    return Object.entries(modulePerms).some(
      ([k, v]) => k !== 'scope' && v === true
    );
  }
  return modulePerms[rule[1]] === true;
};

export const defaultRedirectPage = (to, permissions) => {
  const { accountId } = to.params;

  const permissionRoutes = [
    {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
      path: 'dashboard',
    },
    { permissions: [CONTACT_PERMISSIONS], path: 'contacts' },
    { permissions: [REPORTS_PERMISSIONS], path: 'reports/overview' },
    { permissions: [PORTAL_PERMISSIONS], path: 'portals' },
  ];

  const route = permissionRoutes.find(({ permissions: routePermissions }) =>
    hasPermissions(routePermissions, permissions)
  );

  return `accounts/${accountId}/${route ? route.path : 'dashboard'}`;
};

const validateActiveAccountRoutes = (to, user, klivyPermissions) => {
  // If the current account is active, then check for the route permissions
  const accountDashboardURL = `accounts/${to.params.accountId}/dashboard`;

  // If the user is trying to access suspended route, redirect them to dashboard
  if (to.name === 'account_suspended') {
    return accountDashboardURL;
  }

  const userPermissions = getUserPermissions(user, to.params.accountId);
  const isNativeAdmin = userPermissions.includes('administrator');

  // Klivy "deny" enforcement: rotas marcadas em KLIVY_REQUIRED_ROUTE_RULES
  // exigem a sub-permissão Klivy mesmo que o Chatwoot libere pelo role.
  // Admins nativos passam direto. Sem a permissão, manda pra página
  // /forbidden (Page403, com cadeado e mensagem) em vez do dashboard.
  if (!isNativeAdmin) {
    const required = KLIVY_REQUIRED_ROUTE_RULES[to.name];
    if (required) {
      const modulePerms = klivyPermissions?.[required[0]];
      const has =
        required[1] === '*'
          ? !!modulePerms &&
            Object.entries(modulePerms).some(
              ([k, v]) => k !== 'scope' && v === true
            )
          : modulePerms?.[required[1]] === true;
      if (!has) return `accounts/${to.params.accountId}/forbidden`;
    }
  }

  const isAccessible = routeIsAccessibleFor(to, userPermissions);
  if (isAccessible) return null;

  // Klivy Custom Roles fallback: if the user's role granted this route via
  // the catalog, allow access even when Chatwoot's `meta.permissions` would
  // redirect (Settings routes are tagged `administrator` in core).
  if (routeIsAccessibleByKlivy(to, klivyPermissions)) return null;

  // Otherwise redirect to the user's default landing page.
  return defaultRedirectPage(to, userPermissions);
};

export const validateLoggedInRoutes = (to, user, klivyPermissions) => {
  const currentAccount = getCurrentAccount(user, Number(to.params.accountId));
  // If current account is missing, either user does not have
  // access to the account or the account is deleted, return to login screen
  if (!currentAccount) {
    return `app/login`;
  }

  const isCurrentAccountActive = currentAccount.status === 'active';

  if (isCurrentAccountActive) {
    return validateActiveAccountRoutes(to, user, klivyPermissions);
  }

  // If the current account is not active, then redirect the user to the suspended screen
  if (to.name !== 'account_suspended') {
    return `accounts/${to.params.accountId}/suspended`;
  }

  // Proceed to the route if none of the above conditions are met
  return null;
};

export const isAConversationRoute = (
  routeName,
  includeBase = false,
  includeExtended = true
) => {
  const baseRoutes = [
    'home',
    'conversation_mentions',
    'conversation_unattended',
    'inbox_dashboard',
    'label_conversations',
    'team_conversations',
    'folder_conversations',
    'conversation_participating',
  ];
  const extendedRoutes = [
    'inbox_conversation',
    'conversation_through_mentions',
    'conversation_through_unattended',
    'conversation_through_inbox',
    'conversations_through_label',
    'conversations_through_team',
    'conversations_through_folders',
    'conversation_through_participating',
  ];

  const routes = [
    ...(includeBase ? baseRoutes : []),
    ...(includeExtended ? extendedRoutes : []),
  ];

  return routes.includes(routeName);
};

export const getConversationDashboardRoute = routeName => {
  switch (routeName) {
    case 'inbox_conversation':
      return 'home';
    case 'conversation_through_mentions':
      return 'conversation_mentions';
    case 'conversation_through_unattended':
      return 'conversation_unattended';
    case 'conversations_through_label':
      return 'label_conversations';
    case 'conversations_through_team':
      return 'team_conversations';
    case 'conversations_through_folders':
      return 'folder_conversations';
    case 'conversation_through_participating':
      return 'conversation_participating';
    case 'conversation_through_inbox':
      return 'inbox_dashboard';
    default:
      return null;
  }
};

export const isAInboxViewRoute = (routeName, includeBase = false) => {
  const baseRoutes = ['inbox_view'];
  const extendedRoutes = ['inbox_view_conversation'];
  const routeNames = includeBase
    ? [...baseRoutes, ...extendedRoutes]
    : extendedRoutes;
  return routeNames.includes(routeName);
};

export const isNotificationRoute = routeName =>
  routeName === 'notifications_index';
