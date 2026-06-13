/**
 * Constants do módulo Anamnese.
 *
 * Extraído de AnamnesisTab.vue (Roadmap #11). Options arrays usados em
 * FormSelects — labels textuais ficam em pt-BR fixo (são valores
 * semânticos persistidos no JSONB).
 */

export const SPECIALTY_OPTIONS = [
  { value: 'Odontologia Geral', label: 'Odontologia Geral' },
  { value: 'Estética Facial', label: 'Estética Facial' },
  { value: 'Dermatologia', label: 'Dermatologia' },
  { value: 'Avaliação Clínica', label: 'Avaliação Clínica' },
];

export const SMOKER_OPTIONS = [
  { value: 'Não', label: 'Não' },
  { value: 'Sim, regular', label: 'Sim, regular' },
  { value: 'Sim, socialmente', label: 'Sim, socialmente' },
  { value: 'Ex-fumante', label: 'Ex-fumante' },
];

export const ALCOHOL_OPTIONS = [
  { value: 'Não consome', label: 'Não consome' },
  { value: 'Ocasionalmente', label: 'Ocasionalmente' },
  { value: 'Frequentemente', label: 'Frequentemente' },
];

export const SPORTS_OPTIONS = [
  { value: 'Sedentário', label: 'Sedentário' },
  { value: 'Atividade moderada', label: 'Atividade moderada' },
  { value: 'Atleta / Alta intensidade', label: 'Atleta / Alta intensidade' },
];

// Campos que o backend não permite via strong params — removidos antes do
// PATCH/POST. `pdf_url` é só leitura (gerado ao finalizar).
export const UNPERMITTED_ANAMNESIS_KEYS = [
  'id',
  'status',
  'version_number',
  'account_id',
  'patient_id',
  'professional_id',
  'finalized_at',
  'created_at',
  'updated_at',
  'pdf_url',
];
