/**
 * Utilitários de data/hora para a Agenda.
 * Funções puras sem side-effects.
 */

/**
 * Adiciona zero à esquerda em números de 1 dígito.
 */
export function padZ(n) {
  return String(n).padStart(2, '0');
}

/**
 * Converte Date para string ISO-like com fuso local: "YYYY-MM-DDTHH:mm:ss±HH:MM"
 */
export function toLocalDatetimeString(date) {
  const tzo = -date.getTimezoneOffset();
  const dif = tzo >= 0 ? '+' : '-';
  const padOffset = function (num) {
    const norm = Math.floor(Math.abs(num));
    return String(norm).padStart(2, '0');
  };
  return `${date.getFullYear()}-${padZ(date.getMonth() + 1)}-${padZ(
    date.getDate()
  )}T${padZ(date.getHours())}:${padZ(
    date.getMinutes()
  )}:00${dif}${padOffset(tzo / 60)}:${padOffset(tzo % 60)}`;
}

/**
 * Converte valor de evento (string ISO, timestamp Unix, etc.) para Date.
 */
export function parseEventDate(val) {
  if (!val) return new Date();
  if (typeof val === 'number') return new Date(val * 1000);
  return new Date(val);
}

/**
 * Formata hora de um evento: "HH:mm"
 */
export function formatEventTime(startsAt) {
  const d = parseEventDate(startsAt);
  return `${padZ(d.getHours())}:${padZ(d.getMinutes())}`;
}

/**
 * Calcula duração em horas entre starts_at e ends_at.
 * Mínimo de ~4min (0.067h) para permitir eventos curtos de 5min.
 */
export function getEventDurationInHours(event, resizingEndAt) {
  if (!event.starts_at || !event.ends_at) return 1;
  const start = parseEventDate(event.starts_at);
  const end = resizingEndAt
    ? parseEventDate(resizingEndAt)
    : parseEventDate(event.ends_at);
  const diffMs = end - start;
  const hours = diffMs / (1000 * 60 * 60);
  return Math.max(0.067, hours);
}

/**
 * Calcula duração em minutos.
 */
export function getEventDurationMinutes(event) {
  if (!event.starts_at || !event.ends_at) return 60;
  const start = parseEventDate(event.starts_at);
  const end = parseEventDate(event.ends_at);
  return Math.max(1, Math.round((end - start) / (1000 * 60)));
}

/**
 * Retorna o "tier" de tamanho do evento baseado na duração.
 * 'micro' (≤15min), 'compact' (≤29min), 'medium' (≤39min), null (normal ≥40min)
 */
export function getEventSizeTier(event) {
  const mins = getEventDurationMinutes(event);
  if (mins <= 15) return 'micro';
  if (mins < 30) return 'compact';
  if (mins < 40) return 'medium';
  return null;
}

/**
 * Retorna true se o evento é compacto (≤50min).
 */
export function isCompactEvent(event) {
  return getEventDurationMinutes(event) <= 50;
}

/**
 * Formata data como string "YYYY-MM-DD" a partir de dayObj.
 */
export function dayObjToDateStr(dayObj) {
  return `${dayObj.year}-${padZ(dayObj.month + 1)}-${padZ(dayObj.day)}`;
}

/**
 * Cria o newEvent padrão com valores iniciais.
 */
export function createDefaultNewEvent(options = {}) {
  const now = new Date();
  return {
    title: '',
    event_type: 'consultation',
    priority: 'medium',
    treatment: '',
    category_id: options.category_id || null,
    date:
      options.date ||
      `${now.getFullYear()}-${padZ(now.getMonth() + 1)}-${padZ(now.getDate())}`,
    time_start: options.time_start ?? '',
    time_end: options.time_end ?? '',
    user_id: options.user_id || null,
    contact_id: options.contact_id || null,
    patient_id: options.patient_id || null,
    description: options.description || '',
    selectedPatientName: options.selectedPatientName || '',
    selectedPatientPhone: options.selectedPatientPhone || '',
    selectedPatientAvatarUrl: options.selectedPatientAvatarUrl || null,
    custom_values: options.custom_values || {},
    // Sprint K — flag de teleconsulta. O event_type continua 'consultation'
    // (uma teleconsulta É uma consulta), mas este boolean dispara a UI
    // específica (aba Teleconsulta no modal, botão "Entrar na sala" no
    // popup) e marca custom_attributes.telemedicine_enabled no save.
    telemedicine_enabled: options.telemedicine_enabled === true,
  };
}
