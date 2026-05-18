import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import AgendaDashboard from './AgendaDashboard.vue';
import AgendaSettings from './settings/Index.vue';
import AgendaCustomAttributes from './customAttributes/Index.vue';
import AgendaCategories from './categories/Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/agenda'),
    name: 'agenda_dashboard_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: AgendaDashboard,
  },
  {
    path: frontendURL('accounts/:accountId/agenda/categories'),
    name: 'agenda_categories_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: AgendaCategories,
  },
  {
    path: frontendURL('accounts/:accountId/agenda/settings'),
    name: 'agenda_settings_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: AgendaSettings,
  },
  {
    path: frontendURL('accounts/:accountId/agenda/custom_attributes'),
    name: 'agenda_custom_attributes_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: AgendaCustomAttributes,
  },
];
