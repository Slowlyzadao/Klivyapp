import { frontendURL } from 'dashboard/helper/URLHelper';
import HelpIndex from '../features/help/HelpIndex.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ajuda'),
    name: 'ajuda_dashboard_index',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: HelpIndex,
  },
];
