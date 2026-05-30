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
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

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
  // KlivyRoles — granularidade por action (auditoria C-1):
  // prefix `klivy_roles` em KLIVY_PREFIX_ROUTE_RULES casava `_list`/`_new`/`_edit`
  // com a mesma perm `roles_view` (leitura), abrindo criação/edição para quem só
  // deveria visualizar. Cada nome de rota agora exige a perm coerente com a
  // action do controller (`roles_view` / `roles_create` / `roles_edit`).
  klivy_roles_list: ['settings', 'roles_view'],
  klivy_roles_new: ['settings', 'roles_create'],
  klivy_roles_edit: ['settings', 'roles_edit'],
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
  // Inboxes — granularidade por action (auditoria A-4):
  // prefix `settings_inbox`/`settings_inboxes` casava `_new`/`_finish`/`_page_channel`/
  // `_add_agents` com `inboxes_view`, abrindo CRUD completo de inbox para quem só
  // deveria visualizar. Cada rota agora exige a perm coerente.
  settings_inbox_list: ['settings', 'inboxes_view'],
  settings_inbox_show: ['settings', 'inboxes_view'],
  settings_inbox_new: ['settings', 'inboxes_create'],
  settings_inbox_finish: ['settings', 'inboxes_create'],
  settings_inboxes_page_channel: ['settings', 'inboxes_create'],
  settings_inboxes_add_agents: ['settings', 'inboxes_manage_agents'],
  // Teams — granularidade por action (auditoria A-4):
  // prefix `settings_teams` casava `_new`/`_finish`/`_add_agents`/`_edit`/`_edit_members`/
  // `_edit_finish` com `teams_view`, abrindo CRUD completo de teams para quem só
  // deveria visualizar.
  settings_teams_list: ['settings', 'teams_view'],
  settings_teams_new: ['settings', 'teams_create'],
  settings_teams_finish: ['settings', 'teams_create'],
  settings_teams_add_agents: ['settings', 'teams_create'],
  settings_teams_edit: ['settings', 'teams_edit'],
  settings_teams_edit_members: ['settings', 'teams_edit'],
  settings_teams_edit_finish: ['settings', 'teams_edit'],
  // Integrations — granularidade por action (auditoria A-4):
  // prefix `settings_applications` casava `settings_applications_integration` (página
  // de detalhe), expondo a configuração de uma integração específica para qualquer
  // usuário com `integrations_view`. Actions de conectar/desconectar permanecem
  // protegidas no backend.
  settings_applications: ['settings', 'integrations_view'],
  settings_applications_integration: ['settings', 'integrations_view'],
  // Advanced assignment policies — granularidade por action (auditoria A-4):
  // prefixes `assignment_policy`/`agent_assignment_policy`/`agent_capacity_policy`
  // casavam `_create`/`_edit` com `users_view`. Leitura continua com `users_view`;
  // criar e editar policies agora requer `users_edit` (mesma perm do editor de agente).
  assignment_policy_index: ['settings', 'users_view'],
  agent_assignment_policy_index: ['settings', 'users_view'],
  agent_assignment_policy_create: ['settings', 'users_edit'],
  agent_assignment_policy_edit: ['settings', 'users_edit'],
  agent_capacity_policy_index: ['settings', 'users_view'],
  agent_capacity_policy_create: ['settings', 'users_edit'],
  agent_capacity_policy_edit: ['settings', 'users_edit'],
};

