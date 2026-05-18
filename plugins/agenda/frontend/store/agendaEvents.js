import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from 'dashboard/store/mutation-types';
import AgendaEventsAPI from '@plugins/agenda/frontend/api/agendaEvents';

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
  getAgendaEvents(_state) {
    return _state.records;
  },
  getAgendaEventsByStatus: _state => status => {
    return _state.records.filter(event => event.status === status);
  },
  getAgendaEventsByUser: _state => userId => {
    return _state.records.filter(event => event.user_id === userId);
  },
  getAgendaEventsByContact: _state => contactId => {
    return _state.records.filter(event => event.contact_id === contactId);
  },
  getAgendaEventById: _state => id => {
    return _state.records.find(event => event.id === id);
  },
};

export const actions = {
  get: async function getAgendaEvents({ commit }, filters = {}) {
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isFetching: true });
    try {
      const response = await AgendaEventsAPI.get(filters);
      commit(types.SET_AGENDA_EVENTS, response.data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isFetching: false });
    }
  },
  // Carrega apenas o range visível (semana/mês/dia) e mescla por id no store.
  // Não substitui o array — assim navegar de uma semana pra outra preserva
  // eventos já carregados (cache implícito client-side) e evita perder um evento
  // sendo arrastado/editado em paralelo.
  fetchByRange: async function fetchByRange({ commit }, { startsAt, endsAt, userId } = {}) {
    if (!startsAt || !endsAt) return;
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isFetching: true });
    try {
      const response = await AgendaEventsAPI.filter({ startsAt, endsAt, userId });
      commit(types.UPSERT_AGENDA_EVENTS, response.data);
    } catch (error) {
      // Ignore error
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isFetching: false });
    }
  },
  create: async function createAgendaEvent({ commit }, eventObj) {
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isCreating: true });
    try {
      const response = await AgendaEventsAPI.create(eventObj);
      commit(types.ADD_AGENDA_EVENT, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...updateObj }) => {
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isUpdating: true });
    try {
      const response = await AgendaEventsAPI.update(id, updateObj);
      commit(types.EDIT_AGENDA_EVENT, response.data);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isDeleting: true });
    try {
      await AgendaEventsAPI.delete(id);
      commit(types.DELETE_AGENDA_EVENT, id);
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_AGENDA_EVENT_UI_FLAG](_state, data) {
    _state.uiFlags = {
      ..._state.uiFlags,
      ...data,
    };
  },

  [types.ADD_AGENDA_EVENT]: MutationHelpers.create,
  [types.SET_AGENDA_EVENTS]: MutationHelpers.set,
  [types.UPSERT_AGENDA_EVENTS](_state, items) {
    const incoming = items || [];
    const map = new Map(_state.records.map(r => [r.id, r]));
    incoming.forEach(it => map.set(it.id, it));
    _state.records = Array.from(map.values());
  },
  [types.EDIT_AGENDA_EVENT]: MutationHelpers.update,
  [types.DELETE_AGENDA_EVENT]: MutationHelpers.destroy,
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
