/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Cliente HTTP do plugin document_templates.
// Endpoints registrados em plugins/document_templates/config/routes.rb sob
// /api/v1/accounts/:accountId/document_templates/*.
class DocumentTemplatesAPI extends ApiClient {
  constructor() {
    super('document_templates', { accountScoped: true });
  }

  list({ documentType, folderId, family, only, includeArchived } = {}) {
    return axios.get(this.url, {
      params: {
        document_type: documentType,
        folder_id: folderId,
        family,
        only,
        include_archived: includeArchived,
      },
    });
  }

  klivyLibrary({ documentType, family } = {}) {
    return axios.get(`${this.url}/klivy_library`, {
      params: { document_type: documentType, family },
    });
  }

  show(id) {
    return axios.get(`${this.url}/${id}`);
  }

  create(payload) {
    return axios.post(this.url, { document_template: payload });
  }

  update(id, payload) {
    return axios.patch(`${this.url}/${id}`, { document_template: payload });
  }

  destroy(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  duplicate(id) {
    return axios.post(`${this.url}/${id}/duplicate`);
  }

  // Clona um template Klivy global pra account atual. folderId é opcional.
  cloneToAccount(id, { folderId } = {}) {
    return axios.post(`${this.url}/${id}/clone_to_account`, {
      folder_id: folderId,
    });
  }

  archive(id) {
    return axios.post(`${this.url}/${id}/archive`);
  }

  unarchive(id) {
    return axios.post(`${this.url}/${id}/unarchive`);
  }
}

export const documentTemplatesApi = new DocumentTemplatesAPI();
