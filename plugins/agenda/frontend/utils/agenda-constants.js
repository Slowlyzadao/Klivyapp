/**
 * Constantes compartilhadas do módulo de Agenda.
 * Extraídas do AgendaDashboard.vue original para evitar duplicação.
 */

export const MONTH_KEYS = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

export const DAY_KEYS = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

export const DOW_MAP = {
  0: 'sun',
  1: 'mon',
  2: 'tue',
  3: 'wed',
  4: 'thu',
  5: 'fri',
  6: 'sat',
};

export const TREATMENTS = [
  'Avaliação',
  'Reavaliação',
  'Profilaxia (limpeza)',
  'Restauração',
  'Dente quebrado / urgência',
  'Endodontia (canal)',
  'Extração',
  'Clareamento',
  'Implante dental',
  'Prótese fixa',
  'Prótese removível',
  'Protocolo sobre implante',
  'Prova de prótese',
  'Entrega de prótese',
];

export const EVENT_TYPES = [
  {
    value: 'consultation',
    label: 'Consulta',
    color: '#3b82f6',
    icon: 'i-lucide-stethoscope',
    contextLabel: 'Detalhes do Agendamento',
  },
  {
    value: 'agenda_block',
    label: 'Bloqueio de Agenda',
    color: '#ef4444',
    icon: 'i-lucide-lock',
    contextLabel: 'Detalhes do Bloqueio',
  },
  {
    value: 'appointment',
    label: 'Compromisso',
    color: '#10b981',
    icon: 'i-lucide-calendar-check',
    contextLabel: 'Detalhes do Compromisso',
  },
];

export function getEventTypeMeta(value) {
  return (
    EVENT_TYPES.find(t => t.value === value) || EVENT_TYPES[0]
  );
}

/**
 * Formata telefone brasileiro pro padrão amigável, sem código do país.
 *   "+5547996835065" → "(47) 99683-5065"
 *   "+554732221234"  → "(47) 3222-1234"
 *   "47996835065"    → "(47) 99683-5065"
 * Strings curtas/inválidas voltam como vieram (sem quebrar).
 */
export function formatPhoneBR(raw) {
  if (!raw) return '';
  const digits = String(raw).replace(/\D/g, '');
  // Remove DDI 55 do começo se presente
  const local = digits.startsWith('55') && digits.length >= 12 ? digits.slice(2) : digits;
  if (local.length === 11) {
    // celular: (DD) 9XXXX-XXXX
    return `(${local.slice(0, 2)}) ${local.slice(2, 7)}-${local.slice(7)}`;
  }
  if (local.length === 10) {
    // fixo: (DD) XXXX-XXXX
    return `(${local.slice(0, 2)}) ${local.slice(2, 6)}-${local.slice(6)}`;
  }
  return raw;
}

export const PRIORITIES = [
  { value: 'urgent', label: 'Urgente' },
  { value: 'high', label: 'Alta' },
  { value: 'medium', label: 'Média' },
  { value: 'low', label: 'Baixa' },
];

// Auditoria 2026-05-15 (PR-H): paleta realinhada com referência externa
// para evitar confusão visual.
//   - confirmed mudou de verde para AMARELO — verde fica reservado para
//     completed (fluxo "concluído").
//   - arrived mudou de amarelo para LARANJA — diferencia da confirmação.
//   - in_progress mudou de azul para TEAL — verde-água do paciente "ativo
//     no atendimento agora", contrastando com o verde-escuro de "finalizado".
//   - completed, no_show, cancelled, scheduled mantidos.
// `border` segue 1 tom mais escuro que `color`.
export const STATUS_CONFIGS = {
  scheduled: { label: 'Agendado', color: '#9ca3af', border: '#6b7280' },
  confirmed: { label: 'Confirmado', color: '#f59e0b', border: '#d97706' },
  arrived: { label: 'Chegou', color: '#f97316', border: '#ea580c' },
  in_progress: {
    label: 'Em atendimento',
    color: '#14b8a6',
    border: '#0d9488',
  },
  completed: { label: 'Atendido', color: '#16a34a', border: '#15803d' },
  no_show: { label: 'Faltou', color: '#ef4444', border: '#dc2626' },
  cancelled: { label: 'Cancelado', color: '#6b7280', border: '#4b5563' },
};

export const STATUS_OPTIONS = [
  { key: 'scheduled', label: 'Agendado' },
  { key: 'confirmed', label: 'Confirmado' },
  { key: 'arrived', label: 'Chegou' },
  { key: 'in_progress', label: 'Em atendimento' },
  { key: 'completed', label: 'Atendido' },
  { key: 'no_show', label: 'Faltou' },
  // Auditoria 2026-05-15: cancelled estava fora do filtro porque a clínica
  // não tinha cancelados antes da reconciliação Clinicorp (PR-D). Agora
  // tem 320+ — precisa ficar visível no filtro lateral.
  { key: 'cancelled', label: 'Cancelado' },
];

export const DELETE_REASONS = [
  { value: 'cancelamento_usuario', label: 'Cancelamento pelo usuário' },
  { value: 'cancelamento_paciente', label: 'Cancelamento pelo paciente' },
  { value: 'reagendamento', label: 'Reagendamento' },
  { value: 'outro', label: 'Outro motivo' },
];

export const PERIOD_LABELS = {
  morning: 'Manhã (06:00–12:00)',
  afternoon: 'Tarde (12:00–18:00)',
  evening: 'Noite (18:00–00:00)',
};

export const PERIOD_SHORT_LABELS = {
  morning: 'Manhã',
  afternoon: 'Tarde',
  evening: 'Noite',
};

export const DOW_LABELS_PT = {
  mon: 'Seg',
  tue: 'Ter',
  wed: 'Qua',
  thu: 'Qui',
  fri: 'Sex',
  sat: 'Sáb',
  sun: 'Dom',
};

export const CUSTOM_ATTR_ICONS = {
  text: 'i-lucide-type',
  textarea: 'i-lucide-align-left',
  select: 'i-lucide-list',
  date: 'i-lucide-calendar',
  phone: 'i-lucide-phone',
  cpf: 'i-lucide-contact',
  rg: 'i-lucide-id-card',
};
