/**
 * Constants do módulo Cadastro do paciente.
 *
 * Extraído de RegistrationTab.vue (Roadmap #11). Options arrays usados em
 * FormSelect — labels textuais ficam em pt-BR fixo (são valores semânticos
 * do backend); strings de UI e títulos de seções vão em
 * `app/javascript/dashboard/i18n/locale/{lang}/patientRegistration.json`.
 */

export const SEX_OPTIONS = [
  { value: 'feminino', label: 'Feminino' },
  { value: 'masculino', label: 'Masculino' },
  { value: 'outro', label: 'Outro' },
  { value: 'nao_informado', label: 'Não Informado' },
];

export const MARITAL_STATUS_OPTIONS = [
  { value: 'solteiro', label: 'Solteiro(a)' },
  { value: 'casado', label: 'Casado(a)' },
  { value: 'divorciado', label: 'Divorciado(a)' },
  { value: 'viuvo', label: 'Viúvo(a)' },
];

export const GUARDIAN_RELATIONSHIP_OPTIONS = [
  { value: 'pai', label: 'Pai' },
  { value: 'mae', label: 'Mãe' },
  { value: 'tutor', label: 'Tutor(a)' },
  { value: 'conjuge', label: 'Cônjuge' },
  { value: 'filho', label: 'Filho(a)' },
  { value: 'irmao', label: 'Irmão / Irmã' },
  { value: 'amigo', label: 'Amigo(a)' },
  { value: 'outro', label: 'Outro' },
];

export const UF_OPTIONS = [
  'AC','AL','AM','AP','BA','CE','DF','ES','GO','MA','MG','MS','MT',
  'PA','PB','PE','PI','PR','RJ','RN','RO','RR','RS','SC','SE','SP','TO',
].map(uf => ({ value: uf, label: uf }));

export const INSURANCE_OPTIONS = [
  { value: 'Particular', label: 'Particular' },
  { value: 'Bradesco Saúde', label: 'Bradesco Saúde' },
  { value: 'SulAmérica', label: 'SulAmérica' },
  { value: 'Amil', label: 'Amil' },
  { value: 'Unimed', label: 'Unimed' },
  { value: 'Porto Seguro', label: 'Porto Seguro' },
];

// Paleta determinística para avatares sem imagem (hash do nome → cor).
export const AVATAR_PALETTE = [
  '#6366f1', '#8b5cf6', '#ec4899', '#f43f5e',
  '#f97316', '#22c55e', '#14b8a6', '#3b82f6',
];
