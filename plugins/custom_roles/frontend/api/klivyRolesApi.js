/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

/**
 * API client das Funções (Custom Roles) do Klivy.
 * Roles são atribuídas direto ao AccountUser via klivy_role_id.
 */
class KlivyRolesAPI extends ApiClient {
  constructor() {
    super('klivy_roles', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(payload) {
    return axios.post(this.url, { klivy_role: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { klivy_role: payload });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  assignToUser(roleId, userId) {
    return axios.post(`${this.url}/${roleId}/assign`, { user_id: userId });
  }
}

export default new KlivyRolesAPI();
