/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Cliente do endpoint de modelos de documento (plugin document_templates),
// consumido pelos seletores "Gerar a partir de modelo" das abas Documentos e
// Consentimentos do prontuário. A listagem já vem escopada por account +
// biblioteca Klivy global (DocumentTemplatePolicy::Scope#for_account).
class PatientDocumentTemplatesAPI extends ApiClient {
  constructor() {
    super('document_templates', { accountScoped: true });
  }

  // family: 'clinical' (aba Documentos) | 'consent' (aba Consentimentos).
  list({ family } = {}) {
    return axios.get(this.url, { params: { family } });
  }

  // Modelo completo (inclui content_json) — usado pra descobrir os campos de
  // preenchimento (input.*) do modelo no modal de geração.
  show(id) {
    return axios.get(`${this.url}/${id}`);
  }
}

export default new PatientDocumentTemplatesAPI();
