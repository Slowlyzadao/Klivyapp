import AiAgentVoucherConfig from '@plugins/ai_agent/frontend/api/voucherConfig';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const initialState = () => ({
  // Modo voucher ligado? (a Bea só responde quem chegou por voucher)
  enabled: false,
  // Textos-gatilho do QR (lista que o usuário gerencia)
  triggers: [],
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
});

const state = initialState();

const getters = {
  getEnabled: $state => $state.enabled,
  getTriggers: $state => $state.triggers,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await AiAgentVoucherConfig.get();
      commit('SET_DATA', data.voucher_config);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  save: async ({ commit }, { enabled, triggers }) => {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await AiAgentVoucherConfig.update({ enabled, triggers });
      commit('SET_DATA', data.voucher_config);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isSaving: false });
    }
  },

  // MT-19 — account-switch: zera pra não vazar config entre contas.
  reset: ({ commit }) => commit('RESET'),
};

const mutations = {
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_DATA($state, config) {
    const cfg = config || {};
    $state.enabled = cfg.enabled === true;
    $state.triggers = Array.isArray(cfg.triggers) ? cfg.triggers : [];
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
