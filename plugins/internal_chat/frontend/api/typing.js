/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatTypingAPI extends ApiClient {
  constructor() {
    super('internal_chat/rooms', { accountScoped: true });
  }

  set(roomId, active) {
    return axios.post(`${this.url}/${roomId}/typing`, { active });
  }
}

export default new InternalChatTypingAPI();
