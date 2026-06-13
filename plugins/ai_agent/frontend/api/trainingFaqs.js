/* global axios */
import ApiClient from 'dashboard/api/ApiClient';

// FAQs já aprovadas/publicadas no RAG da Bea, agregadas de todas as conversas
// de treinamento. Cada FAQ é endereçada pelo id composto "<conversa>-<índice>".
class AiAgentTrainingFaqs extends ApiClient {
  constructor() {
    super('ai_agent/training_faqs', { accountScoped: true });
  }

  get() {
    return axios.get(this.url);
  }

  update(id, faq) {
    return axios.patch(`${this.url}/${id}`, { faq });
  }

  delete(id) {
    return axios.delete(`${this.url}/${id}`);
  }

  // Apaga várias FAQs. `ids` vazio/ausente → apaga TODAS; senão, só as do array.
  deleteMany(ids) {
    return axios.delete(`${this.url}/destroy_all`, {
      data: ids && ids.length ? { ids } : {},
    });
  }
}

export default new AiAgentTrainingFaqs();
