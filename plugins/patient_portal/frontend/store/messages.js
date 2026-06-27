// Store da conversa com a clínica — bridge para Chatwoot via backend.
import { defineStore } from 'pinia';
import { messagesApi } from '../api/messages';

export const useMessagesStore = defineStore('messages', {
  state: () => ({
    conversation:  null,
    messages:      [],
    loading:       false,
    sending:       false,
    error:         null
  }),

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        const data = await messagesApi.list();
        this.conversation = data.conversation;
        this.messages     = data.messages || [];
      } catch (e) {
        this.error = e.message;
      } finally {
        this.loading = false;
      }
    },

    async send(content) {
      this.sending = true; this.error = null;
      try {
        const data = await messagesApi.send(content);
        this.messages = [...this.messages, data.message];
        return data; // { message, urgent, urgent_keywords }
      } catch (e) {
        this.error = e.message;
        throw e;
      } finally {
        this.sending = false;
      }
    },

    async triage(content) {
      try {
        return await messagesApi.triage(content);
      } catch (_) {
        // Falha silenciosa — assumimos não-urgente em caso de erro
        return { urgent: false, keywords: [] };
      }
    }
  }
});
