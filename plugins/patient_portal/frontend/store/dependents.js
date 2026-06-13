// Store de dependentes (Sprint I, PRD §13.2).
//
// Estado:
//   - acting     : quem logou (responsável OU paciente single)
//   - active     : quem está sendo acessado agora (self OU dependente)
//   - accessible : lista do que o acting pode acessar (self + dependentes)
//
// Quando active != acting → flag onDependent=true → UI mostra indicador.
import { defineStore } from 'pinia';
import { dependentsApi } from '../api/dependents';

export const useDependentsStore = defineStore('dependents', {
  state: () => ({
    acting:     null,
    active:     null,
    accessible: [],
    loading:    false,
    error:      null,
    switching:  false
  }),

  getters: {
    onDependent: (s) => s.active && s.acting && s.active.id !== s.acting.id,
    hasDependents: (s) => (s.accessible?.length || 0) > 1,
    activeName:  (s) => s.active?.name || ''
  },

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        const data = await dependentsApi.list();
        this._apply(data);
      } catch (e) { this.error = e.message; }
      finally { this.loading = false; }
    },

    async switchTo(patientId) {
      if (this.switching) return;
      this.switching = true; this.error = null;
      try {
        const data = await dependentsApi.switch(patientId);
        this._apply(data);
        return true;
      } catch (e) {
        this.error = e.message;
        return false;
      } finally {
        this.switching = false;
      }
    },

    _apply(ctxPayload) {
      this.acting     = ctxPayload?.acting     || null;
      this.active     = ctxPayload?.active     || null;
      this.accessible = ctxPayload?.accessible || [];
    },

    reset() {
      this.acting = null; this.active = null; this.accessible = [];
      this.error = null; this.loading = false; this.switching = false;
    }
  }
});
