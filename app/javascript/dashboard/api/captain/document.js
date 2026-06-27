/* global axios */
import ApiClient from '../ApiClient';

class CaptainDocument extends ApiClient {
  constructor() {
    // A aba "Documentos" da Bea precisa gravar na base de conhecimento que o
    // agente realmente lê (AiAgent::Document → pgvector, consultada pela tool
    // search_knowledge). O endpoint legado `captain/documents` grava em
    // Captain::Document, que a Bea NUNCA consulta — por isso aponta aqui para
    // `ai_agent/documents`, cujo JSON espelha o do Captain (só troca de URL).
    super('ai_agent/documents', { accountScoped: true });
  }

  get({ page = 1, searchKey, assistantId } = {}) {
    return axios.get(this.url, {
      params: {
        page,
        searchKey,
        assistant_id: assistantId,
      },
    });
  }
}

export default new CaptainDocument();
