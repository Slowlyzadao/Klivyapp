import MessagesAPI from '@plugins/internal_chat/frontend/api/messages';

const SET_MESSAGES = 'internalChatMessages/SET_MESSAGES';
const PREPEND_MESSAGES = 'internalChatMessages/PREPEND_MESSAGES';
const APPEND_MESSAGE = 'internalChatMessages/APPEND_MESSAGE';
const REPLACE_MESSAGE = 'internalChatMessages/REPLACE_MESSAGE';
const SET_UI_FLAG = 'internalChatMessages/SET_UI_FLAG';
const MARK_END_OF_HISTORY = 'internalChatMessages/MARK_END_OF_HISTORY';
const SET_PENDING_PRIVATE_REPLY = 'internalChatMessages/SET_PENDING_PRIVATE_REPLY';

export const state = {
  byRoom: {}, // { roomId: [messages...] }
  endOfHistory: {},
  uiFlags: {
    isFetching: false,
    isSending: false,
  },
  // Quando o usuário escolhe "Responder no particular" num grupo, gravamos
  // aqui o snapshot da mensagem origem + o roomId do DM. Quando o RoomView
  // monta esse DM, consome o snapshot e seta como replyTarget no composer.
  pendingPrivateReply: null,
};

export const getters = {
  getMessagesForRoom: _state => roomId => _state.byRoom[roomId] || [],
  isEndOfHistory: _state => roomId => Boolean(_state.endOfHistory[roomId]),
  getUIFlags: _state => _state.uiFlags,
};

