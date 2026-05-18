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
