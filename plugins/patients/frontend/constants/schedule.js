/**
 * Constants do módulo Agenda do paciente.
 *
 * Extraído de ScheduleTab.vue (Roadmap #11). Status `deleted_*` correspondem
 * a eventos soft-deletados na agenda mas preservados no prontuário do paciente
 * (rastreabilidade médico-legal). Derivados do `deletion_reason` no backend:
 *   cancelamento_usuario  → deleted_user
 *   cancelamento_paciente → deleted_patient
 *   reagendamento         → deleted_reschedule
 *   outro                 → deleted_other
 */

export const APPOINTMENT_TYPE_LABELS = {
  avaliacao: 'Avaliação',
  retorno: 'Retorno',
  procedimento: 'Procedimento',
  revisao: 'Revisão',
  emergencia: 'Emergência',
};

export const EVENT_TYPE_LABELS = {
  consultation: 'Consulta',
  agenda_block: 'Bloqueio',
  appointment: 'Compromisso',
};

// Tons mais escuros no light (text-X-700) para WCAG AA;
// dark:text-X-400 mantém legibilidade em fundo escuro.
export const PRIORITY_CONFIG = {
  urgent: {
    label: 'Urgente',
    cls: 'bg-red-500/15 text-red-700 dark:text-red-400 border border-red-500/30',
    text: '!!!',
  },
  high: {
    label: 'Alta',
    cls: 'bg-red-500/15 text-red-700 dark:text-red-400 border border-red-500/30',
    text: '!!!',
  },
  medium: {
    label: 'Média',
    cls: 'bg-yellow-500/15 text-yellow-800 dark:text-yellow-300 border border-yellow-500/40',
    text: '!!',
  },
  low: {
    label: 'Baixa',
    cls: 'bg-slate-500/15 text-slate-700 dark:text-slate-400 border border-slate-500/30',
    text: '!',
  },
};

export const priorityCfg = p => PRIORITY_CONFIG[p] || PRIORITY_CONFIG.medium;

export const APPOINTMENT_STATUS_CONFIG = {
  scheduled: {
    label: 'Agendado',
    icon: 'i-lucide-calendar-clock',
    badgeCls:
      'bg-green-500/10 text-green-700 dark:text-green-400 border border-green-500/30',
  },
  confirmed: {
    label: 'Confirmado',
    icon: 'i-lucide-calendar-check',
    badgeCls:
      'bg-woot-500/10 text-woot-700 dark:text-woot-400 border border-woot-500/30',
  },
  arrived: {
    label: 'Presente',
    icon: 'i-lucide-user-check',
    badgeCls:
      'bg-violet-500/10 text-violet-700 dark:text-violet-400 border border-violet-500/30',
  },
  in_progress: {
    label: 'Em Atendimento',
    icon: 'i-lucide-stethoscope',
    badgeCls:
      'bg-yellow-500/15 text-yellow-800 dark:text-yellow-300 border border-yellow-500/40',
  },
  done: {
    label: 'Realizado',
    icon: 'i-lucide-check-circle-2',
    badgeCls:
      'bg-green-500/10 text-green-700 dark:text-green-400 border border-green-500/30',
  },
  no_show: {
    label: 'Falta',
    icon: 'i-lucide-user-x',
    badgeCls:
      'bg-yellow-500/15 text-yellow-800 dark:text-yellow-300 border border-yellow-500/40',
  },
  canceled: {
    label: 'Cancelado',
    icon: 'i-lucide-x-circle',
    badgeCls:
      'bg-red-500/10 text-red-700 dark:text-red-400 border border-red-500/30',
  },
  rescheduled: {
    label: 'Reagendado',
    icon: 'i-lucide-calendar-arrow-up',
    badgeCls:
      'bg-yellow-500/15 text-yellow-800 dark:text-yellow-300 border border-yellow-500/40',
  },
  deleted_user: {
    label: 'Cancelado pelo Usuário',
    icon: 'i-lucide-x-circle',
    badgeCls:
      'bg-red-500/10 text-red-700 dark:text-red-400 border border-red-500/30',
  },
  deleted_patient: {
    label: 'Cancelado pelo Paciente',
    icon: 'i-lucide-user-x',
    badgeCls:
      'bg-red-500/10 text-red-700 dark:text-red-400 border border-red-500/30',
  },
  deleted_reschedule: {
    label: 'Reagendado',
    icon: 'i-lucide-calendar-arrow-up',
    badgeCls:
      'bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/40',
  },
  deleted_other: {
    label: 'Excluído',
    icon: 'i-lucide-trash-2',
    badgeCls:
      'bg-slate-500/15 text-slate-700 dark:text-slate-300 border border-slate-500/30',
  },
};

export const aptStatusCfg = status =>
  APPOINTMENT_STATUS_CONFIG[status] || APPOINTMENT_STATUS_CONFIG.scheduled;
