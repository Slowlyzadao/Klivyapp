/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// CRUD de pastas organizadoras de templates.
// Endpoints: /api/v1/accounts/:accountId/document_template_folders/*.
class DocumentTemplateFoldersAPI extends ApiClient {
  constructor() {
    super('document_template_folders', { accountScoped: true });
  }

  list() {
    return axios.get(this.url);
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(payload) {
    return axios.post(this.url, { document_template_folder: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { document_template_folder: payload });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }
}

export const documentTemplateFoldersApi = new DocumentTemplateFoldersAPI();
