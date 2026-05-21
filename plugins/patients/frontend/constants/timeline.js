/**
 * Constants do módulo Timeline.
 * Extraído de TimelineTab.vue (Roadmap #11).
 */

export const BRT = 'America/Sao_Paulo';

export const TIMELINE_TYPE_CONFIG = {
  cadastro: { icon: 'i-lucide-user-plus', color: 'indigo', label: 'Cadastro' },
  anamnesis_filled: { icon: 'i-lucide-clipboard-list', color: 'blue', label: 'Anamnese' },
  appointment_scheduled: { icon: 'i-lucide-calendar-plus', color: 'orange', label: 'Agendamento' },
  appointment_rescheduled: { icon: 'i-lucide-calendar-clock', color: 'yellow', label: 'Reagendamento' },
  appointment_done: { icon: 'i-lucide-calendar-check', color: 'emerald', label: 'Consulta Realizada' },
  appointment_no_show: { icon: 'i-lucide-user-x', color: 'red', label: 'Falta' },
  appointment_canceled: { icon: 'i-lucide-calendar-x', color: 'rose', label: 'Cancelamento' },
  clinical_note: { icon: 'i-lucide-stethoscope', color: 'cyan', label: 'Evolução Clínica' },
  session_performed: { icon: 'i-lucide-activity', color: 'teal', label: 'Sessão Realizada' },
  exam_uploaded: { icon: 'i-lucide-image', color: 'violet', label: 'Exame/Imagem' },
  document_generated: { icon: 'i-lucide-file-text', color: 'sky', label: 'Documento' },
  consent_signed: { icon: 'i-lucide-file-signature', color: 'purple', label: 'Consentimento Assinado' },
  consent_revoked: { icon: 'i-lucide-file-x', color: 'rose', label: 'Consentimento Revogado' },
  consent_expired: { icon: 'i-lucide-clock-x', color: 'amber', label: 'Consentimento Vencido' },
  document_deleted: { icon: 'i-lucide-file-x', color: 'rose', label: 'Documento Removido' },
  treatment_plan_created: { icon: 'i-lucide-target', color: 'indigo', label: 'Plano de Tratamento Criado' },
  treatment_plan_approved: { icon: 'i-lucide-check-circle', color: 'emerald', label: 'Plano de Tratamento Aprovado' },
  treatment_plan_archived: { icon: 'i-lucide-archive', color: 'slate', label: 'Plano de Tratamento Arquivado' },
  payment: { icon: 'i-lucide-circle-dollar-sign', color: 'green', label: 'Pagamento' },
  refund: { icon: 'i-lucide-receipt', color: 'amber', label: 'Reembolso' },
  status_changed: { icon: 'i-lucide-refresh-cw', color: 'slate', label: 'Status Alterado' },
  discharge: { icon: 'i-lucide-log-out', color: 'lime', label: 'Alta Médica' },
  recall_sent: { icon: 'i-lucide-bell', color: 'yellow', label: 'Recall Enviado' },
};

export const timelineEventConfig = eventType =>
  TIMELINE_TYPE_CONFIG[eventType] ?? {
    icon: 'i-lucide-activity',
    color: 'slate',
    label: eventType,
  };

// Categorias dos filtros — quais event_types entram em cada filtro.
export const FILTER_CATEGORIES = {
  clinical: [
    'clinical_note',
    'anamnesis_filled',
    'session_performed',
    'treatment_plan_created',
    'treatment_plan_approved',
    'treatment_plan_archived',
  ],
  financial: ['payment', 'refund'],
  documents: [
    'document_generated',
    'document_deleted',
    'consent_signed',
    'consent_revoked',
    'consent_expired',
    'exam_uploaded',
  ],
};

export const matchesFilter = (event, filter) => {
  if (filter === 'all') return true;
  if (filter === 'appointments') {
    return event.event_type?.startsWith('appointment');
  }
  return FILTER_CATEGORIES[filter]?.includes(event.event_type) || false;
};
