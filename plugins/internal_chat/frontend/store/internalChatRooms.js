import RoomsAPI from '@plugins/internal_chat/frontend/api/rooms';
import MembershipsAPI from '@plugins/internal_chat/frontend/api/memberships';

const SET_ROOMS = 'internalChatRooms/SET_ROOMS';
const SET_ARCHIVED = 'internalChatRooms/SET_ARCHIVED';
const REMOVE_ARCHIVED = 'internalChatRooms/REMOVE_ARCHIVED';
const UPSERT_ROOM = 'internalChatRooms/UPSERT_ROOM';
const REMOVE_ROOM = 'internalChatRooms/REMOVE_ROOM';
const SET_UI_FLAG = 'internalChatRooms/SET_UI_FLAG';
const SET_UNREAD_SUMMARY = 'internalChatRooms/SET_UNREAD_SUMMARY';
const UPDATE_MEMBER_READ = 'internalChatRooms/UPDATE_MEMBER_READ';
const RESET = 'internalChatRooms/RESET';

const initialState = () => ({
  records: [],
  // Conversas arquivadas (carregadas sob demanda na aba "Arquivadas").
  archived: [],
  unreadSummary: { byRoom: {}, total: 0 },
  uiFlags: {
    isFetching: false,
    isCreating: false,
  },
});

export const state = initialState();

export const getters = {
  getAllRooms: _state => _state.records,
  getArchivedRooms: _state => _state.archived,
  getRoomById: _state => id =>
    _state.records.find(r => Number(r.id) === Number(id)),
  getTotalUnread: _state => _state.unreadSummary.total || 0,
  getUnreadByRoom: _state => roomId =>
    _state.unreadSummary.byRoom[roomId] || 0,
  getUIFlags: _state => _state.uiFlags,
  // Maior `last_read_message_id` entre membros que NÃO sejam o usuário dado.
  // Usado para decidir ✓ vs ✓✓ em mensagens próprias.
  getMaxOthersRead: _state => (roomId, currentUserId) => {
    const room = _state.records.find(r => Number(r.id) === Number(roomId));
    if (!room?.members) return 0;
    let max = 0;
    for (const m of room.members) {
      if (m.user_id === currentUserId) continue;
      const v = m.last_read_message_id || 0;
      if (v > max) max = v;
    }
    return max;
  },
};

