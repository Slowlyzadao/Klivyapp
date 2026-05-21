/* global axios */
import ApiClient from './ApiClient';

class FormTemplatesAPI extends ApiClient {
  constructor() {
    // Note: Form Templates are likely global/account scoped, not specific to patients
    super('form_templates', { accountScoped: true });
  }

  get(params = {}) {
    return axios.get(this.url, { params });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new FormTemplatesAPI();
