// Mapping legível dos document_types suportados pelo modelo backend.
// Source da verdade vive em DocumentTemplate::DOCUMENT_TYPES (Ruby).
// Mantemos esse espelho aqui SÓ pra labels do UI. Quando adicionar tipo
// novo, atualizar os dois lados.

export const CLINICAL_TYPE_LABELS = {
  receita: 'Receita',
  atestado: 'Atestado',
  pedido_exame: 'Pedido de exame',
  declaracao: 'Declaração',
  relatorio_clinico: 'Relatório clínico',
  encaminhamento: 'Encaminhamento',
  contrato: 'Contrato',
  orcamento: 'Orçamento',
  instrucao_procedimento: 'Instrução de procedimento',
  questionario: 'Questionário',
  outro: 'Outro',
};

export const CONSENT_TYPE_LABELS = {
  consentimento_geral: 'Consentimento geral',
  consentimento_lgpd: 'Termo LGPD',
  consentimento_imagem: 'Autorização de uso de imagem',
  consentimento_toxina: 'Consent. — Toxina botulínica',
  consentimento_preenchimento: 'Consent. — Preenchimento',
  consentimento_laser: 'Consent. — Laser',
  consentimento_fototerapia_led: 'Consent. — Fototerapia LED',
  consentimento_peeling: 'Consent. — Peeling',
  consentimento_dermoabrasao: 'Consent. — Dermoabrasão',
  consentimento_menor: 'Autorização — Paciente menor',
  consentimento_cirurgico: 'Consent. — Cirurgia',
  consentimento_anestesia: 'Consent. — Anestesia',
};

export const DOCUMENT_TYPE_LABELS = {
  ...CLINICAL_TYPE_LABELS,
  ...CONSENT_TYPE_LABELS,
};

export const labelFor = (type) => DOCUMENT_TYPE_LABELS[type] || type;

export const isConsent = (type) => Object.prototype.hasOwnProperty.call(CONSENT_TYPE_LABELS, type);
