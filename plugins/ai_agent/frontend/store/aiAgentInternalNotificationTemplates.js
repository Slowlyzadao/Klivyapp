import AiAgentInternalNotificationTemplates from '@plugins/ai_agent/frontend/api/internalNotificationTemplates';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const state = {
  records: [],
  catalog: { events: [], rooms: [], users: [] },
  uiFlags: {
    isFetching: false,
    isFetchingCatalog: false,
    isUpdating: false,
    isCreating: false,
    isDeleting: false,
    isResetting: false,
  },
};

const getters = {
  getRecords: $state => $state.records,
  getCatalog: $state => $state.catalog,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await AiAgentInternalNotificationTemplates.get();
      commit('SET_RECORDS', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  fetchCatalog: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetchingCatalog: true });
    try {
      const response = await AiAgentInternalNotificationTemplates.catalog();
      commit('SET_CATALOG', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetchingCatalog: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const response = await AiAgentInternalNotificationTemplates.update(id, payload);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await AiAgentInternalNotificationTemplates.create(payload);
      commit('ADD_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentInternalNotificationTemplates.delete(id);
      commit('REMOVE_RECORD', id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  reset: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { isResetting: true });
    try {
      const response = await AiAgentInternalNotificationTemplates.reset(id);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isResetting: false });
    }
  },
};

const mutations = {
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_RECORDS($state, records) {
    $state.records = records;
  },
  SET_CATALOG($state, catalog) {
    $state.catalog = catalog;
  },
  ADD_RECORD($state, record) {
    $state.records.push(record);
  },
  REPLACE_RECORD($state, record) {
    const idx = $state.records.findIndex(r => r.id === record.id);
    if (idx !== -1) $state.records.splice(idx, 1, record);
  },
  REMOVE_RECORD($state, id) {
    $state.records = $state.records.filter(r => r.id !== id);
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
