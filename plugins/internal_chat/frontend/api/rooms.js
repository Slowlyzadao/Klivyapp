/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatRoomsAPI extends ApiClient {
  constructor() {
    super('internal_chat/rooms', { accountScoped: true });
  }

  unreadSummary() {
    return axios.get(`${this.url}/unread_summary`);
  }

  archive(roomId) {
    return axios.patch(`${this.url}/${roomId}/archive`);
  }

  unarchive(roomId) {
    return axios.patch(`${this.url}/${roomId}/unarchive`);
  }

  mute(roomId, until_ = null) {
    return axios.patch(`${this.url}/${roomId}/mute`, { mute_until: until_ });
  }

  unmute(roomId) {
    return axios.delete(`${this.url}/${roomId}/mute`);
  }

  updateAvatar(roomId, file) {
    const form = new FormData();
    form.append('avatar', file);
    return axios.patch(`${this.url}/${roomId}/avatar`, form, {
      headers: { 'Content-Type': 'multipart/form-data' },
    });
  }

  removeAvatar(roomId) {
    return axios.delete(`${this.url}/${roomId}/avatar`);
  }
}

export default new InternalChatRoomsAPI();
