/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// Tom de voz da Bea (projeto de estilo). Recurso singular por conta.
class AiAgentStyleProfile extends ApiClient {
  constructor() {
    super('ai_agent/style_profile', { accountScoped: true });
  }

  // Perfil ATIVO + RASCUNHO.
  get() {
    return axios.get(this.url);
  }

  // Dispara a geração (async) a partir das conversas do Treinamento.
  generate() {
    return axios.post(`${this.url}/generate`);
  }

  // Grava os campos no perfil ATIVO. `approve: true` consome o rascunho
  // (aprovação); sem approve é só edição/toggle (não toca no rascunho).
  update(styleProfile, { approve = false } = {}) {
    return axios.patch(this.url, { style_profile: styleProfile, approve });
  }
}

export default new AiAgentStyleProfile();
