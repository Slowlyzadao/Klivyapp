import { frontendURL } from 'dashboard/helper/URLHelper';
import SettingsWrapper from 'dashboard/routes/dashboard/settings/SettingsWrapper.vue';
import RolesListIndex from '../features/roles-list/RolesListIndex.vue';
import RoleEditorIndex from '../features/role-editor/RoleEditorIndex.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/custom-roles'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          redirect: to => ({ name: 'klivy_roles_list', params: to.params }),
        },
        {
          path: 'list',
          name: 'klivy_roles_list',
          meta: { permissions: ['administrator'] },
          component: RolesListIndex,
        },
        {
          path: 'new',
          name: 'klivy_roles_new',
          meta: { permissions: ['administrator'] },
          component: RoleEditorIndex,
        },
        {
          path: ':roleId/edit',
          name: 'klivy_roles_edit',
          meta: { permissions: ['administrator'] },
          component: RoleEditorIndex,
        },
      ],
    },
  ],
};
