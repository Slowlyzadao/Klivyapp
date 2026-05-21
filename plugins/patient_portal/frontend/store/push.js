// Store de Web Push (Sprint G).
//
// Responsabilidades:
//   1. Detectar suporte (`serviceWorker` + `PushManager` + `Notification`).
//   2. Registrar Service Worker `/patient_portal_sw.js` no escopo `/`.
//   3. Pedir permissão e inscrever no PushManager com a VAPID public key.
//   4. POST /push_subscriptions com endpoint+keys → backend guarda + envia
//      push quando algum evento dispara.
//
// O fluxo "registrar push" só roda após login. iOS Safari < 16.4 não suporta
// Web Push em PWA não instalado — a store responde `supported=false` e a UI
// orienta o paciente a instalar o PWA na tela inicial.
import { defineStore } from 'pinia';
import { pushApi } from '../api/push';

const SW_PATH = '/patient_portal_sw.js';
const SW_SCOPE = '/';

function urlBase64ToUint8Array(base64String) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = window.atob(base64);
  const out = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i += 1) out[i] = raw.charCodeAt(i);
  return out;
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  for (let i = 0; i < bytes.byteLength; i += 1) binary += String.fromCharCode(bytes[i]);
  return window.btoa(binary)
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export const usePushStore = defineStore('push', {
  state: () => ({
    supported:  false,
    permission: 'default',
    subscribed: false,
    busy:       false,
    error:      null,
    endpoint:   null,
  }),

  actions: {
    detectSupport() {
      const ok = 'serviceWorker' in navigator
              && 'PushManager' in window
              && 'Notification' in window;
      this.supported = ok;
      this.permission = ok ? Notification.permission : 'unsupported';
      return ok;
    },

    async ensureRegistration() {
      const existing = await navigator.serviceWorker.getRegistration(SW_SCOPE);
      if (existing) return existing;
      return navigator.serviceWorker.register(SW_PATH, { scope: SW_SCOPE });
    },

    async hydrate() {
      if (!this.detectSupport()) return;
      try {
        const reg = await this.ensureRegistration();
        const sub = await reg.pushManager.getSubscription();
        if (sub) {
          this.subscribed = true;
          this.endpoint   = sub.endpoint;
        }
      } catch (e) {
        this.error = e.message;
      }
    },

    async subscribe() {
      if (!this.detectSupport()) {
        this.error = 'Push não suportado neste dispositivo.';
        return false;
      }

      this.busy = true; this.error = null;
      try {
        const perm = await Notification.requestPermission();
        this.permission = perm;
        if (perm !== 'granted') {
          this.error = 'Permissão de notificação negada.';
          return false;
        }

        const reg = await this.ensureRegistration();
        const { public_key } = await pushApi.publicKey();

        const sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(public_key)
        });

        await pushApi.subscribe({
          endpoint: sub.endpoint,
          keys: {
            p256dh: arrayBufferToBase64(sub.getKey('p256dh')),
            auth:   arrayBufferToBase64(sub.getKey('auth'))
          }
        });

        this.subscribed = true;
        this.endpoint = sub.endpoint;
        return true;
      } catch (e) {
        this.error = e.message;
        return false;
      } finally {
        this.busy = false;
      }
    },

    async unsubscribe() {
      if (!this.subscribed) return true;
      this.busy = true; this.error = null;
      try {
        const reg = await this.ensureRegistration();
        const sub = await reg.pushManager.getSubscription();
        if (sub) {
          await pushApi.unsubscribe(sub.endpoint).catch(() => null);
          await sub.unsubscribe();
        }
        this.subscribed = false;
        this.endpoint   = null;
        return true;
      } catch (e) {
        this.error = e.message;
        return false;
      } finally {
        this.busy = false;
      }
    }
  }
});
