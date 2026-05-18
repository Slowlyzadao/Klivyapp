/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class InternalChatMembershipsAPI extends ApiClient {
  constructor() {
    super('internal_chat/rooms', { accountScoped: true });
  }

  list(roomId) {
    return axios.get(`${this.url}/${roomId}/memberships`);
  }

  add(roomId, { userId, role = 'member' }) {
    return axios.post(`${this.url}/${roomId}/memberships`, {
      membership: { user_id: userId, role },
    });
  }

  addBea(roomId) {
    return axios.post(`${this.url}/${roomId}/memberships`, {
      membership: { add_bea: true },
    });
  }

  changeRole(roomId, membershipId, role) {
    return axios.patch(`${this.url}/${roomId}/memberships/${membershipId}`, {
      membership: { role },
    });
  }

  remove(roomId, membershipId) {
    return axios.delete(`${this.url}/${roomId}/memberships/${membershipId}`);
  }
}

export default new InternalChatMembershipsAPI();
