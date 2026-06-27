// Estado efêmero de "X está digitando" por sala. Não persiste — o handler
// do ActionCable atualiza o store, e timers de 5s removem entradas paradas.

const SET_TYPING = 'internalChatTyping/SET_TYPING';
const RESET = 'internalChatTyping/RESET';

const initialState = () => ({
  byRoom: {}, // { [roomId]: { [userId]: { name, expiresAt } } }
});

export const state = initialState();

export const getters = {
  getTypersForRoom: _state => roomId => {
    const map = _state.byRoom[roomId] || {};
    const now = Date.now();
    return Object.values(map).filter(t => t.expiresAt > now);
  },
};

const TIMERS = new Map();

export const actions = {
  receive: ({ commit, state: s }, { room_id, user_id, user_name, active }) => {
    if (!room_id || !user_id) return;
    const key = `${room_id}:${user_id}`;
    if (TIMERS.has(key)) {
      clearTimeout(TIMERS.get(key));
      TIMERS.delete(key);
    }
    if (active) {
      const expiresAt = Date.now() + 5000;
      const next = { ...(s.byRoom[room_id] || {}) };
      next[user_id] = { user_id, name: user_name, expiresAt };
      commit(SET_TYPING, { room_id, map: next });
      const tid = setTimeout(() => {
        const cur = { ...(s.byRoom[room_id] || {}) };
        delete cur[user_id];
        commit(SET_TYPING, { room_id, map: cur });
        TIMERS.delete(key);
      }, 5200);
      TIMERS.set(key, tid);
    } else {
      const cur = { ...(s.byRoom[room_id] || {}) };
      delete cur[user_id];
      commit(SET_TYPING, { room_id, map: cur });
    }
  },
  // MT-15 — limpa TIMERS module-scope + state. Sem isso, o setTimeout fica
  // pendente mesmo após o user sair da conta; quando dispara, tenta commit
  // num state que já não pertence à conta corrente. Cobre o memory leak
  // identificado na auditoria.
  reset: ({ commit }) => {
    TIMERS.forEach(tid => clearTimeout(tid));
    TIMERS.clear();
    commit(RESET);
  },
};

export const mutations = {
  [SET_TYPING](_state, { room_id, map }) {
    _state.byRoom = { ..._state.byRoom, [room_id]: map };
  },
  [RESET](_state) {
    Object.assign(_state, initialState());
  },
};

export default { namespaced: true, state, getters, actions, mutations };
