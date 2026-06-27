// Store de anamneses — só renderiza se a clínica habilitou o opt-in.
import { defineStore } from 'pinia';
import { anamnesesApi } from '../api/anamneses';

export const useAnamnesesStore = defineStore('anamneses', {
  state: () => ({
    exposed: false,
    hasAny:  false,
    items:   [],
    loading: false,
    error:   null
  }),

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        const data = await anamnesesApi.list();
        this.exposed = data.exposed;
        this.hasAny  = data.has_any;
        this.items   = data.items || [];
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    }
  }
});
