// Rotas do painel admin do Portal do Paciente (Sprint G).
// Acessível em /app/accounts/:accountId/settings/patient-portal.
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

const meta = { permissions: ['administrator'] };

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/patient-portal'),
      component: SettingsWrapper,
      props: {},
      children: [
        {
          path: '',
          name: 'patient_portal_settings_wrapper',
          meta,
          redirect: to => ({ name: 'patient_portal_settings_index', params: to.params }),
        },
        {
          path: 'general',
          name: 'patient_portal_settings_index',
          meta,
          component: Index,
        },
      ],
    },
  ],
};
