// Store de auth (Pinia). Mantém estado do fluxo OTP + sessão.
// Persistência: localStorage (key `pp.jwt`). MVP não usa refresh token —
// JWT direto com TTL 7d, suficiente.
import { defineStore } from 'pinia';
import { authApi } from '../api/auth';
import { consentsApi } from '../api/consents';

const STORAGE_KEY = 'pp.jwt';

export const useAuthStore = defineStore('auth', {
  state: () => ({
    // Sessão
    jwt:     localStorage.getItem(STORAGE_KEY) || null,
    patient: null,
    account: null,
    consent: { required: false, term_version: null },

    // Fluxo OTP (não persistido)
    identifier: '',
    channel:    'email',
    tempToken:  null,
    accounts:   [],
    loading:    false,
    error:      null
  }),

  getters: {
    isAuthenticated:    (s) => !!s.jwt,
    multiAccount:       (s) => s.accounts.length > 1,
    needsPortalConsent: (s) => s.consent?.required === true
  },

  actions: {
    setError(message) { this.error = message; },
    clearError()      { this.error = null; },

    async requestOtp({ identifier, channel }) {
      this.loading = true; this.error = null;
      try {
        await authApi.requestOtp({ identifier, channel });
        this.identifier = identifier;
        this.channel    = channel;
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally { this.loading = false; }
    },

    async verifyOtp({ code }) {
      this.loading = true; this.error = null;
      try {
        const data = await authApi.verifyOtp({ identifier: this.identifier, code });
        this.tempToken = data.temp_token;
        this.accounts  = data.patients;
        // Se só uma account, segue direto pra select.
        if (this.accounts.length === 1) {
          await this.selectAccount(this.accounts[0].account_id);
        }
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally { this.loading = false; }
    },

    async selectAccount(accountId) {
      this.loading = true; this.error = null;
      try {
        const data = await authApi.selectAccount({ tempToken: this.tempToken, accountId });
        this.jwt     = data.jwt;
        this.patient = data.patient;
        this.account = data.account;
        localStorage.setItem(STORAGE_KEY, data.jwt);
        // Limpa estado intermediário
        this.tempToken = null;
        this.accounts  = [];
        // Carrega consent flag — separa o flow de login do gate de consent.
        const me = await authApi.me();
        this.consent = me.consent || { required: false, term_version: null };
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally { this.loading = false; }
    },

    async hydrate() {
      if (!this.jwt) return;
      try {
        const data = await authApi.me();
        this.patient = data.patient;
        this.account = data.account;
        this.consent = data.consent || { required: false, term_version: null };
      } catch (e) {
        // Token inválido/expirado → limpa
        this.logout();
      }
    },

    async acceptPortalTerms() {
      await consentsApi.acceptPortalTerms();
      this.consent = { ...this.consent, required: false };
    },

    async logout() {
      try { await authApi.logout(); } catch (_) { /* ignore */ }
      this.jwt = null;
      this.patient = null;
      this.account = null;
      localStorage.removeItem(STORAGE_KEY);
    }
  }
});
