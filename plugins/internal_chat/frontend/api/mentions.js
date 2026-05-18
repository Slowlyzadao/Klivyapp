/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatMentionsAPI extends ApiClient {
  constructor() {
    super('internal_chat/mentions', { accountScoped: true });
  }

  list({ status = 'unread', limit = 50 } = {}) {
    return axios.get(this.url, { params: { status, limit } });
  }

  markRead(messageIds = null) {
    const body = messageIds ? { message_ids: messageIds } : {};
    return axios.post(`${this.url}/mark_read`, body);
  }

  unreadCount() {
    return axios.get(`${this.url}/unread_count`);
  }
}

export default new InternalChatMentionsAPI();
