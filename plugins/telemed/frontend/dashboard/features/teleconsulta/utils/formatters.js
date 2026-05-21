// Helpers de formatação usados na listagem de teleconsultas (clínica).
// Mantidos puros para serem facilmente testáveis e reutilizáveis pelos
// cards de "Próximas", "Em andamento", "Finalizadas", "Sem comparecimento".

const TZ = 'America/Sao_Paulo';

export const STATUS_LABELS = {
  scheduled: 'Agendado',
  confirmed: 'Confirmado',
  arrived: 'Aguardando',
  in_progress: 'Em atendimento',
  completed: 'Finalizado',
  no_show: 'Sem comparec.',
};

function isSameDay(a, b) {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

// Iniciais a partir do nome do paciente (até 2 letras maiúsculas).
// "Roberto Alves" → "RA"; "Ana" → "AN"; "" → "?".
export function initialsFromName(name) {
  if (!name || typeof name !== 'string') return '?';
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return '?';
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

// Formata a data de início no estilo "Hoje, 15:30" / "Amanhã, 09:00"
// / "23/05, 14:00". Usa fuso de São Paulo para alinhar com o backend.
export function formatStartDateLabel(isoDate) {
  if (!isoDate) return '—';
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return '—';

  const today = new Date();
  const tomorrow = new Date(today);
  tomorrow.setDate(today.getDate() + 1);

  const time = date.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: TZ,
  });

  if (isSameDay(date, today)) return `Hoje, ${time}`;
  if (isSameDay(date, tomorrow)) return `Amanhã, ${time}`;

  const shortDate = date.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    timeZone: TZ,
  });
  return `${shortDate}, ${time}`;
}

// "Hoje, 10:00" / "Ontem, 10:00" / "15/05/2026, 09:15" — usado nos cards
// finalizados (datas no passado).
export function formatPastDateLabel(isoDate) {
  if (!isoDate) return '—';
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return '—';

  const today = new Date();
  const yesterday = new Date(today);
  yesterday.setDate(today.getDate() - 1);

  const time = date.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: TZ,
  });

  if (isSameDay(date, today)) return `Hoje, ${time}`;
  if (isSameDay(date, yesterday)) return `Ontem, ${time}`;

  const fullDate = date.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: TZ,
  });
  return `${fullDate}, ${time}`;
}

// "20/05/2026 às 22:00" — usado no banner do detalhe.
export function formatFullDateTimeLabel(isoDate) {
  if (!isoDate) return '—';
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return '—';
  const datePart = date.toLocaleDateString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    timeZone: TZ,
  });
  const timePart = date.toLocaleTimeString('pt-BR', {
    hour: '2-digit',
    minute: '2-digit',
    timeZone: TZ,
  });
  return `${datePart} às ${timePart}`;
}

// "15 min" / "1h 05min" — duração curta humanizada (entrada em minutos).
export function formatDurationMinutes(minutes) {
  const total = Math.max(0, Math.round(Number(minutes) || 0));
  if (total < 60) return `${total} min`;
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  return mins === 0
    ? `${hours}h`
    : `${hours}h ${String(mins).padStart(2, '0')}min`;
}

// "MM:SS" — usado nos timestamps de áudio/transcrição (entrada em segundos).
export function formatClockSeconds(seconds) {
  const total = Math.max(0, Math.round(Number(seconds) || 0));
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

// Sufixo relativo do tipo "(em 45 min)" / "(em 2h)" / "(em 3 dias)".
// Retorna `null` para datas no passado — o caller decide o que exibir.
export function formatRelativeHint(isoDate, now = new Date()) {
  if (!isoDate) return null;
  const date = new Date(isoDate);
  if (Number.isNaN(date.getTime())) return null;

  const diffMs = date.getTime() - now.getTime();
  if (diffMs <= 0) return null;

  const diffMin = Math.round(diffMs / 60000);
  if (diffMin < 60) return `em ${diffMin} min`;
  const diffHours = Math.round(diffMin / 60);
  if (diffHours < 24) return `em ${diffHours}h`;
  const diffDays = Math.round(diffHours / 24);
  if (diffDays === 1) return 'amanhã';
  return `em ${diffDays} dias`;
}
