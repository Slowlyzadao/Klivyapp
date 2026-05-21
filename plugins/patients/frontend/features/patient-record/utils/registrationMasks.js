/**
 * Máscaras e formatadores do cadastro do paciente.
 *
 * Extraído de RegistrationTab.vue (Roadmap #11). Consolida 7+ duplicações
 * de máscaras inline (handleCpfInput / handleGuardianCpfInput;
 * handlePhoneInput / handleAlternativePhoneInput / handleGuardianPhoneInput;
 * formatCpfDisplay / formatRgDisplay / formatPhoneDisplay).
 *
 * Funções puras: recebem value bruto, retornam string formatada. Nenhum
 * efeito colateral — caller decide onde gravar.
 */

import { AVATAR_PALETTE } from '@plugins/patients/frontend/constants/registration';

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

export const maskRg = raw => {
  let value = String(raw || '')
    .replace(/[^a-zA-Z0-9]/g, '')
    .toUpperCase();
  if (value.length > 9) value = value.slice(0, 9);
  if (value.length > 8) {
    return value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3-$4'
    );
  }
  if (value.length > 5) {
    return value.replace(
      /^([a-zA-Z0-9]{2})([a-zA-Z0-9]{3})([a-zA-Z0-9]{1,})/,
      '$1.$2.$3'
    );
  }
  if (value.length > 2) {
    return value.replace(/^([a-zA-Z0-9]{2})([a-zA-Z0-9]{1,})/, '$1.$2');
  }
  return value;
};

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

// Formatters para display de valores já gravados (DB) — mais permissivos:
// só formatam se reconhecem o tamanho, retornam original se inesperado.
export const formatPhoneDisplay = phoneStr => {
  if (!phoneStr) return '';
  let val = String(phoneStr).replace(/\D/g, '');
  if (val.startsWith('55')) val = val.slice(2);
  if (val.length === 11) {
    return val.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  }
  if (val.length === 10) {
    return val.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  }
  return phoneStr;
};

// Para display, alias do mask (idempotente para valores parciais).
export const formatCpfDisplay = maskCpf;
export const formatRgDisplay = maskRg;

// Hash determinístico nome → cor para avatares fallback.
export const phoneContactColor = name => {
  if (!name) return AVATAR_PALETTE[0];
  let h = 0;
  for (let i = 0; i < name.length; i += 1) {
    h = name.charCodeAt(i) + (h * 32 - h);
  }
  return AVATAR_PALETTE[Math.abs(h) % AVATAR_PALETTE.length];
};

// Iniciais do nome para placeholder do avatar.
export const getInitials = name => {
  if (!name) return '';
  return name.charAt(0).toUpperCase();
};
