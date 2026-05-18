import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES, CONVERSATION_PERMISSIONS } from 'dashboard/constants/permissions.js';
import FollowUpsIndex from './followUps/Index.vue';
import InternalNotificationTemplatesIndex from './internalNotificationTemplates/Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai_agent/follow_ups'),
    name: 'ai_agent_follow_ups_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: FollowUpsIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ai_agent/templates'),
    name: 'ai_agent_internal_notification_templates_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: InternalNotificationTemplatesIndex,
  },
];
