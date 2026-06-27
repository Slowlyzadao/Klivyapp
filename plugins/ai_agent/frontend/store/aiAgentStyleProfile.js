import AiAgentStyleProfile from '@plugins/ai_agent/frontend/api/styleProfile';
import { throwErrorMessage } from 'dashboard/store/utils/api';

// Status do RASCUNHO em que a geração ainda está rodando — controla o polling
// na aba "Tom de voz" enquanto o job destila as conversas.
export const DRAFT_PROCESSING_STATUS = 'generating';

const initialState = () => ({
  active: {},
  draft: {},
  uiFlags: {
    isFetching: false,
    isGenerating: false,
    isSaving: false,
  },
});

const state = initialState();

const getters = {
  getActive: $state => $state.active,
  getDraft: $state => $state.draft,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await AiAgentStyleProfile.get();
      commit('SET_PROFILE', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  generate: async ({ commit }) => {
    commit('SET_UI_FLAG', { isGenerating: true });
    try {
      const { data } = await AiAgentStyleProfile.generate();
      commit('SET_PROFILE', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isGenerating: false });
    }
  },

  // Re-busca pro polling do status do rascunho (generating → ready | failed).
  refresh: async ({ commit }) => {
    try {
      const { data } = await AiAgentStyleProfile.get();
      commit('SET_PROFILE', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    }
  },

  // Grava os campos editados no perfil ATIVO. `approve` consome o rascunho
  // (aprovação); sem approve é só toggle/edição do ativo.
  save: async ({ commit }, { profile, approve = false }) => {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await AiAgentStyleProfile.update(profile, { approve });
      commit('SET_PROFILE', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  // MT-19 — defesa em profundidade pra account-switch.
  reset: ({ commit }) => commit('RESET'),
};

const mutations = {
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_PROFILE($state, { active, draft }) {
    $state.active = active || {};
    $state.draft = draft || {};
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
