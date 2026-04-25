// store/modules/beclinicPermissions/mutations.js
import {
  SET_PERMISSIONS,
  SET_PERMISSIONS_LOADING,
  CLEAR_PERMISSIONS,
} from './types';

export const mutations = {
  [SET_PERMISSIONS](state, { beclinicRole, permissions, team }) {
    state.beclinicRole = beclinicRole;
    state.permissions = permissions;
    state.team = team;
    state.loaded = true;
  },
  [SET_PERMISSIONS_LOADING](state, isLoading) {
    state.isLoading = isLoading;
  },
  [CLEAR_PERMISSIONS](state) {
    state.beclinicRole = null;
    state.permissions = {};
    state.team = null;
    state.loaded = false;
  },
};
