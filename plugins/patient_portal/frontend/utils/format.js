// Helpers de formatação compartilhados entre páginas. Mantém a lógica fora
// de cada componente — fácil testar e padronizar locale.
const LOCALE = 'pt-BR';

const dateFmt = new Intl.DateTimeFormat(LOCALE, { day: '2-digit', month: 'short', year: 'numeric' });
const timeFmt = new Intl.DateTimeFormat(LOCALE, { hour: '2-digit', minute: '2-digit' });
const longFmt = new Intl.DateTimeFormat(LOCALE, {
  weekday: 'long', day: '2-digit', month: 'long', year: 'numeric',
  hour: '2-digit', minute: '2-digit'
});

export function formatDate(iso) {
  if (!iso) return '';
  return dateFmt.format(new Date(iso));
}

export function formatTime(iso) {
  if (!iso) return '';
  return timeFmt.format(new Date(iso));
}

export function formatDateTime(iso) {
  if (!iso) return '';
  return `${formatDate(iso)} · ${formatTime(iso)}`;
}

export function formatLong(iso) {
  if (!iso) return '';
  return longFmt.format(new Date(iso));
}

export function formatRelative(iso) {
  if (!iso) return '';
  const target = new Date(iso);
  const now = new Date();
  const diffMs = target - now;
  const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));

  if (Math.abs(diffDays) <= 1) {
    if (diffDays === 0)  return 'hoje';
    if (diffDays === 1)  return 'amanhã';
    if (diffDays === -1) return 'ontem';
  }
  if (diffDays > 1 && diffDays <= 7)   return `em ${diffDays} dias`;
  if (diffDays < -1 && diffDays >= -7) return `há ${Math.abs(diffDays)} dias`;
  return formatDate(iso);
}

export function formatCurrency(cents) {
  return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: 'BRL' }).format((cents || 0) / 100);
}

export function fileSize(bytes) {
  if (!bytes) return '';
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(0)} KB`;
  return `${(kb / 1024).toFixed(1)} MB`;
}