export const actions = {
  fetch: async ({ commit }, { roomId, beforeId } = {}) => {
    commit(SET_UI_FLAG, { isFetching: true });
    try {
      const res = await MessagesAPI.list(roomId, { beforeId, limit: 30 });
      const list = res.data?.data || [];
      if (beforeId) {
        commit(PREPEND_MESSAGES, { roomId, list });
      } else {
        commit(SET_MESSAGES, { roomId, list });
      }
      if (list.length < 30) commit(MARK_END_OF_HISTORY, roomId);
    } finally {
      commit(SET_UI_FLAG, { isFetching: false });
    }
  },
  send: async ({ commit }, { roomId, content, contentAttributes, files, stickerId }) => {
    commit(SET_UI_FLAG, { isSending: true });
    try {
      const res = await MessagesAPI.send(roomId, {
        content,
        contentAttributes: contentAttributes || {},
        files: files || [],
        stickerId,
      });
      commit(APPEND_MESSAGE, { roomId, message: res.data.data });
      return res.data.data;
    } finally {
      commit(SET_UI_FLAG, { isSending: false });
    }
  },
  receiveFromCable: ({ commit, dispatch, state: s }, message) => {
    if (!message?.room_id) return;
    const list = s.byRoom[message.room_id] || [];
    const exists = list.some(m => m.id === message.id);
    if (exists) {
      commit(REPLACE_MESSAGE, { roomId: message.room_id, message });
    } else {
      commit(APPEND_MESSAGE, { roomId: message.room_id, message });
    }
    // Atualiza last_message + last_message_at do card lateral, pra preview
    // refletir a msg recém-chegada (sem isso o card mostra a msg anterior
    // até o próximo refetch).
    dispatch(
      'internalChatRooms/applyIncomingMessage',
      { roomId: message.room_id, message },
      { root: true }
    );
  },
  markRead: async (_, { roomId, messageId }) => {
    if (!roomId || !messageId) return;
    await MessagesAPI.markRead(roomId, messageId);
  },
  edit: async ({ commit }, { roomId, messageId, content }) => {
    const res = await MessagesAPI.edit(roomId, messageId, { content });
    commit(REPLACE_MESSAGE, { roomId, message: res.data.data });
    return res.data.data;
  },
  remove: async ({ commit }, { roomId, messageId }) => {
    const res = await MessagesAPI.remove(roomId, messageId);
    commit(REPLACE_MESSAGE, { roomId, message: res.data.data });
    return res.data.data;
  },
  // Toggle favorito da mensagem. Atualiza otimisticamente; se a request
  // falhar, reverte. O backend é idempotente (find_or_create), então repetir
  // não polui a tabela.
  toggleFavorite: async ({ commit, state: s }, { roomId, messageId }) => {
    const list = s.byRoom[roomId] || [];
    const current = list.find(m => m.id === messageId);
    if (!current) return;
    const next = !current.is_favorited;
    commit(REPLACE_MESSAGE, {
      roomId,
      message: { ...current, is_favorited: next },
    });
    try {
      if (next) {
        await MessagesAPI.favorite(roomId, messageId);
      } else {
        await MessagesAPI.unfavorite(roomId, messageId);
      }
    } catch (e) {
      // Reverte em caso de falha
      commit(REPLACE_MESSAGE, {
        roomId,
        message: { ...current, is_favorited: !next },
      });
      throw e;
    }
  },
  fetchFavorites: async (_, { roomId }) => {
    const res = await MessagesAPI.listFavorites(roomId);
    return res.data?.data || [];
  },
  // Prepara um "responder no particular": cria/encontra DM com o autor da
  // mensagem origem (o RoomCreator é idempotente) e armazena snapshot do quote
  // pra ser consumido quando o RoomView do DM montar.
  preparePrivateReply: async ({ commit, dispatch }, { sourceMessage }) => {
    const senderId = sourceMessage?.sender?.id;
    if (!senderId) return null;
    const room = await dispatch(
      'internalChatRooms/create',
      { kind: 'direct', member_user_ids: [senderId] },
      { root: true }
    );
    if (!room?.id) return null;

    const snapshot = buildQuoteSnapshot(sourceMessage);
    commit(SET_PENDING_PRIVATE_REPLY, { snapshot, roomId: room.id });
    return room;
  },
  consumePendingPrivateReply: ({ commit, state: s }, roomId) => {
    if (!s.pendingPrivateReply) return null;
    if (Number(s.pendingPrivateReply.roomId) !== Number(roomId)) return null;
    const data = s.pendingPrivateReply;
    commit(SET_PENDING_PRIVATE_REPLY, null);
    return data;
  },
  clearPendingPrivateReply: ({ commit }) => {
    commit(SET_PENDING_PRIVATE_REPLY, null);
  },
  // Toggle reação. WhatsApp-style: cada usuário tem no máx UMA reação por
  // mensagem; clicar no MESMO emoji que já reagi → remove; clicar em emoji
  // diferente → substitui. Otimista, com revert em falha.
  toggleReaction: async (
    { commit, state: s, rootGetters },
    { roomId, messageId, emoji }
  ) => {
    const list = s.byRoom[roomId] || [];
    const current = list.find(m => m.id === messageId);
    if (!current) return;

    const myId = rootGetters.getCurrentUserID;
    const reactions = Array.isArray(current.reactions) ? current.reactions : [];

    // Achar minha reação atual (se houver) — só uma é possível.
    const myCurrent = reactions.find(r => r.by_me);
    const isToggleOff = myCurrent && myCurrent.emoji === emoji;
    const targetEmoji = isToggleOff ? null : emoji;

    // Aplica otimista: remove minha reação antiga, adiciona/atualiza nova.
    const next = applyMyReaction(reactions, myId, myCurrent?.emoji, targetEmoji);
    commit(REPLACE_MESSAGE, {
      roomId,
      message: { ...current, reactions: next },
    });

    try {
      if (targetEmoji) {
        await MessagesAPI.react(roomId, messageId, targetEmoji);
      } else {
        await MessagesAPI.unreact(roomId, messageId);
      }
    } catch (e) {
      // Reverte
      commit(REPLACE_MESSAGE, {
        roomId,
        message: { ...current, reactions },
      });
      throw e;
    }
  },
};

