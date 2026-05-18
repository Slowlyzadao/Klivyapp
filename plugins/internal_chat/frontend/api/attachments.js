/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatAttachmentsAPI extends ApiClient {
  constructor() {
    super('internal_chat/rooms', { accountScoped: true });
  }

  list(roomId, { type = 'media' } = {}) {
    return axios.get(`${this.url}/${roomId}/attachments`, {
      params: { type },
    });
  }
}

export default new InternalChatAttachmentsAPI();
