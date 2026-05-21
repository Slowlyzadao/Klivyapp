/* eslint-disable */
// Service Worker do Portal do Paciente (Sprint G).
//
// Escopo: '/'. Responsável apenas por:
//   1. Receber `push` events → exibir notificação nativa do SO.
//   2. Receber `notificationclick` → abrir/focar a janela em uma URL específica.
//
// NÃO faz cache offline neste sprint (cacheamento PWA fica como melhoria futura).
//
// Servido por Rails como arquivo estático em public/. Por estar em /, o escopo
// engloba a SPA inteira do portal (que mora em /, /appointments, /financial, etc).

self.addEventListener('install', event => {
  // Ativa imediatamente — não há cache pra esquentar.
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', event => {
  let data = {};
  try {
    if (event.data) data = event.data.json();
  } catch (_) {
    data = { title: 'Klivy', body: event.data ? event.data.text() : '' };
  }

  const title = data.title || 'Klivy';
  const options = {
    body:    data.body || '',
    icon:    '/android-icon-192x192.png',
    badge:   '/android-icon-96x96.png',
    data:    data.data || {},
    tag:     data.data?.kind || 'klivy-default',
    renotify: true
  };

  event.waitUntil(self.registration.showNotification(title, options));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();

  const targetPath = pickTargetPath(event.notification.data || {});

  event.waitUntil((async () => {
    const allClients = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of allClients) {
      if (new URL(client.url).pathname === targetPath && 'focus' in client) {
        return client.focus();
      }
    }
    if (self.clients.openWindow) {
      return self.clients.openWindow(targetPath);
    }
    return null;
  })());
});

function pickTargetPath(data) {
  if (typeof data.url === 'string' && data.url.startsWith('/')) return data.url;
  const kind = data.kind;
  if (kind === 'financial_charge' || kind === 'financial_due_soon') {
    return data.installment_id ? `/financial/installments/${data.installment_id}` : '/financial';
  }
  if (kind === 'appointment_confirmed' || kind === 'appointment_reminder') {
    return data.appointment_id ? `/appointments/${data.appointment_id}` : '/appointments';
  }
  if (kind === 'document_ready') {
    return '/health';
  }
  if (kind === 'message_new') return '/messages';
  if (kind === 'consent_pending') return '/consent-records';
  return '/notifications';
}
