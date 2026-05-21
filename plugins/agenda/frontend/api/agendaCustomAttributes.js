/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

class AgendaCustomAttributesAPI extends ApiClient {
  constructor() {
    super('agenda_custom_attributes', { accountScoped: true });
  }

  getAll() {
    return axios.get(this.url);
  }

  create(data) {
    return axios.post(this.url, { agenda_custom_attribute: data });
  }

  update(id, data) {
    return axios.put(`${this.url}/${id}`, { agenda_custom_attribute: data });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  reorder(ids) {
    return axios.patch(`${this.url}/reorder`, { ids });
  }
}

export default new AgendaCustomAttributesAPI();
