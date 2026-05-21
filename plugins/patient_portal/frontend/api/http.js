// Cliente HTTP centralizado. Não usa axios pra evitar bundle extra — fetch
// nativo já dá conta. Interceptor de auth injeta JWT do auth store.
import { useAuthStore } from '../store/auth';

const BASE_URL = window.klivyPatientPortalConfig?.apiBaseUrl || '';

async function request(method, path, { body, headers = {}, auth = true } = {}) {
  const finalHeaders = { 'Content-Type': 'application/json', Accept: 'application/json', ...headers };
  if (auth) {
    const token = useAuthStore().jwt;
    if (token) finalHeaders.Authorization = `Bearer ${token}`;
  }

  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: finalHeaders,
    body: body ? JSON.stringify(body) : undefined,
    credentials: 'same-origin'
  });

  let payload = null;
  try { payload = await res.json(); } catch (_) { /* sem body */ }

  if (!res.ok) {
    const err = new Error(payload?.errors?.[0]?.message || `HTTP ${res.status}`);
    err.status = res.status;
    err.code = payload?.errors?.[0]?.code;
    err.payload = payload;
    throw err;
  }
  return payload?.data ?? payload;
}

export const http = {
  get:    (path, opts)        => request('GET', path, opts),
  post:   (path, body, opts)  => request('POST', path, { ...opts, body }),
  patch:  (path, body, opts)  => request('PATCH', path, { ...opts, body }),
  del:    (path, opts)        => request('DELETE', path, opts)
};
