// Store de notificações in-app. Sprint E ligou no modelo real
// `PatientPortalNotification`. NotificationDispatcher serve como ponto único
// para os outros fluxos criarem notificações novas.
import { defineStore } from 'pinia';
import { notificationsApi } from '../api/notifications';

export const useNotificationsStore = defineStore('notifications', {
  state: () => ({
    items: [],
    unreadCount: 0,
    loading: false,
    error: null
  }),

  actions: {
    async fetch() {
      this.loading = true; this.error = null;
      try {
        const data = await notificationsApi.list();
        this.items = data.items || [];
        this.unreadCount = data.unread_count || 0;
      } catch (e) {
        this.error = e.message;
      } finally { this.loading = false; }
    },

    async markRead(id) {
      try {
        await notificationsApi.markRead(id);
        const i = this.items.findIndex(n => n.id === id);
        if (i >= 0 && !this.items[i].read) {
          this.items[i] = { ...this.items[i], read: true };
          this.unreadCount = Math.max(0, this.unreadCount - 1);
        }
      } catch (_) { /* não-fatal */ }
    },

    async markAllRead() {
      try {
        await notificationsApi.markAllRead();
        this.unreadCount = 0;
        this.items = this.items.map(i => ({ ...i, read: true }));
      } catch (_) { /* não-fatal */ }
    }
  }
});
