import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from 'dashboard/store/mutation-types';
import AgendaEventsAPI from '@plugins/agenda/frontend/api/agendaEvents';

// Plugin-scoped mutation types. Mantém as constantes do Year View locais
// para não inflar `dashboard/store/mutation-types` (Chatwoot core) com
// chaves específicas da agenda.
const SET_AGENDA_YEAR_STATS = 'agendaEvents/SET_AGENDA_YEAR_STATS';
const CLEAR_AGENDA_YEAR_STATS = 'agendaEvents/CLEAR_AGENDA_YEAR_STATS';

export const state = {
  records: [],
  // Year View cache: `{ [year]: { byDay: { 'YYYY-MM-DD': {...counts} } } }`.
  // Mantido fora de `records` porque é payload agregado (não evento cru),
  // e a Year View nunca lê `records` — assim trocar de view não invalida
  // o cache anual. Frozen no UPSERT pra evitar mutação acidental.
  yearStats: {},
  uiFlags: {
    isFetching: false,
    isFetchingYearStats: false,
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
  getYearStats: _state => year => {
    return _state.yearStats[year] || null;
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
  // Cache por (ano + userId). Trocar de profissional no filtro lateral
  // invalida via key mismatch. CUD em evento limpa todo o cache anual
  // (ver mutações ADD/EDIT/DELETE abaixo).
  fetchYearStats: async function fetchYearStats({ commit, state: _state }, { year, userId, force = false } = {}) {
    if (!year) return null;
    if (!force) {
      const existing = _state.yearStats[year];
      if (existing && existing.userId === (userId || null)) {
        return existing;
      }
    }
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isFetchingYearStats: true });
    try {
      const response = await AgendaEventsAPI.yearStats({ year, userId });
      const payload = {
        year,
        userId: userId || null,
        byDay: Object.freeze(response.data.by_day || {}),
        fetchedAt: Date.now(),
      };
      commit(SET_AGENDA_YEAR_STATS, payload);
      return payload;
    } catch (error) {
      // Loga no console pra diagnosticar 404/500 silenciosos — sem isso o
      // Year View aparece zerado sem nenhuma pista do que falhou.
      // eslint-disable-next-line no-console
      console.error('[Agenda] fetchYearStats failed', {
        year,
        userId,
        status: error?.response?.status,
        data: error?.response?.data,
        error,
      });
      // Marca um registro vazio pro getter retornar algo (evita re-tentativa
      // infinita por watcher) e permite UI distinguir "erro" de "carregando".
      commit(SET_AGENDA_YEAR_STATS, {
        year,
        userId: userId || null,
        byDay: Object.freeze({}),
        fetchedAt: Date.now(),
        error: error?.response?.status || 'network',
      });
      return null;
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isFetchingYearStats: false });
    }
  },
  create: async function createAgendaEvent({ commit }, eventObj) {
    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isCreating: true });
    try {
      const response = await AgendaEventsAPI.create(eventObj);
      commit(types.ADD_AGENDA_EVENT, response.data);
      // Year View pode estar mostrando dados defasados — invalida cache.
      // Próxima abertura da Year View re-fetcha (~1 request).
      commit(CLEAR_AGENDA_YEAR_STATS);
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
      commit(CLEAR_AGENDA_YEAR_STATS);
      return response.data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.SET_AGENDA_EVENT_UI_FLAG, { isUpdating: false });
    }
  },
  // Soft-delete: aceita { id, reason, note }. Backend rejeita sem reason e
  // exige note quando reason='outro'. Evento some da agenda mas permanece
  // visível no prontuário do paciente (Agenda e Histórico + Timeline).
  delete: async ({ commit }, payload) => {
    const id = typeof payload === 'object' ? payload.id : payload;
    const reason = typeof payload === 'object' ? payload.reason : null;
    const note = typeof payload === 'object' ? payload.note : null;

    commit(types.SET_AGENDA_EVENT_UI_FLAG, { isDeleting: true });
    try {
      await AgendaEventsAPI.softDelete(id, { reason, note });
      commit(types.DELETE_AGENDA_EVENT, id);
      commit(CLEAR_AGENDA_YEAR_STATS);
    } catch (error) {
      throw error;
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
  [SET_AGENDA_YEAR_STATS](_state, payload) {
    _state.yearStats = { ..._state.yearStats, [payload.year]: payload };
  },
  [CLEAR_AGENDA_YEAR_STATS](_state) {
    _state.yearStats = {};
  },
};

export default {
  namespaced: true,
  actions,
  state,
  getters,
  mutations,
};
