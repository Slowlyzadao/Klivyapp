// Store de consentimentos clínicos (ConsentRecord).
import { defineStore } from 'pinia';
import { consentRecordsApi } from '../api/consent_records';

export const useConsentRecordsStore = defineStore('consent_records', {
  state: () => ({
    pending:  [],
    signed:   [],
    loading:  false,
    error:    null
  }),

  getters: {
    pendingCount: (s) => s.pending.length,
    signedCount:  (s) => s.signed.length
  },

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        const data = await consentRecordsApi.list();
        this.pending = data.pending;
        this.signed  = data.signed;
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async sign(id, signatureBlob) {
      const updated = await consentRecordsApi.sign(id, signatureBlob);
      // Move de pending para signed
      this.pending = this.pending.filter(c => c.id !== id);
      this.signed = [updated, ...this.signed];
      return updated;
    }
  }
});
