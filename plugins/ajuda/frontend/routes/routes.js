import { frontendURL } from 'dashboard/helper/URLHelper';
import HelpIndex from '../features/help/HelpIndex.vue';
import HelpReportBug from '../features/help/HelpReportBug.vue';
import HelpFeatureRequest from '../features/help/HelpFeatureRequest.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/ajuda'),
    name: 'ajuda_dashboard_index',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: HelpIndex,
  },
  {
    path: frontendURL('accounts/:accountId/ajuda/reportar-erro'),
    name: 'ajuda_report_bug',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: HelpReportBug,
  },
  {
    path: frontendURL('accounts/:accountId/ajuda/solicitar-melhoria'),
    name: 'ajuda_feature_request',
    meta: {
      permissions: ['administrator', 'agent'],
    },
    component: HelpFeatureRequest,
  },
];
