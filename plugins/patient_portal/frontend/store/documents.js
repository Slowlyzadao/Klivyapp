// Store de documentos — lista + pedidos de 2ª via.
import { defineStore } from 'pinia';
import { documentsApi }        from '../api/documents';
import { documentRequestsApi } from '../api/document_requests';

export const useDocumentsStore = defineStore('documents', {
  state: () => ({
    items:    [],
    requests: [],
    loading:  false,
    error:    null
  }),

  getters: {
    count:               (s) => s.items.length,
    pendingRequestCount: (s) => s.requests.filter(r => r.status === 'pending').length
  },

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        this.items = await documentsApi.list();
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async fetchRequests() {
      this.requests = await documentRequestsApi.list();
    },

    async download(doc) {
      await documentsApi.download(doc.id, doc.file_name);
    },

    async requestDocument(payload) {
      const created = await documentRequestsApi.create(payload);
      this.requests = [created, ...this.requests];
      return created;
    },

    async cancelRequest(id, reason) {
      const updated = await documentRequestsApi.cancel(id, reason);
      const i = this.requests.findIndex(r => r.id === id);
      if (i >= 0) this.requests.splice(i, 1, updated);
      return updated;
    }
  }
});
