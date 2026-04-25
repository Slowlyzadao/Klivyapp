// store/modules/beclinicPermissions/actions.js
import BeClinicPermissionsAPI from '../../../api/beclinicPermissions';
import {
  SET_PERMISSIONS,
  SET_PERMISSIONS_LOADING,
  CLEAR_PERMISSIONS,
} from './types';

export const actions = {
  // Fetch permissions for the current user in the current account.
  // Called once on app boot after authentication.
  fetch: async ({ commit }) => {
    commit(SET_PERMISSIONS_LOADING, true);
    try {
      const { data } = await BeClinicPermissionsAPI.fetchPermissions();
      commit(SET_PERMISSIONS, {
        beclinicRole: data.beclinic_role,
        permissions: data.permissions || {},
        team: data.team || null,
      });
    } catch {
      // On error, keep empty permissions (deny all non-admin access)
      commit(CLEAR_PERMISSIONS);
    } finally {
      commit(SET_PERMISSIONS_LOADING, false);
    }
  },

  // Clear permissions on logout
  clear: ({ commit }) => {
    commit(CLEAR_PERMISSIONS);
  },
};
