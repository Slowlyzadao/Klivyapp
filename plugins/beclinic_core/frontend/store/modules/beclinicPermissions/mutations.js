// store/modules/beclinicPermissions/mutations.js
import {
  SET_PERMISSIONS,
  SET_PERMISSIONS_LOADING,
  CLEAR_PERMISSIONS,
} from './types';

export const mutations = {
  [SET_PERMISSIONS](state, { permissions }) {
    state.permissions = permissions;
    state.loaded = true;
  },
  [SET_PERMISSIONS_LOADING](state, isLoading) {
    state.isLoading = isLoading;
  },
  [CLEAR_PERMISSIONS](state) {
    state.permissions = {};
    state.loaded = false;
  },
};
