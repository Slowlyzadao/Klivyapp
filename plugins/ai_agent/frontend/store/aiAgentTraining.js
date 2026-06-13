import AiAgentTraining from '@plugins/ai_agent/frontend/api/training';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Estados em que o job ainda está rodando — usados pra controlar o polling
// de status na aba enquanto o pipeline processa.
export const PROCESSING_STATUSES = [
  'pending',
  'extracting',
  'transcribing',
  'extracting_faq',
];

const initialState = () => ({
  records: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isDeleting: false,
    isPublishing: false,
    isApproving: false,
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
      const response = await AiAgentTraining.get();
      commit('SET_RECORDS', response.data.payload);
      return response.data.payload;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit }, payload) => {
    commit('SET_UI_FLAG', { isCreating: true });
    try {
      const response = await AiAgentTraining.create(payload);
      commit('ADD_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isCreating: false });
    }
  },

  // Re-busca 1 registro (polling enquanto o job processa).
  refresh: async ({ commit }, id) => {
    try {
      const response = await AiAgentTraining.show(id);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  delete: async ({ commit }, { id, mode }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTraining.delete(id, mode);
      commit('REMOVE_RECORD', id);
      return id;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
  },

  // Lista todas as FAQs sugeridas pendentes (de todas as conversas) pra revisão.
  fetchPendingFaqs: async () => {
    try {
      const response = await AiAgentTraining.pendingFaqs();
      return response.data.payload;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  // Aprova em massa as FAQs selecionadas; re-busca pra refletir published_at.
  approveAll: async ({ commit, dispatch }, { ids }) => {
    commit('SET_UI_FLAG', { isApproving: true });
    try {
      await AiAgentTraining.approveAll(ids);
      await dispatch('fetch');
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isApproving: false });
    }
    return true;
  },

  // Apaga todas as conversas visíveis de uma vez; re-busca pra refletir o estado.
  deleteAll: async ({ commit, dispatch }, { mode }) => {
    commit('SET_UI_FLAG', { isDeleting: true });
    try {
      await AiAgentTraining.deleteAll(mode);
      await dispatch('fetch');
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isDeleting: false });
    }
    return true;
  },

  // Aprova as FAQs mantidas e publica no RAG da Bea.
  publish: async ({ commit }, { id, faqs }) => {
    commit('SET_UI_FLAG', { isPublishing: true });
    try {
      const response = await AiAgentTraining.publish(id, faqs);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isPublishing: false });
    }
  },

  // Define qual participante é a clínica e dispara o processamento.
  selectClinic: async ({ commit }, { id, clinicSenderName }) => {
    try {
      const response = await AiAgentTraining.selectClinic(id, clinicSenderName);
      commit('REPLACE_RECORD', response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  // MT-19 — defesa em profundidade pra account-switch: evita que uploads de
  // uma clínica vazem visualmente pra outra caso a navegação vire SPA.
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
    $state.records.unshift(record);
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
