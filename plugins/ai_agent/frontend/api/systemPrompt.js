/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// System message (system prompt) da Bea POR CONTA. Recurso singular por conta.
class AiAgentSystemPrompt extends ApiClient {
  constructor() {
    super('ai_agent/system_prompt', { accountScoped: true });
  }

  // Texto da conta + default do super admin (+ using_default).
  get() {
    return axios.get(this.url);
  }

  // Grava o system message da conta. A partir daí a Bea segue 100% esse texto
  // (congelado). Salvar vazio reverte pro default em runtime.
  update(content) {
    return axios.patch(this.url, { system_prompt: { content } });
  }
}

export default new AiAgentSystemPrompt();
