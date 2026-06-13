import AiAgentFollowUpRules from '@plugins/ai_agent/frontend/api/followUpRules';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const initialState = () => ({
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
});

const state = initialState();

const getters = {
  getRecords: $state => $state.records,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const response = await AiAgentFollowUpRules.get();
      commit('SET_RECORDS', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await AiAgentFollowUpRules.create(payload);
      commit('ADD_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...payload }) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const response = await AiAgentFollowUpRules.update(id, payload);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },

  delete: async ({ commit }, id) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentFollowUpRules.delete(id);
      commit('REMOVE_RECORD', id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  // MT-19 — defesa em profundidade pra account-switch. Hoje o
  // SidebarAccountSwitcher faz full reload (zera tudo via browser); se
  // mudar pra SPA navigation no futuro, esse reset garante que regras
  // de uma clínica não vazem visualmente pra outra.
  reset: ({ commit }) => commit('RESET'),
};

const mutations = {
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_RECORDS($state, records) {
    $state.records = records;
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
  RESET($state) {
    Object.assign($state, initialState());
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
