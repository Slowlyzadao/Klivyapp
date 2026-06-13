import StickersAPI from '@plugins/internal_chat/frontend/api/stickers';

// PERF-23 (auditoria 2026-05-18): promise in-flight do refresh é
// compartilhada entre callers concorrentes. Sem isso, reabrir o
// StickerPicker durante uma request anterior dispara 4 requests
// (2 endpoints × 2 chamadas). Padrão "promise hoisting" canônico.
let inFlightRefresh = null;

const SET_LIST = 'internalChatStickers/SET_LIST';
const SET_RECENT = 'internalChatStickers/SET_RECENT';
const SET_PENDING = 'internalChatStickers/SET_PENDING';
const UPSERT = 'internalChatStickers/UPSERT';
const REMOVE = 'internalChatStickers/REMOVE';
const SET_FAVORITE = 'internalChatStickers/SET_FAVORITE';
const SET_FLAG = 'internalChatStickers/SET_FLAG';
const RESET = 'internalChatStickers/RESET';

const initialState = () => ({
  records: [], // todos os stickers visíveis pra conta (defaults + favoritados)
  recent: [],  // top 10 do user por frequência de envio (já ordenados)
  loaded: false,
  // FE-14 (auditoria 2026-05-18): IDs de stickers com save/remove em
  // flight. Compartilhado entre TODOS os MessageBubble do mesmo sticker
  // — antes cada bubble tinha `stickerActionPending` próprio, então
  // user clicando save no bubble A e remove no bubble B (mesmo sticker)
  // disparava 2 requests concorrentes com state divergente.
  pendingStickerIds: [],
  uiFlags: {
    isFetching: false,
    isUploading: false,
  },
});

export const state = initialState();

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
  // FE-14: bubbles consultam este getter pra disable button quando
  // outra request do mesmo sticker já está em flight.
  isStickerPending: _state => id => _state.pendingStickerIds.includes(Number(id)),
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

  refresh: ({ commit }) => {
    // PERF-23: dedup de requests in-flight (ver topo do arquivo).
    if (inFlightRefresh) return inFlightRefresh;
    inFlightRefresh = (async () => {
      try {
        const [all, recent] = await Promise.all([
          StickersAPI.list('all'),
          StickersAPI.list('recent'),
        ]);
        commit(SET_LIST, all.data?.data || []);
        commit(SET_RECENT, recent.data?.data || []);
      } finally {
        inFlightRefresh = null;
      }
    })();
    return inFlightRefresh;
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
  //
  // FE-22 (auditoria 2026-05-18): stickers `kind === 'default'` são visíveis
  // automaticamente pra todo mundo da conta — não há favorito a adicionar
  // nem remover. Antes o backend retornava `is_favorite: false` ao
  // favoritar e 403 ao desfavoritar, causando UI inconsistente. Agora o
  // store detecta e faz no-op, mantendo o sticker sempre na coleção.
  toggleFavorite: async ({ commit, state: s, dispatch }, id) => {
    const sticker = s.records.find(r => r.id === id);
    if (sticker?.kind === 'default') {
      // No-op: padrões são "favoritos por construção".
      return { sticker_id: id, is_favorite: true, default: true };
    }
    // FE-14: pending compartilhado. Se outra request do mesmo sticker
    // já está em flight (clicou save em bubble A + remove em bubble B),
    // descarta silenciosamente — a primeira request vence.
    if (s.pendingStickerIds.includes(Number(id))) {
      return { sticker_id: id, is_favorite: Boolean(sticker), pending: true };
    }
    commit(SET_PENDING, { id, value: true });
    try {
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
    } finally {
      commit(SET_PENDING, { id, value: false });
    }
  },

  // Atalho usado pelo MessageBubble: favorita um sticker recebido via mensagem
  // (sem ter no store) e refetch pra cachear.
  favoriteAndCacheById: async ({ commit, state: s, dispatch }, id) => {
    // FE-14: mesma guarda de pending compartilhado.
    if (s.pendingStickerIds.includes(Number(id))) return;
    commit(SET_PENDING, { id, value: true });
    try {
      await StickersAPI.favorite(id);
      await dispatch('refresh');
    } finally {
      commit(SET_PENDING, { id, value: false });
    }
  },
  // MT-14/MT-19 — zera `loaded` flag + listas. Crítico aqui especificamente
  // porque o flag `loaded` é um gate de cache: sem reset, um account-switch
  // sem reload manteria stickers da conta anterior visíveis.
  reset: ({ commit }) => commit(RESET),
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
  // FE-14: pending shared entre bubbles do mesmo sticker.
  [SET_PENDING](_state, { id, value }) {
    const idn = Number(id);
    if (value && !_state.pendingStickerIds.includes(idn)) {
      _state.pendingStickerIds = [..._state.pendingStickerIds, idn];
    } else if (!value) {
      _state.pendingStickerIds = _state.pendingStickerIds.filter(x => x !== idn);
    }
  },
  [SET_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
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
