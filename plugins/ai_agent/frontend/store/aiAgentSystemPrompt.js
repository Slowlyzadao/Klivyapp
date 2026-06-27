import AiAgentSystemPrompt from '@plugins/ai_agent/frontend/api/systemPrompt';
import { throwErrorMessage } from 'dashboard/store/utils/api';

const initialState = () => ({
  // Texto PRÓPRIO da conta (vazio = herda o default).
  content: '',
  // Default global do super admin — fonte do botão "Restaurar padrão".
  default: '',
  // true quando a conta ainda não tem o seu e usa o default em runtime.
  usingDefault: true,
  uiFlags: {
    isFetching: false,
    isSaving: false,
  },
});

const state = initialState();

const getters = {
  getContent: $state => $state.content,
  getDefault: $state => $state.default,
  getUsingDefault: $state => $state.usingDefault,
  getUIFlags: $state => $state.uiFlags,
};

const actions = {
  fetch: async ({ commit }) => {
    commit('SET_UI_FLAG', { isFetching: true });
    try {
      const { data } = await AiAgentSystemPrompt.get();
      commit('SET_DATA', data);
      return data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  save: async ({ commit }, content) => {
    commit('SET_UI_FLAG', { isSaving: true });
    try {
      const { data } = await AiAgentSystemPrompt.update(content);
      commit('SET_DATA', data);
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
  SET_DATA(
    $state,
    { content, default: defaultPrompt, using_default: usingDefault }
  ) {
    $state.content = content || '';
    $state.default = defaultPrompt || '';
    $state.usingDefault = usingDefault ?? true;
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
