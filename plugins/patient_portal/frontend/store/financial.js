// Store financeira — summary + lista de parcelas.
import { defineStore } from 'pinia';
import { financialApi } from '../api/financial';

export const useFinancialStore = defineStore('financial', {
  state: () => ({
    totals:           { open_amount_cents: 0, overdue_amount_cents: 0, paid_year_cents: 0, open_count: 0, overdue_count: 0 },
    showPaidHistory:  true,
    nextDue:          null,
    installments:     [],
    loading:          false,
    error:            null
  }),

  getters: {
    hasOverdue:  (s) => s.totals.overdue_count > 0,
    hasOpen:     (s) => s.totals.open_count > 0
  },

  actions: {
    async fetchSummary() {
      this.loading = true; this.error = null;
      try {
        const data = await financialApi.summary();
        this.totals          = data.totals;
        this.showPaidHistory = data.show_paid_history;
        this.nextDue         = data.next_due;
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async fetchInstallments(scope = 'all') {
      this.loading = true; this.error = null;
      try {
        this.installments = await financialApi.installments(scope);
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async openProof(id) {
      await financialApi.proof(id);
    }
  }
});