export const actions = {
  fetch: async ({ commit }) => {
    commit(SET_UI_FLAG, { isFetching: true });
    try {
      const res = await RoomsAPI.get();
      commit(SET_ROOMS, res.data?.data || []);
    } finally {
      commit(SET_UI_FLAG, { isFetching: false });
    }
  },
  show: async ({ commit }, id) => {
    const res = await RoomsAPI.show(id);
    commit(UPSERT_ROOM, res.data.data);
    return res.data.data;
  },
  create: async ({ commit }, payload) => {
    commit(SET_UI_FLAG, { isCreating: true });
    try {
      const res = await RoomsAPI.create({ room: payload });
      commit(UPSERT_ROOM, res.data.data);
      return res.data.data;
    } finally {
      commit(SET_UI_FLAG, { isCreating: false });
    }
  },
  upsertFromCable: ({ commit }, room) => commit(UPSERT_ROOM, room),
  applyReadReceipt: ({ commit }, payload) => commit(UPDATE_MEMBER_READ, payload),
  removeRoom: ({ commit }, id) => commit(REMOVE_ROOM, id),
  // Cable: sala foi excluída pelo dono — remove da lista local pra todos.
  handleDeletedFromCable: ({ commit }, { room_id }) => commit(REMOVE_ROOM, room_id),
  update: async ({ commit }, { id, ...payload }) => {
    const res = await RoomsAPI.update(id, { room: payload });
    commit(UPSERT_ROOM, res.data.data);
    return res.data.data;
  },
  updateAvatar: async ({ commit }, { roomId, file }) => {
    const res = await RoomsAPI.updateAvatar(roomId, file);
    commit(UPSERT_ROOM, res.data.data);
    return res.data.data;
  },
  removeAvatar: async ({ commit }, roomId) => {
    const res = await RoomsAPI.removeAvatar(roomId);
    commit(UPSERT_ROOM, res.data.data);
    return res.data.data;
  },
  destroy: async ({ commit }, roomId) => {
    await RoomsAPI.delete(roomId);
    commit(REMOVE_ROOM, roomId);
  },
  addMember: async ({ dispatch }, { roomId, userId, role = 'member' }) => {
    await MembershipsAPI.add(roomId, { userId, role });
    return dispatch('show', roomId);
  },
  addBeaMember: async ({ dispatch }, { roomId }) => {
    await MembershipsAPI.addBea(roomId);
    return dispatch('show', roomId);
  },
  removeMember: async ({ dispatch }, { roomId, membershipId }) => {
    await MembershipsAPI.remove(roomId, membershipId);
    return dispatch('show', roomId);
  },
  leaveRoom: async ({ dispatch, commit }, { roomId, membershipId }) => {
    await MembershipsAPI.remove(roomId, membershipId);
    commit(REMOVE_ROOM, roomId);
    return dispatch('fetch');
  },
  changeMemberRole: async ({ dispatch }, { roomId, membershipId, role }) => {
    await MembershipsAPI.changeRole(roomId, membershipId, role);
    return dispatch('show', roomId);
  },
  fetchArchived: async ({ commit }) => {
    const res = await RoomsAPI.listArchived();
    commit(SET_ARCHIVED, res.data?.data || []);
  },
  archive: async ({ commit }, roomId) => {
    const res = await RoomsAPI.archive(roomId);
    // Per-membership: some só da MINHA lista (o outro participante mantém).
    commit(REMOVE_ROOM, roomId);
    return res.data.data;
  },
  unarchive: async ({ commit }, roomId) => {
    const res = await RoomsAPI.unarchive(roomId);
    commit(REMOVE_ARCHIVED, roomId);
    commit(UPSERT_ROOM, res.data.data);
    return res.data.data;
  },
  mute: async ({ commit }, { roomId, until: until_ = null }) => {
    const res = await RoomsAPI.mute(roomId, until_);
    commit(UPSERT_ROOM, { id: roomId, muted_until: res.data.data.muted_until });
    return res.data.data;
  },
  unmute: async ({ commit }, roomId) => {
    await RoomsAPI.unmute(roomId);
    commit(UPSERT_ROOM, { id: roomId, muted_until: null });
  },
  fetchUnreadSummary: async ({ commit }) => {
    const res = await RoomsAPI.unreadSummary();
    commit(SET_UNREAD_SUMMARY, res.data);
  },
  applyIncomingMessage: ({ commit, state: s }, { roomId, message }) => {
    const room = s.records.find(r => Number(r.id) === Number(roomId));
    if (!room) return;
    commit(UPSERT_ROOM, {
      id: roomId,
      last_message: message,
      last_message_at: message.created_at,
    });
  },
  bumpUnread: ({ commit, state: s }, roomId) => {
    const next = { ...s.unreadSummary.byRoom };
    next[roomId] = (next[roomId] || 0) + 1;
    commit(SET_UNREAD_SUMMARY, {
      data: next,
      total: Object.values(next).reduce((a, b) => a + b, 0),
    });
  },
  clearUnread: ({ commit, state: s }, roomId) => {
    const next = { ...s.unreadSummary.byRoom };
    delete next[roomId];
    commit(SET_UNREAD_SUMMARY, {
      data: next,
      total: Object.values(next).reduce((a, b) => a + b, 0),
    });
  },
  // MT-14/MT-19 — zera state ao trocar de conta. Defesa em profundidade: hoje
  // o SidebarAccountSwitcher faz full reload (zera tudo via browser), mas
  // se um dia migrar pra SPA navigation, este reset é o que garante que
  // dados de uma clínica não vazam pra outra.
  reset: ({ commit }) => commit(RESET),
};

export const mutations = {
  [SET_ROOMS](_state, rooms) {
    _state.records = rooms;
  },
  [SET_ARCHIVED](_state, rooms) {
    _state.archived = rooms;
  },
  [REMOVE_ARCHIVED](_state, id) {
    _state.archived = _state.archived.filter(r => Number(r.id) !== Number(id));
  },
  [UPSERT_ROOM](_state, room) {
    if (!room) return;
    const idx = _state.records.findIndex(r => Number(r.id) === Number(room.id));
    const next = _state.records.slice();
    if (idx >= 0) {
      next[idx] = { ...next[idx], ...room };
    } else {
      next.unshift(room);
    }
    // reordena por last_message_at desc
    next.sort((a, b) => {
      const ta = new Date(a.last_message_at || a.created_at).getTime();
      const tb = new Date(b.last_message_at || b.created_at).getTime();
      return tb - ta;
    });
    // Reatribui nova referência: força o RecycleScroller (lista virtualizada)
    // a re-renderizar os cards mesmo em mudança de dado SEM reordenação — ex.:
    // troca de avatar do grupo, que não altera last_message_at. Com splice
    // in-place o card só atualizava quando mudava de posição (nova mensagem).
    _state.records = next;
  },
  [REMOVE_ROOM](_state, id) {
    _state.records = _state.records.filter(r => Number(r.id) !== Number(id));
  },
  [SET_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [SET_UNREAD_SUMMARY](_state, payload) {
    _state.unreadSummary = {
      byRoom: payload.data || {},
      total: payload.total || 0,
    };
  },
  [UPDATE_MEMBER_READ](_state, { room_id, user_id, last_read_message_id }) {
    const idx = _state.records.findIndex(r => Number(r.id) === Number(room_id));
    if (idx < 0) return;
    const room = _state.records[idx];
    const members = (room.members || []).map(m => {
      if (m.user_id !== user_id) return m;
      if ((m.last_read_message_id || 0) >= last_read_message_id) return m;
      return { ...m, last_read_message_id };
    });
    _state.records.splice(idx, 1, { ...room, members });
  },
  [RESET](_state) {
    Object.assign(_state, initialState());
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
