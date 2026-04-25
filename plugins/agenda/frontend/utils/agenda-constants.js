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
  { value: 'consultation', label: 'Consulta' },
  { value: 'agenda_block', label: 'Bloqueio de Agenda' },
  { value: 'appointment', label: 'Compromisso' },
];

export const PRIORITIES = [
  { value: 'urgent', label: 'Urgente' },
  { value: 'high', label: 'Alta' },
  { value: 'medium', label: 'Média' },
  { value: 'low', label: 'Baixa' },
];

export const STATUS_CONFIGS = {
  scheduled: { label: 'Agendado', color: '#9ca3af', border: '#6b7280' },
  confirmed: { label: 'Confirmado', color: '#22c55e', border: '#16a34a' },
  arrived: { label: 'Chegou', color: '#eab308', border: '#ca8a04' },
  in_progress: {
    label: 'Em atendimento',
    color: '#3b82f6',
    border: '#2563eb',
  },
  completed: { label: 'Atendido', color: '#22c55e', border: '#16a34a' },
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
