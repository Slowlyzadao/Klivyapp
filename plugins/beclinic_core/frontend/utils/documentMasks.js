/**
 * Máscaras de documento brasileiro (CPF / CNPJ) — utilitário compartilhado.
 *
 * Fonte ÚNICA de verdade pra mascarar CPF/CNPJ no app. Antes a lógica de CPF
 * vivia só em `plugins/patients/.../registrationMasks.js`; foi promovida aqui
 * (beclinic_core = camada base) pra que financeiro (perfil do profissional PJ)
 * e pacientes reusem o mesmo código, sem duplicar.
 *
 * Funções puras e idempotentes (rodar sobre valor já formatado é seguro):
 * recebem o valor bruto e retornam a string formatada. O caller decide onde
 * gravar. O backend normaliza pra dígitos de qualquer forma.
 *
 *   maskCpf('12345678900')  → '123.456.789-00'
 *   maskCnpj('11222333000181') → '11.222.333/0001-81'
 *   maskDocument(v, { pj: true })  → CNPJ ; { pj: false } → CPF
 */

// CPF: 000.000.000-00 (11 dígitos). Lógica idêntica à original do cadastro de
// paciente — preservada ao mover pra cá pra não regredir aquele fluxo.
export const maskCpf = raw => {
  let value = String(raw || '').replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    return value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  }
  if (value.length > 6) {
    return value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  }
  if (value.length > 3) {
    return value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  return value;
};

// CNPJ: 00.000.000/0000-00 (14 dígitos).
export const maskCnpj = raw => {
  let value = String(raw || '').replace(/\D/g, '');
  if (value.length > 14) value = value.slice(0, 14);
  if (value.length > 12) {
    return value.replace(/(\d{2})(\d{3})(\d{3})(\d{4})(\d{1,2})/, '$1.$2.$3/$4-$5');
  }
  if (value.length > 8) {
    return value.replace(/(\d{2})(\d{3})(\d{3})(\d{1,4})/, '$1.$2.$3/$4');
  }
  if (value.length > 5) {
    return value.replace(/(\d{2})(\d{3})(\d{1,3})/, '$1.$2.$3');
  }
  if (value.length > 2) {
    return value.replace(/(\d{2})(\d{1,3})/, '$1.$2');
  }
  return value;
};

// Escolhe a máscara pelo tipo de pessoa: PJ → CNPJ, senão CPF.
export const maskDocument = (raw, { pj = false } = {}) => (pj ? maskCnpj(raw) : maskCpf(raw));

// Telefone BR: (00) 00000-0000 (celular) / (00) 0000-0000 (fixo). Promovido do
// cadastro de paciente pra cá (fonte única) — lógica idêntica, sem regressão.
// Aceita prefixo 55 (E.164) e descarta. registrationMasks re-exporta daqui.
export const maskPhone = raw => {
  let value = String(raw || '').replace(/\D/g, '');
  if (value.startsWith('55')) value = value.slice(2);
  if (value.length > 11) value = value.slice(0, 11);

  if (value.length > 10) {
    return value.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  }
  if (value.length > 6) {
    return value.replace(/(\d{2})(\d{4,5})(\d{0,4})/, '($1) $2-$3');
  }
  if (value.length > 2) {
    return value.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  }
  if (value.length > 0) {
    return value.replace(/(\d{0,2})/, '($1');
  }
  return '';
};

// CEP: 00000-000 (8 dígitos).
export const maskCep = raw => {
  let value = String(raw || '').replace(/\D/g, '');
  if (value.length > 8) value = value.slice(0, 8);
  if (value.length > 5) {
    return value.replace(/(\d{5})(\d{1,3})/, '$1-$2');
  }
  return value;
};
