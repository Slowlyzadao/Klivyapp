// Store de pagamentos online. Polling leve em awaiting_payment pra detectar
// confirmação por webhook (em dev é via simulate_paid).
import { defineStore } from 'pinia';
import { paymentsApi } from '../api/payments';

const POLL_MS = 4000;

export const usePaymentsStore = defineStore('payments', {
  state: () => ({
    current:    null,
    loading:    false,
    error:      null,
    _pollTimer: null
  }),

  getters: {
    isAwaiting: (s) => s.current?.status === 'awaiting_payment',
    isPaid:     (s) => s.current?.status === 'paid'
  },

  actions: {
    async start({ installmentId, method }) {
      this.loading = true; this.error = null;
      try {
        this.current = await paymentsApi.create({ installmentId, method });
        return this.current;
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally {
        this.loading = false;
      }
    },

    async refresh(id) {
      try {
        this.current = await paymentsApi.get(id);
        return this.current;
      } catch (e) { this.error = e.message; }
    },

    startPolling(id) {
      this.stopPolling();
      this._pollTimer = setInterval(async () => {
        await this.refresh(id);
        if (this.isPaid || ['expired', 'failed', 'cancelled'].includes(this.current?.status)) {
          this.stopPolling();
        }
      }, POLL_MS);
    },

    stopPolling() {
      if (this._pollTimer) {
        clearInterval(this._pollTimer);
        this._pollTimer = null;
      }
    },

    async cancel(id) {
      this.current = await paymentsApi.cancel(id);
      this.stopPolling();
    },

    async simulatePaid(id) {
      this.current = await paymentsApi.simulatePaid(id);
      this.stopPolling();
    },

    reset() {
      this.stopPolling();
      this.current = null;
      this.error   = null;
    }
  }
});
