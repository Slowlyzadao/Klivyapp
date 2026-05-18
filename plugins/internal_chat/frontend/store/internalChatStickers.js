import StickersAPI from '@plugins/internal_chat/frontend/api/stickers';

const SET_LIST = 'internalChatStickers/SET_LIST';
const SET_RECENT = 'internalChatStickers/SET_RECENT';
const UPSERT = 'internalChatStickers/UPSERT';
const REMOVE = 'internalChatStickers/REMOVE';
const SET_FAVORITE = 'internalChatStickers/SET_FAVORITE';
const SET_FLAG = 'internalChatStickers/SET_FLAG';

export const state = {
  records: [], // todos os stickers visíveis pra conta (defaults + favoritados)
  recent: [],  // top 10 do user por frequência de envio (já ordenados)
  loaded: false,
  uiFlags: {
    isFetching: false,
    isUploading: false,
  },
};

export const getters = {
  getAll: _state => _state.records,
  getRecent: _state => _state.recent,
  getById: _state => id => {
    const idn = Number(id);
    return (
      _state.records.find(s => Number(s.id) === idn) ||
      _state.recent.find(s => Number(s.id) === idn)
    );
  },
  getFavorites: _state => _state.records.filter(s => s.is_favorite),
  getMine: _state => _state.records.filter(s => s.is_mine),
  getUIFlags: _state => _state.uiFlags,
  isLoaded: _state => _state.loaded,
};

export const actions = {
  fetch: async ({ commit, state: s }) => {
    if (s.loaded) return;
    commit(SET_FLAG, { isFetching: true });
    try {
      const res = await StickersAPI.list('all');
      commit(SET_LIST, res.data?.data || []);
    } finally {
      commit(SET_FLAG, { isFetching: false });
    }
  },

  refresh: async ({ commit }) => {
    const [all, recent] = await Promise.all([
      StickersAPI.list('all'),
      StickersAPI.list('recent'),
    ]);
    commit(SET_LIST, all.data?.data || []);
    commit(SET_RECENT, recent.data?.data || []);
  },

  fetchRecent: async ({ commit }) => {
    const res = await StickersAPI.list('recent');
    commit(SET_RECENT, res.data?.data || []);
  },

  upload: async ({ commit }, payload) => {
    commit(SET_FLAG, { isUploading: true });
    try {
      const res = await StickersAPI.upload(payload);
      commit(UPSERT, res.data.data);
      return res.data.data;
    } finally {
      commit(SET_FLAG, { isUploading: false });
    }
  },

  remove: async ({ commit }, id) => {
    await StickersAPI.delete(id);
    commit(REMOVE, id);
  },

  // Toggle dentro da coleção: se já tá salvo, remove (cascade-delete possível);
  // se não tá, adiciona à coleção.
  toggleFavorite: async ({ commit, state: s, dispatch }, id) => {
    const sticker = s.records.find(r => r.id === id);
    if (sticker) {
      // Já está na coleção → desfavoritar (backend pode cascade-delete).
      const res = await StickersAPI.unfavorite(id);
      commit(REMOVE, id);
      return res.data?.data;
    }
    // Sticker não está na coleção (recebido via mensagem) → favoritar e
    // recarregar a lista pra trazer o objeto completo.
    await StickersAPI.favorite(id);
    await dispatch('refresh');
    return { sticker_id: id, is_favorite: true };
  },

  // Atalho usado pelo MessageBubble: favorita um sticker recebido via mensagem
  // (sem ter no store) e refetch pra cachear.
  favoriteAndCacheById: async ({ dispatch }, id) => {
    await StickersAPI.favorite(id);
    await dispatch('refresh');
  },
};

export const mutations = {
  [SET_LIST](_state, list) {
    _state.records = list;
    _state.loaded = true;
  },
  [SET_RECENT](_state, list) {
    _state.recent = list;
  },
  [UPSERT](_state, sticker) {
    if (!sticker) return;
    const idx = _state.records.findIndex(s => Number(s.id) === Number(sticker.id));
    if (idx >= 0) _state.records.splice(idx, 1, { ..._state.records[idx], ...sticker });
    else _state.records.unshift(sticker);
  },
  [REMOVE](_state, id) {
    _state.records = _state.records.filter(s => Number(s.id) !== Number(id));
  },
  [SET_FAVORITE](_state, { id, value }) {
    const idx = _state.records.findIndex(s => Number(s.id) === Number(id));
    if (idx >= 0) {
      _state.records.splice(idx, 1, { ..._state.records[idx], is_favorite: value });
    }
  },
  [SET_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
