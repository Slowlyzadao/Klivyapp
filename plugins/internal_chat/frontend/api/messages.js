/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatMessagesAPI extends ApiClient {
  constructor() {
    super('internal_chat/rooms', { accountScoped: true });
  }

  list(roomId, { beforeId, limit = 30 } = {}) {
    const params = { limit };
    if (beforeId) params.before_id = beforeId;
    return axios.get(`${this.url}/${roomId}/messages`, { params });
  }

  send(roomId, { content, contentAttributes, files = [], stickerId } = {}) {
    if (files && files.length) {
      const fd = new FormData();
      if (content) fd.append('message[content]', content);
      if (contentAttributes) {
        fd.append(
          'message[content_attributes]',
          JSON.stringify(contentAttributes)
        );
      }
      files.forEach(f => fd.append('message[attachments][]', f));
      return axios.post(`${this.url}/${roomId}/messages`, fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
    }
    return axios.post(`${this.url}/${roomId}/messages`, {
      message: {
        content,
        content_attributes: contentAttributes || {},
        sticker_id: stickerId,
      },
    });
  }

  edit(roomId, messageId, payload) {
    return axios.patch(`${this.url}/${roomId}/messages/${messageId}`, {
      message: payload,
    });
  }

  remove(roomId, messageId) {
    return axios.delete(`${this.url}/${roomId}/messages/${messageId}`);
  }

  markRead(roomId, messageId) {
    return axios.post(`${this.url}/${roomId}/messages/mark_read`, {
      message_id: messageId,
    });
  }

  favorite(roomId, messageId) {
    return axios.post(`${this.url}/${roomId}/messages/${messageId}/favorite`);
  }

  unfavorite(roomId, messageId) {
    return axios.delete(`${this.url}/${roomId}/messages/${messageId}/favorite`);
  }

  // FE-21 (auditoria 2026-05-18): aceita params opcional pra paginação.
  // Backend retorna `meta: { page, per_page, total }`. Default mantém
  // página 1 (200 itens) — backwards-compatible.
  listFavorites(roomId, params = {}) {
    return axios.get(`${this.url}/${roomId}/messages/favorites`, { params });
  }

  react(roomId, messageId, emoji) {
    return axios.post(`${this.url}/${roomId}/messages/${messageId}/react`, {
      emoji,
    });
  }

  unreact(roomId, messageId) {
    return axios.delete(`${this.url}/${roomId}/messages/${messageId}/react`);
  }
}

export default new InternalChatMessagesAPI();
