// Store de consultas — lista (upcoming/past) + ações + pedidos pendentes.
import { defineStore } from 'pinia';
import { appointmentsApi }        from '../api/appointments';
import { appointmentRequestsApi } from '../api/appointment_requests';

export const useAppointmentsStore = defineStore('appointments', {
  state: () => ({
    upcoming:  [],
    past:      [],
    requests:  [],
    loading:   false,
    error:     null
  }),

  getters: {
    upcomingCount:  (s) => s.upcoming.length,
    pastCount:      (s) => s.past.length,
    pendingRequestCount: (s) => s.requests.filter(r => r.status === 'pending').length
  },

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        const data = await appointmentsApi.list();
        this.upcoming = data.upcoming;
        this.past     = data.past;
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async confirm(id) {
      const updated = await appointmentsApi.confirm(id);
      this.replaceInUpcoming(updated);
      return updated;
    },

    async cancel(id, reason) {
      const updated = await appointmentsApi.cancel(id, reason);
      // Após cancelar, sai do upcoming e entra no past (já vem com cancelled=true).
      this.upcoming = this.upcoming.filter(a => a.id !== id);
      this.past = [updated, ...this.past];
      return updated;
    },

    replaceInUpcoming(updated) {
      const i = this.upcoming.findIndex(a => a.id === updated.id);
      if (i >= 0) this.upcoming.splice(i, 1, updated);
    },

    async fetchRequests() {
      this.requests = await appointmentRequestsApi.list();
    },

    async requestAppointment(payload) {
      const created = await appointmentRequestsApi.create(payload);
      this.requests = [created, ...this.requests];
      return created;
    },

    async cancelRequest(id, reason) {
      const updated = await appointmentRequestsApi.cancel(id, reason);
      const i = this.requests.findIndex(r => r.id === id);
      if (i >= 0) this.requests.splice(i, 1, updated);
      return updated;
    }
  }
});
