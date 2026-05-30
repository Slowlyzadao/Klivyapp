/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Catálogo de variáveis disponíveis pra inserção nos templates.
// Endpoint: GET /api/v1/accounts/:accountId/document_templates/variables.
//
// Catálogo é read-only e estável dentro da sessão — o useVariableCatalog
// composable cacheia em memória após o primeiro fetch.
class DocumentTemplateVariablesAPI extends ApiClient {
  constructor() {
    // Usa o resource base 'document_templates' porque o endpoint
    // `variables` vive como collection action lá.
    super('document_templates', { accountScoped: true });
  }

  fetch() {
    return axios.get(`${this.url}/variables`);
  }
}

export const documentTemplateVariablesApi = new DocumentTemplateVariablesAPI();
