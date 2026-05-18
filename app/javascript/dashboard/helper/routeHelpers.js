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

// =====================================================
// Klivy custom-role route rules
// =====================================================
// Three rule types working alongside the Chatwoot native check:
//
//   KLIVY_EXACT_ROUTE_RULES   — allow list, exact route name match.
//                               If Chatwoot denies AND Klivy grants, allow.
//   KLIVY_PREFIX_ROUTE_RULES  — allow list, prefix match on route name.
//                               Same fallback semantics as exact rules.
//   KLIVY_REQUIRED_ROUTE_RULES — deny list. If Chatwoot allows but Klivy is
//                               missing the perm, redirect anyway.
//                               Used for routes whose meta.permissions is too
//                               loose (e.g. covers any agent) but should be
//                               gated by Klivy regardless.
const KLIVY_EXACT_ROUTE_RULES = {
  // Settings (admin-only natively, surfaced for Klivy custom roles)
  agent_list: ['settings', 'users_view'],
  labels_list: ['settings', 'labels_view'],
  attributes_list: ['settings', 'custom_attributes_view'],
  automation_list: ['settings', 'automation_view'],
  auditlogs_list: ['settings', 'audit_view'],
  general_settings_index: ['settings', 'account_view'],
  security_settings_index: ['settings', 'security_view'],
  billing_settings_index: ['settings', 'billing_view'],
  sla_list: ['settings', 'sla_view'],
  conversation_workflow_index: ['settings', 'workflow_view'],
  agent_bots: ['settings', 'agent_bots_view'],
  // Agenda (Klivy plugin)
  agenda_dashboard_index: ['agenda', 'view'],
  agenda_settings_index: ['agenda', 'view_settings'],
  agenda_custom_attributes_index: ['agenda', 'manage_custom_attributes'],
  agenda_categories_index: ['agenda', 'view'],
  // Reports (admin-only natively, surfaced for Klivy)
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
  // Campaigns (admin-only natively)
  campaigns_livechat_index: ['campaigns', 'view'],
  campaigns_sms_index: ['campaigns', 'view'],
  campaigns_whatsapp_index: ['campaigns', 'view'],
  campaigns_ongoing_index: ['campaigns', 'view'],
  campaigns_one_off_index: ['campaigns', 'view'],
};

const KLIVY_PREFIX_ROUTE_RULES = {
  settings_teams: ['settings', 'teams_view'],
  settings_inbox: ['settings', 'inboxes_view'],
  settings_applications: ['settings', 'integrations_view'],
  settings_inboxes: ['settings', 'inboxes_view'],
  klivy_roles: ['settings', 'roles_view'],
  agent_assignment_policy: ['settings', 'users_view'],
  agent_capacity_policy: ['settings', 'users_view'],
  assignment_policy: ['settings', 'users_view'],
};

const KLIVY_REQUIRED_ROUTE_RULES = {
  // Conversation tabs that the native CONVERSATION_PERMISSIONS allows for any
  // agent — but Klivy must still enforce per-tab visibility.
  conversation_mentions: ['chat', 'view_mentions'],
  conversation_through_mentions: ['chat', 'view_mentions'],
  conversation_unattended: ['chat', 'view_unassigned'],
  conversation_through_unattended: ['chat', 'view_unassigned'],
  // Financial pages (Klivy plugin) — meta.permissions is [...ROLES] which
  // covers any agent, so we deny here when Klivy perms are missing.
  financial_dashboard_index: ['financial', 'view_dashboard'],
  financial_cash_flow: ['financial', 'view_cashflow'],
  financial_receivables: ['financial', 'view_receivables'],
  financial_payables: ['financial', 'view_payables'],
  financial_dre: ['financial', 'view_dre'],
  financial_reports: ['financial', 'view_reports'],
  financial_cash_register: ['financial', 'view_cash_register'],
  financial_settings: ['financial', 'manage_settings'],
  // Contacts pages
  contacts_dashboard_index: ['contacts', 'view_all'],
  contacts_dashboard_active: ['contacts', 'view_active'],
  contacts_dashboard_segments_index: ['contacts', 'manage_segments'],
  contacts_dashboard_labels_index: ['contacts', 'manage_tags'],
};

const klivyHasPermission = (klivyPermissions, [moduleKey, action]) => {
  if (!klivyPermissions || typeof klivyPermissions !== 'object') return false;
  const mod = klivyPermissions[moduleKey];
  return Boolean(mod && mod[action] === true);
};

const klivyExactRule = routeName =>
  routeName ? KLIVY_EXACT_ROUTE_RULES[routeName] : undefined;

const klivyPrefixRule = routeName => {
  if (!routeName) return undefined;
  const found = Object.entries(KLIVY_PREFIX_ROUTE_RULES).find(([prefix]) =>
    routeName.startsWith(prefix)
  );
  return found ? found[1] : undefined;
};

const klivyRequiredRule = routeName =>
  routeName ? KLIVY_REQUIRED_ROUTE_RULES[routeName] : undefined;

const routeIsAccessibleByKlivy = (routeName, klivyPermissions) => {
  const rule = klivyExactRule(routeName) || klivyPrefixRule(routeName);
  if (!rule) return false;
  return klivyHasPermission(klivyPermissions, rule);
};

export const routeIsAccessibleFor = (route, userPermissions = []) => {
  const { meta: { permissions: routePermissions = [] } = {} } = route;
  return hasPermissions(routePermissions, userPermissions);
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
  const isNativeAdmin = (userPermissions || []).includes('administrator');

  // Klivy deny rule: even if Chatwoot would let the user pass, refuse if the
  // route is mapped and the user lacks the Klivy perm. Skip for native admins
  // so vanilla Chatwoot installs are unaffected.
  if (!isNativeAdmin) {
    const requiredRule = klivyRequiredRule(to.name);
    if (
      requiredRule &&
      !klivyHasPermission(klivyPermissions, requiredRule)
    ) {
      return defaultRedirectPage(to, userPermissions);
    }
  }

  // Native Chatwoot RBAC.
  if (routeIsAccessibleFor(to, userPermissions)) return null;

  // Klivy fallback: if the route is mapped and Klivy grants, allow.
  if (routeIsAccessibleByKlivy(to.name, klivyPermissions)) return null;

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
