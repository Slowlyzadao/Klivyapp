// store/modules/beclinicPermissions/index.js
import { actions } from './actions';
import { getters } from './getters';
import { mutations } from './mutations';

const state = {
  beclinicRole: null, // 'dono' | 'gerente' | 'especialista' | 'super_admin'
  permissions: {}, // hash completo de permissões por módulo
  team: null, // dados do time/perfil do usuário
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
