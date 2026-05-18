import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from 'dashboard/routes/dashboard/settings/SettingsWrapper.vue';
import BeClinicRolesIndex from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/roles'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => ({ name: 'beclinic_roles_list', params: to.params }),
        },
        {
          path: 'list',
          name: 'beclinic_roles_list',
          meta: {
            permissions: ['administrator'],
          },
          component: BeClinicRolesIndex,
        },
      ],
    },
  ],
};
