// BR-specific date helpers used across BeClinic plugins (patients, agenda, etc.).
// Keep these isolated from Chatwoot core (`app/javascript/shared/helpers/DateHelper.js`)
// so the core helper file stays untouched.

// Date-only string ('YYYY-MM-DD') — must NOT be parsed through new Date() because
// the spec parses it as UTC midnight, which shifts the day for users west of UTC.
const ISO_DATE_ONLY_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const BR_DATE_RE = /^(\d{2})\/(\d{2})\/(\d{4})$/;

// Format a value as DD/MM/YYYY.
// - For date-only strings ('YYYY-MM-DD'): keeps the day as-is, no timezone shift.
// - For ISO datetimes / Date instances: uses local-time getters (so a Brazilian
//   user gets the BRT calendar day).
// Returns '' for empty/invalid input.
export const formatDateBR = value => {
  if (!value) return '';
  if (typeof value === 'string') {
    const iso = value.match(ISO_DATE_ONLY_RE);
    if (iso) return `${iso[3]}/${iso[2]}/${iso[1]}`;
    if (BR_DATE_RE.test(value)) return value;
  }
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const dd = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const yyyy = d.getFullYear();
  return `${dd}/${mm}/${yyyy}`;
};

// DD/MM/YYYY → YYYY-MM-DD. Returns '' if not a fully-typed valid BR date.
export const brToIsoDate = value => {
  if (!value) return '';
  const m = String(value).match(BR_DATE_RE);
  if (!m) return '';
  const [, dd, mm, yyyy] = m;
  const day = Number(dd);
  const month = Number(mm);
  const year = Number(yyyy);
  if (month < 1 || month > 12 || day < 1 || day > 31) return '';
  return `${yyyy}-${mm}-${dd}`;
};

// Mask a partial DD/MM/YYYY string while the user types.
export const maskDateBR = raw => {
  const digits = String(raw || '').replace(/\D/g, '').slice(0, 8);
  if (digits.length <= 2) return digits;
  if (digits.length <= 4) return `${digits.slice(0, 2)}/${digits.slice(2)}`;
  return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4)}`;
};

// ─── BRT (America/Sao_Paulo) datetime helpers ──────────────────────────────
// Background: <input type="datetime-local"> emits/accepts naïve strings like
// "2026-05-15T14:30" with no timezone. The browser interprets them in the
// user's local timezone, which corrupts data when the operator and the clinic
// are in different zones. These helpers force the BRT interpretation so the
// stored UTC value matches what the operator typed in São Paulo time.
//
// Auto-detects the offset via Intl so we handle horário de verão correctly
// if Brazil ever re-adopts DST (currently UTC-3 year-round since 2019).

const BRT_TZ = 'America/Sao_Paulo';

const tzOffsetMinutes = (instant, timeZone) => {
  const fmt = tz =>
    new Intl.DateTimeFormat('en-US', {
      timeZone: tz,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }).formatToParts(instant);
  const toMs = parts => {
    const get = t => Number(parts.find(p => p.type === t).value);
    return Date.UTC(
      get('year'),
      get('month') - 1,
      get('day'),
      get('hour') === 24 ? 0 : get('hour'),
      get('minute'),
      get('second')
    );
  };
  return (toMs(fmt(timeZone)) - toMs(fmt('UTC'))) / 60000;
};

// "2026-05-15T14:30" (interpreted as BRT wall-clock) → ISO UTC string.
// Returns null for empty/invalid input.
export const brtLocalToIso = localStr => {
  if (!localStr) return null;
  const m = String(localStr).match(
    /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?$/
  );
  if (!m) return null;
  const [, y, mo, d, h, mi, s = '00'] = m;
  // First UTC guess assuming components are already UTC, then adjust by BRT offset.
  const naiveUtc = Date.UTC(+y, +mo - 1, +d, +h, +mi, +s);
  const offsetMin = tzOffsetMinutes(new Date(naiveUtc), BRT_TZ);
  return new Date(naiveUtc - offsetMin * 60000).toISOString();
};

// ISO UTC string (or Date) → "YYYY-MM-DDTHH:mm" in BRT, suitable for
// <input type="datetime-local"> initial value. Returns '' for empty/invalid.
export const isoToBrtLocal = value => {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: BRT_TZ,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(d);
  const get = t => parts.find(p => p.type === t).value;
  const hour = get('hour') === '24' ? '00' : get('hour');
  return `${get('year')}-${get('month')}-${get('day')}T${hour}:${get('minute')}`;
};

// Format a Date/ISO as "DD/MM/YYYY HH:mm" in BRT. Returns '' for invalid.
export const formatDateTimeBRT = value => {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: BRT_TZ,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
    .format(d)
    .replace(',', '');
};

// Format a Date/ISO as "DD/MM/YYYY" in BRT.
export const formatDateBRT = value => {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: BRT_TZ,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(d);
};

// Format a Date/ISO as "HH:mm" in BRT.
export const formatTimeBRT = value => {
  if (!value) return '';
  const d = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(d.getTime())) return '';
  return new Intl.DateTimeFormat('pt-BR', {
    timeZone: BRT_TZ,
    hour: '2-digit',
    minute: '2-digit',
  }).format(d);
};
