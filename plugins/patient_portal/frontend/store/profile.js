// Store do perfil do paciente. Editáveis (whitelist no backend): name, email,
// phone, birthdate, sex, address, contact_preferences.
import { defineStore } from 'pinia';
import { profileApi } from '../api/profile';

export const useProfileStore = defineStore('profile', {
  state: () => ({
    data:    null,
    loading: false,
    saving:  false,
    error:   null
  }),

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        this.data = await profileApi.get();
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async save(updates) {
      this.saving = true; this.error = null;
      try {
        this.data = await profileApi.update(updates);
        return this.data;
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally {
        this.saving = false;
      }
    },

    async exportLgpd() {
      return await profileApi.lgpdExport();
    }
  }
});
