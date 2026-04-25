import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from 'dashboard/store/mutation-types';
import ServicesAPI from '@plugins/agenda/frontend/api/agendaServices';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getUIFlags(_state) {
    return _state.uiFlags;
  },
  allServices(_state) {
    return _state.records;
  },
  getServiceById: _state => id => {
    return _state.records.find(s => s.id === id);
  },
};

export const actions = {
  // Busca todos os serviços da conta
  fetch: async function fetchServices({ commit }) {
    commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isFetching: true });
    try {
      const response = await ServicesAPI.get();
      commit(types.SET_AGENDA_SERVICES, response.data);
    } catch (error) {
      // Ignore silently
    } finally {
      commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isFetching: false });
    }
  },

  // Cria um novo serviço
  create: async function createService({ commit }, serviceData) {
    commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isCreating: true });
    try {
      const response = await ServicesAPI.create({
        agenda_service: serviceData,
      });
      commit(types.ADD_AGENDA_SERVICE, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isCreating: false });
    }
  },

  // Atualiza um serviço existente
  update: async ({ commit }, { id, ...updateData }) => {
    commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isUpdating: true });
    try {
      const response = await ServicesAPI.update(id, {
        agenda_service: updateData,
      });
      commit(types.EDIT_AGENDA_SERVICE, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isUpdating: false });
    }
  },

  // Remove um serviço
  delete: async ({ commit }, id) => {
    commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isDeleting: true });
    try {
      await ServicesAPI.delete(id);
      commit(types.DELETE_AGENDA_SERVICE, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_SERVICE_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_AGENDA_SERVICE_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_AGENDA_SERVICE]: MutationHelpers.create,
  [types.SET_AGENDA_SERVICES]: MutationHelpers.set,
  [types.EDIT_AGENDA_SERVICE]: MutationHelpers.update,
  [types.DELETE_AGENDA_SERVICE]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
