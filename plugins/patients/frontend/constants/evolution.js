/**
 * Constants do módulo Evolução (procedimentos + evolução clínica unificados).
 */

export const BRT = 'America/Sao_Paulo';

export const DEFAULT_SESSION_DURATION_MINUTES = 30;

export const EVOLUTION_SUBTABS = Object.freeze({
  IN_PROGRESS: 'in_progress',
  CLINICAL_RECORD: 'clinical_record',
  EVOLUTION_HISTORY: 'evolution_history',
});

export const NOTE_TEMPLATE_OPTIONS = [
  { value: 'Evolução Padrão', label: 'Evolução Padrão' },
  { value: 'Primeira Consulta Estética', label: 'Primeira Consulta Estética' },
  { value: 'Revisão / Retorno', label: 'Revisão / Retorno' },
  { value: 'Sessão de Laser', label: 'Sessão de Laser' },
];

export const PRODUCT_UNIT_OPTIONS = [
  { value: 'un', label: 'un' },
  { value: 'ml', label: 'ml' },
  { value: 'mg', label: 'mg' },
  { value: 'g', label: 'g' },
  { value: 'U', label: 'U' },
  { value: 'gota', label: 'gota' },
];

export const SIGNATURE_CHANNELS = [
  { value: 'whatsapp', label: 'WhatsApp' },
  { value: 'sms', label: 'SMS' },
];

export const SIGNATURE_MODES = [
  { value: 'screen', label: 'Assinatura na Tela' },
  { value: 'link', label: 'Botão de Confirmação' },
];

const todayInBRT = () =>
  new Date().toLocaleDateString('en-CA', { timeZone: BRT });

export const blankSession = () => ({
  performed_at: todayInBRT(),
  procedure_name: '',
  complaint_of_day: '',
  assessment: '',
  next_consultation_details: '',
  observation: '',
  area_treated: '',
  product_name: '',
  quantity: '',
  unit: 'un',
  batch: '',
  product_expires_at: '',
  complications: '',
  result_observed: '',
  return_needed: false,
  return_in_days: null,
  duration_minutes: DEFAULT_SESSION_DURATION_MINUTES,
  treatment_item_id: null,
  treatment_plan_id: null,
  professional_id: null,
  status: 'draft',
});

export const blankSessionFilter = () => ({
  procedure_name: '',
  date_from: '',
  date_to: '',
});

// `mode='link'` é o default desde [1.5.4.0] — link compartilhado é o único
// fluxo 100% funcional. `screen` é o fallback pra quando o paciente está
// presente fisicamente (assina no tablet do médico).
export const blankSignatureRequest = () => ({
  phone: '',
  channel: 'whatsapp',
  mode: 'link',
});
