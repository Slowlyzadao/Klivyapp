import { frontendURL } from 'dashboard/helper/URLHelper';
import PatientsIndex from './Index.vue';
import PatientsRecord from './Record.vue';

export const routes = [
  {
    path: frontendURL('accounts/:accountId/patients'),
    name: 'patients_dashboard_index',
    component: PatientsIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
  {
    path: frontendURL('accounts/:accountId/patients/:patientId/record'),
    name: 'patients_dashboard_record',
    component: PatientsRecord,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
