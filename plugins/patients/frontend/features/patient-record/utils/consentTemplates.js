/**
 * fillConsentTemplate — substitui placeholders do template do consent type
 * pelos dados do paciente.
 *
 * Placeholders suportados (case-sensitive, com colchetes):
 *   [NOME DO PACIENTE], [NOME DO RESPONSÁVEL], [CPF],
 *   [DATA DE NASCIMENTO], [ENDEREÇO], [RG], [EMAIL], [TELEFONE]
 *
 * Campos faltando viram '________________' (espaço pra preenchimento manual).
 *
 * Extraído de ConsentsTab.vue (Roadmap #11).
 */

const FALLBACK = '________________';
const BRT = 'America/Sao_Paulo';

const formatPatientCpf = cpf => {
  if (!cpf) return FALLBACK;
  return String(cpf).replace(
    /(\d{3})(\d{3})(\d{3})(\d{2})/,
    '$1.$2.$3-$4'
  );
};

const formatPatientBirthdate = birthdate => {
  if (!birthdate) return FALLBACK;
  try {
    const d = new Date(birthdate);
    return d.toLocaleDateString('pt-BR', { timeZone: BRT });
  } catch {
    // Fallback intencional: se o parse falhar, mostra o raw em vez de quebrar.
    return birthdate;
  }
};

const formatPatientAddress = address => {
  if (!address) return FALLBACK;
  const parts = [
    address.street,
    address.number,
    address.complement,
    address.neighborhood,
    address.city,
    address.state,
    address.zip,
  ];
  const joined = parts.filter(Boolean).join(', ');
  return joined || FALLBACK;
};

export const fillConsentTemplate = (template, patient) => {
  if (!template) return '';
  const p = patient || {};
  return template
    .replace('[NOME DO PACIENTE]', p.name || FALLBACK)
    .replace('[NOME DO RESPONSÁVEL]', FALLBACK)
    .replace('[CPF]', formatPatientCpf(p.cpf))
    .replace('[DATA DE NASCIMENTO]', formatPatientBirthdate(p.birthdate))
    .replace('[ENDEREÇO]', formatPatientAddress(p.address))
    .replace('[RG]', p.rg || FALLBACK)
    .replace('[EMAIL]', p.email || FALLBACK)
    .replace('[TELEFONE]', p.phone || FALLBACK);
};
