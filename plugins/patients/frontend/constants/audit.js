/**
 * Constants do módulo Auditoria.
 *
 * Extraído de AuditTab.vue (Roadmap #11). `clinical_override` (Roadmap #16.1)
 * gravado pelo session_logs/treatment_items_controller.
 */

export const BRT = 'America/Sao_Paulo';

export const AUDIT_ACTIONS = [
  'view',
  'create',
  'update',
  'delete',
  'sign',
  'export',
  'finalize',
  'approve',
  'pay',
  'print',
  'clinical_override',
];

// Tons text-X-700 no light mode + dark:text-X-400 — alinhado com WCAG AA.
export const AUDIT_ACTION_CONFIG = {
  view: {
    label: 'VISUALIZAÇÃO',
    color:
      'bg-slate-500/10 text-slate-700 dark:text-slate-300 border border-slate-500/30',
    icon: 'i-lucide-eye',
  },
  create: {
    label: 'CRIAÇÃO',
    color:
      'bg-emerald-500/10 text-emerald-700 dark:text-emerald-400 border border-emerald-500/30',
    icon: 'i-lucide-plus',
  },
  update: {
    label: 'EDIÇÃO',
    color:
      'bg-blue-500/10 text-blue-700 dark:text-blue-400 border border-blue-500/30',
    icon: 'i-lucide-edit-2',
  },
  delete: {
    label: 'EXCLUSÃO',
    color: 'bg-red-500/10 text-red-700 dark:text-red-400 border border-red-500/30',
    icon: 'i-lucide-trash-2',
  },
  sign: {
    label: 'ASSINATURA',
    color:
      'bg-violet-500/10 text-violet-700 dark:text-violet-400 border border-violet-500/30',
    icon: 'i-lucide-pen-tool',
  },
  export: {
    label: 'EXPORTAÇÃO',
    color:
      'bg-amber-500/10 text-amber-700 dark:text-amber-400 border border-amber-500/30',
    icon: 'i-lucide-download',
  },
  finalize: {
    label: 'FINALIZAÇÃO',
    color:
      'bg-indigo-500/10 text-indigo-700 dark:text-indigo-400 border border-indigo-500/30',
    icon: 'i-lucide-check-circle',
  },
  approve: {
    label: 'APROVAÇÃO',
    color:
      'bg-teal-500/10 text-teal-700 dark:text-teal-400 border border-teal-500/30',
    icon: 'i-lucide-thumbs-up',
  },
  pay: {
    label: 'PAGAMENTO',
    color:
      'bg-green-500/10 text-green-700 dark:text-green-400 border border-green-500/30',
    icon: 'i-lucide-circle-dollar-sign',
  },
  print: {
    label: 'IMPRESSÃO',
    color:
      'bg-cyan-500/10 text-cyan-700 dark:text-cyan-400 border border-cyan-500/30',
    icon: 'i-lucide-printer',
  },
  clinical_override: {
    label: 'OVERRIDE CLÍNICO',
    color:
      'bg-amber-500/15 text-amber-800 dark:text-amber-300 border border-amber-500/40',
    icon: 'i-lucide-shield-alert',
  },
};

export const auditActionConfig = action =>
  AUDIT_ACTION_CONFIG[action] || {
    label: (action || 'AÇÃO').toUpperCase(),
    color:
      'bg-slate-500/10 text-slate-700 dark:text-slate-300 border border-slate-500/30',
    icon: 'i-lucide-activity',
  };

// Tradução para nomes amigáveis dos resource_type. Backend grava com nome
// da AR class (Anamnesis/TreatmentPlan/etc.).
export const RESOURCE_TYPE_LABELS = {
  Anamnesis: 'Anamnese',
  TreatmentPlan: 'Plano de Tratamento',
  TreatmentItem: 'Procedimento',
  ClinicalNote: 'Evolução/Nota Clínica',
  FinancialEstimate: 'Orçamento',
  Transaction: 'Transação Financeira',
  Patient: 'Cadastro do Paciente',
  ExamMedia: 'Exame/Mídia',
  Document: 'Documento',
  ConsentRecord: 'Consentimento',
  SessionLog: 'Sessão de Procedimento',
  Recall: 'Recall',
  CriticalAlert: 'Alerta Crítico',
};

export const blankAuditFilters = () => ({
  action_type: '',
  actor_id: '',
  start_date: '',
  end_date: '',
  page: 1,
});

export const PAGE_SIZE = 15;