// Todos os prefixes foram migrados para EXACT rules em KLIVY_EXACT_ROUTE_RULES
// (auditoria C-1 + A-4). Prefix matching é frágil: `settings_teams` cobria
// `_new`/`_edit`/etc. com a mesma perm de leitura. Mantemos o objeto vazio para
// preservar o contrato da API (`klivyPrefixRule` retorna undefined => fallback).
const KLIVY_PREFIX_ROUTE_RULES = {};

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
  // Patients pages (auditoria A-2) — meta.permissions é ['administrator','agent']
  // (libera qualquer agent). Sem este deny, qualquer agent acessa o prontuário
  // por URL mesmo sem perm `patients.*`. Sidebar usa `moduleEnabled('patients')`
  // que é fail-open (mostra se módulo não está no hash) — backstop aqui.
  patients_dashboard_index: ['patients', 'view'],
  patients_dashboard_record: ['patients', 'view'],
  // Ajuda (Central de Ajuda do plugin Klivy — auditoria A-2). Sem deny, qualquer
  // agent acessa via URL. `help.view` é a única perm desse módulo.
  ajuda_dashboard_index: ['help', 'view'],
  ajuda_report_bug: ['help', 'view'],
  ajuda_feature_request: ['help', 'view'],
  // Agenda (auditoria A-3) — promove de KLIVY_EXACT (allow list noop pra rotas
  // que Chatwoot já libera) para KLIVY_REQUIRED (deny list real). Cobre acesso
  // por URL direta mesmo quando sidebar gating não aparece.
  agenda_dashboard_index: ['agenda', 'view'],
  agenda_categories_index: ['agenda', 'view'],
  agenda_settings_index: ['agenda', 'view_settings'],
  agenda_custom_attributes_index: ['agenda', 'manage_custom_attributes'],
  // Captain / BEA (auditoria A-1) — meta.permissions é ['administrator','agent']
  // E sub-rotas são protegidas por feature flag, mas sem deny por perm Klivy
  // qualquer agent com o flag acessava todas as sub-páginas via URL.
  captain_assistants_index: ['captain', 'view'],
  captain_assistants_create_index: ['captain', 'view'],
  captain_assistants_responses_index: ['captain', 'manage_faqs'],
  captain_assistants_responses_pending: ['captain', 'manage_faqs'],
  captain_assistants_documents_index: ['captain', 'manage_documents'],
  captain_assistants_scenarios_index: ['captain', 'manage_scenarios'],
  captain_assistants_playground_index: ['captain', 'use_playground'],
  captain_assistants_inboxes_index: ['captain', 'manage_inboxes'],
  captain_tools_index: ['captain', 'manage_tools'],
  captain_assistants_settings_index: ['captain', 'manage_settings'],
  captain_assistants_guardrails_index: ['captain', 'manage_settings'],
  captain_assistants_guidelines_index: ['captain', 'manage_settings'],
  // Companies (Chatwoot Enterprise feature) — propositadamente NÃO mapeada:
  // não há módulo `companies` em shared/modules.js (Klivy não usa hoje).
  // Mantém comportamento atual (qualquer agent acessa). Anotado em
  // CUSTOM_ROLES_AUDITORIA_COMPLETA para abordagem futura.
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

// Verdadeiro quando o store `beclinicPermissions` já teve a primeira resposta
// do `GET /beclinic_permissions` aplicada (mesmo que tenha vindo `{}`). Antes
// disso a navegação inicial (F5/URL direta) chega no `router.beforeEach` com
// `klivyPermissions = {}` — e qualquer regra KLIVY_REQUIRED (deny list)
// bloquearia toda rota, redirecionando pra dashboard. Pra evitar esse falso
// positivo, o gate só é aplicado quando o hash tem ao menos uma chave de
// módulo presente. Race window: até o fetch terminar, KLIVY_REQUIRED é
// fail-open — sidebar gates e backend Pundit cobrem (ver auditoria Lote 8,
// race condition encontrada durante validação).
const isKlivyPermissionsLoaded = perms =>
  perms && typeof perms === 'object' && Object.keys(perms).length > 0;

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
  //
  // Guard `isKlivyPermissionsLoaded`: F5/URL direta dispara o `beforeEach` ANTES
  // do `App.vue#mounted` ter completado `beclinicPermissions/fetch`. Sem este
  // guard, `klivyHasPermission({}, rule)` sempre retorna false e bloqueia toda
  // rota mapeada → user fica preso no dashboard. Quando o store carrega, o
  // sidebar e o backend Pundit fazem o gating real.
  if (!isNativeAdmin && isKlivyPermissionsLoaded(klivyPermissions)) {
    const requiredRule = klivyRequiredRule(to.name);
    if (requiredRule && !klivyHasPermission(klivyPermissions, requiredRule)) {
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

const readLastOpenedConversationMap = () => {
  try {
    const raw = localStorage.getItem(
      LOCAL_STORAGE_KEYS.LAST_OPENED_CONVERSATION
    );
    if (!raw) return {};
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
};

export const getLastOpenedConversationId = accountId => {
  if (!accountId) return null;
  const map = readLastOpenedConversationMap();
  const value = map[String(accountId)];
  return value ? Number(value) : null;
};

export const setLastOpenedConversationId = (accountId, conversationId) => {
  if (!accountId || !conversationId) return;
  try {
    const map = readLastOpenedConversationMap();
    map[String(accountId)] = Number(conversationId);
    localStorage.setItem(
      LOCAL_STORAGE_KEYS.LAST_OPENED_CONVERSATION,
      JSON.stringify(map)
    );
  } catch {
    // ignore quota / serialization errors
  }
};
