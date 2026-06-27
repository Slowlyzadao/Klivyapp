import AiAgentTrainingFaqs from '@plugins/ai_agent/frontend/api/trainingFaqs';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const initialState = () => ({
  records: [],
  uiFlags: {
    isFetching: false,
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
      const response = await AiAgentTrainingFaqs.get();
      commit('SET_RECORDS', response.data.payload);
      return response.data.payload;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  // Edita pergunta/resposta/categoria; não muda índices, então só substitui local.
  update: async ({ commit }, { id, faq }) => {
    commit('SET_UI_FLAG', { isUpdating: true });
    try {
      const response = await AiAgentTrainingFaqs.update(id, faq);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isUpdating: false });
    }
  },

  // Apagar reindexa as FAQs seguintes da mesma conversa, então re-busca a lista.
  delete: async ({ commit, dispatch }, id) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTrainingFaqs.delete(id);
      await dispatch('fetch');
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  // Apaga várias FAQs de uma vez (ids vazio = todas); re-busca a lista depois,
  // pois apagar reindexa as FAQs seguintes de cada conversa.
  deleteMany: async ({ commit, dispatch }, ids) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTrainingFaqs.deleteMany(ids);
      await dispatch('fetch');
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
    return true;
  },

  reset: ({ commit }) => commit('RESET'),
};

const mutations = {
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_RECORDS($state, records) {
    $state.records = records;
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
