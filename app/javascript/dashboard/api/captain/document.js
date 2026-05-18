/* global axios */
import ApiClient from '../ApiClient';

// Talks to the AiAgent plugin endpoint (/api/v1/accounts/:id/ai_agent/documents),
// not the legacy Captain::Document table. The Bea RAG (search_knowledge tool)
// reads from AiAgent::Document → ParentChunk/ChildChunk + pgvector. The class
// name is kept as `CaptainDocument` (and the store stays `captainDocuments`)
// to avoid a churny rename across DocumentForm/Index/DocumentCard — the path
// is what defines the contract, not the JS class name.
class CaptainDocument extends ApiClient {
  constructor() {
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
