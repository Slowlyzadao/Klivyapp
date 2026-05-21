// store/modules/beclinicPermissions/index.js
import { actions } from './actions';
import { getters } from './getters';
import { mutations } from './mutations';

const state = {
  permissions: {}, // hash completo de permissões por módulo
  loaded: false, // true após o primeiro fetch
  isLoading: false,
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
