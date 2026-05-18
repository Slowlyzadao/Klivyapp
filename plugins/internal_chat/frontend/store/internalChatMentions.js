import MentionsAPI from '@plugins/internal_chat/frontend/api/mentions';

const SET_MENTIONS = 'internalChatMentions/SET_MENTIONS';
const PREPEND_MENTION = 'internalChatMentions/PREPEND_MENTION';
const SET_UNREAD_COUNT = 'internalChatMentions/SET_UNREAD_COUNT';
const SET_UI_FLAG = 'internalChatMentions/SET_UI_FLAG';

export const state = {
  records: [],
  unreadCount: 0,
  uiFlags: { isFetching: false },
};

export const getters = {
  getAll: _state => _state.records,
  getUnreadCount: _state => _state.unreadCount,
  hasUnreadMentions: _state => _state.unreadCount > 0,
  getUIFlags: _state => _state.uiFlags,
  // Conta menções não lidas por sala — usado pra @ ao lado do badge na
  // RoomList. Se a lista de records ainda não foi fetchada, retorna 0.
  getUnreadCountByRoom: _state => roomId =>
    _state.records.filter(
      m => Number(m.room_id) === Number(roomId) && !m.read_at
    ).length,
};

export const actions = {
  fetch: async ({ commit }, params = {}) => {
    commit(SET_UI_FLAG, { isFetching: true });
    try {
      const res = await MentionsAPI.list(params);
      commit(SET_MENTIONS, res.data?.data || []);
    } finally {
      commit(SET_UI_FLAG, { isFetching: false });
    }
  },
  fetchUnreadCount: async ({ commit }) => {
    const res = await MentionsAPI.unreadCount();
    commit(SET_UNREAD_COUNT, res.data?.count || 0);
  },
  markRead: async ({ commit, state: s }, messageIds = null) => {
    await MentionsAPI.markRead(messageIds);
    if (messageIds) {
      const ids = new Set(messageIds);
      const records = s.records.map(m =>
        ids.has(m.message_id) ? { ...m, read_at: new Date().toISOString() } : m
      );
      commit(SET_MENTIONS, records);
      const remaining = records.filter(m => !m.read_at).length;
      commit(SET_UNREAD_COUNT, remaining);
    } else {
      commit(SET_MENTIONS, s.records.map(m => ({ ...m, read_at: m.read_at || new Date().toISOString() })));
      commit(SET_UNREAD_COUNT, 0);
    }
  },
  receiveFromCable: ({ commit, state: s }, payload) => {
    if (!payload?.message_id) return;
    const record = {
      id: `cable-${payload.message_id}`,
      message_id: payload.message_id,
      room_id: payload.room_id,
      sender: payload.sender,
      content_preview: payload.content_preview || '',
      created_at: payload.mentioned_at,
      read_at: null,
    };
    commit(PREPEND_MENTION, record);
    commit(SET_UNREAD_COUNT, s.unreadCount + 1);
  },
};

export const mutations = {
  [SET_MENTIONS](_state, list) {
    _state.records = list;
  },
  [PREPEND_MENTION](_state, mention) {
    _state.records = [mention, ..._state.records];
  },
  [SET_UNREAD_COUNT](_state, n) {
    _state.unreadCount = n;
  },
  [SET_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
};

export default { namespaced: true, state, getters, actions, mutations };