// Helper puro pra aplicar transição de reação no array agregado por emoji.
// Mantém o formato { emoji, count, by_me, user_ids } que o backend devolve.
function applyMyReaction(reactions, myId, prevEmoji, nextEmoji) {
  let next = reactions.map(r => ({ ...r, user_ids: [...(r.user_ids || [])] }));

  // Remove minha reação anterior (se existia)
  if (prevEmoji) {
    next = next
      .map(r => {
        if (r.emoji !== prevEmoji) return r;
        const ids = r.user_ids.filter(id => id !== myId);
        return { ...r, user_ids: ids, count: ids.length, by_me: false };
      })
      .filter(r => r.count > 0);
  }

  // Adiciona/incrementa nova reação
  if (nextEmoji) {
    const existing = next.find(r => r.emoji === nextEmoji);
    if (existing) {
      if (!existing.user_ids.includes(myId)) existing.user_ids.push(myId);
      existing.count = existing.user_ids.length;
      existing.by_me = true;
    } else {
      next.push({
        emoji: nextEmoji,
        count: 1,
        by_me: true,
        user_ids: [myId],
      });
    }
  }

  // Ordena por count desc (mesma ordenação do backend)
  return next.sort((a, b) => b.count - a.count);
}

export const mutations = {
  [SET_MESSAGES](_state, { roomId, list }) {
    _state.byRoom = { ..._state.byRoom, [roomId]: list };
  },
  [PREPEND_MESSAGES](_state, { roomId, list }) {
    const current = _state.byRoom[roomId] || [];
    _state.byRoom = { ..._state.byRoom, [roomId]: [...list, ...current] };
  },
  [APPEND_MESSAGE](_state, { roomId, message }) {
    const current = _state.byRoom[roomId] || [];
    if (current.some(m => m.id === message.id)) return;
    _state.byRoom = { ..._state.byRoom, [roomId]: [...current, message] };
  },
  [REPLACE_MESSAGE](_state, { roomId, message }) {
    const current = _state.byRoom[roomId] || [];
    const idx = current.findIndex(m => m.id === message.id);
    if (idx === -1) return;
    const next = [...current];
    next.splice(idx, 1, message);
    _state.byRoom = { ..._state.byRoom, [roomId]: next };
  },
  [SET_UI_FLAG](_state, data) {
    _state.uiFlags = { ..._state.uiFlags, ...data };
  },
  [MARK_END_OF_HISTORY](_state, roomId) {
    _state.endOfHistory = { ..._state.endOfHistory, [roomId]: true };
  },
  [SET_PENDING_PRIVATE_REPLY](_state, value) {
    _state.pendingPrivateReply = value;
  },
};

// Constrói o snapshot do quote pra um "responder no particular". O DM destino
// não consegue resolver `in_reply_to_id` (é de outra sala), então salvamos
// preview + sender_name aqui pra renderizar a citação sem precisar buscar
// a mensagem original.
const ATTACHMENT_LABELS = {
  image: '📷 Imagem',
  audio: '🎵 Áudio',
  video: '🎬 Vídeo',
  file: '📎 Arquivo',
};

function buildQuoteSnapshot(msg) {
  let preview = '';
  if (msg.deleted_at) preview = 'Mensagem apagada';
  else if (msg.content_type === 'sticker') preview = '🎨 Figurinha';
  else if (msg.content) preview = String(msg.content).slice(0, 140);
  else if (msg.attachments?.length) {
    const att = msg.attachments[0];
    preview = ATTACHMENT_LABELS[att.file_type] || '📎 Anexo';
  }

  // Miniatura pra render como thumbnail no ReplyPreview: sticker tem image_url
  // direto; imagem usa thumb_url (pode estar vazio se variant pifou) → file_url.
  let thumbUrl = null;
  if (msg.sticker?.image_url) {
    thumbUrl = msg.sticker.image_url;
  } else if (msg.attachments?.[0]?.file_type === 'image') {
    thumbUrl = msg.attachments[0].thumb_url || msg.attachments[0].file_url;
  }

  return {
    _is_snapshot: true,
    id: msg.id,
    sender_name: msg.sender?.name || 'Usuário',
    content_preview: preview,
    content_type: msg.content_type,
    first_attachment_type: msg.attachments?.[0]?.file_type || null,
    thumb_url: thumbUrl,
    original_room_id: msg.room_id,
    deleted_at: msg.deleted_at,
  };
}

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
