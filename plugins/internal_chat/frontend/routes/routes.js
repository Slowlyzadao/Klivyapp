import { frontendURL } from 'dashboard/helper/URLHelper';
import { ROLES, CONVERSATION_PERMISSIONS } from 'dashboard/constants/permissions.js';
import ChatShell from '../components/ChatShell.vue';
import EmptyState from '../components/EmptyState.vue';
import RoomView from '../components/RoomView.vue';
import MentionsView from '../components/MentionsView.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/internal-chat'),
    component: ChatShell,
    meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
    children: [
      {
        path: '',
        name: 'internal_chat_home',
        component: EmptyState,
        meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
      },
      {
        path: 'rooms/:roomId',
        name: 'internal_chat_room',
        component: RoomView,
        props: true,
        meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
      },
      {
        path: 'mentions',
        name: 'internal_chat_mentions',
        component: MentionsView,
        meta: { permissions: [...ROLES, ...CONVERSATION_PERMISSIONS] },
      },
    ],
  },
];
