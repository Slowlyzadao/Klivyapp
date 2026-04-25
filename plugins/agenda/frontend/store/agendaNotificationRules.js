import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from 'dashboard/store/mutation-types';
import NotifRulesAPI from '@plugins/agenda/frontend/api/agendaNotificationRules';

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
  allRules(_state) {
    return _state.records;
  },
  enabledRules(_state) {
    return _state.records.filter(r => r.enabled);
  },
  reminderRules(_state) {
    return _state.records.filter(
      r => r.rule_type === 'reminder' && r.trigger_offset_hours != null
    );
  },
  getRuleById: _state => id => {
    return _state.records.find(r => r.id === id);
  },
};

export const actions = {
  // Busca todas as regras da conta
  fetch: async function fetchRules({ commit }) {
    commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isFetching: true });
    try {
      const response = await NotifRulesAPI.get();
      commit(types.SET_AGENDA_NOTIF_RULES, response.data);
    } catch (error) {
      // Ignore silently
    } finally {
      commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isFetching: false });
    }
  },

  // Cria uma nova regra
  create: async function createRule({ commit }, ruleData) {
    commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isCreating: true });
    try {
      const response = await NotifRulesAPI.create({
        agenda_notification_rule: ruleData,
      });
      commit(types.ADD_AGENDA_NOTIF_RULE, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isCreating: false });
    }
  },

  // Atualiza uma regra existente
  update: async ({ commit }, { id, ...updateData }) => {
    commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isUpdating: true });
    try {
      const response = await NotifRulesAPI.update(id, {
        agenda_notification_rule: updateData,
      });
      commit(types.EDIT_AGENDA_NOTIF_RULE, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isUpdating: false });
    }
  },

  // Remove uma regra
  delete: async ({ commit }, id) => {
    commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isDeleting: true });
    try {
      await NotifRulesAPI.delete(id);
      commit(types.DELETE_AGENDA_NOTIF_RULE, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_NOTIF_RULE_UI_FLAG, { isDeleting: false });
    }
  },

  // Toggle enabled/disabled
  toggle: async ({ commit }, id) => {
    try {
      const response = await NotifRulesAPI.toggle(id);
      commit(types.EDIT_AGENDA_NOTIF_RULE, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    }
  },
};

export const mutations = {
  [types.SET_AGENDA_NOTIF_RULE_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_AGENDA_NOTIF_RULE]: MutationHelpers.create,
  [types.SET_AGENDA_NOTIF_RULES]: MutationHelpers.set,
  [types.EDIT_AGENDA_NOTIF_RULE]: MutationHelpers.update,
  [types.DELETE_AGENDA_NOTIF_RULE]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
