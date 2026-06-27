import { frontendURL } from 'dashboard/helper/URLHelper';
import {
  ROLES,
  CONVERSATION_PERMISSIONS,
} from 'dashboard/constants/permissions.js';
import FollowUpsIndex from './followUps/Index.vue';
import InternalNotificationTemplatesIndex from './internalNotificationTemplates/Index.vue';
import TrainingIndex from './training/Index.vue';
import SystemPromptIndex from './systemPrompt/Index.vue';
import VouchersIndex from './vouchers/Index.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ai_agent/vouchers'),
    name: 'ai_agent_vouchers_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: VouchersIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ai_agent/system_prompt'),
    name: 'ai_agent_system_prompt_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: SystemPromptIndex,
  },
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
  {
    path: frontendURL('accounts/:accountId/ai_agent/training'),
    name: 'ai_agent_training_index',
    meta: {
      permissions: [...ROLES, ...CONVERSATION_PERMISSIONS],
    },
    component: TrainingIndex,
  },
];
