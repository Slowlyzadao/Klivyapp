// CPF helpers — validação e formatação.
// Usado em qualquer plugin que aceita CPF (patients, financial, etc).

// Remove tudo que não é dígito.
export const onlyDigits = value => String(value || '').replace(/\D/g, '');

// Aplica máscara DDD.DDD.DDD-DD durante digitação. Aceita strings parciais.
export const maskCPF = raw => {
  const digits = onlyDigits(raw).slice(0, 11);
  if (digits.length <= 3) return digits;
  if (digits.length <= 6) return `${digits.slice(0, 3)}.${digits.slice(3)}`;
  if (digits.length <= 9) {
    return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6)}`;
  }
  return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`;
};

// Formata CPF completo. Retorna a entrada original se inválido (não força).
export const formatCPF = value => {
  const digits = onlyDigits(value);
  if (digits.length !== 11) return value;
  return `${digits.slice(0, 3)}.${digits.slice(3, 6)}.${digits.slice(6, 9)}-${digits.slice(9)}`;
};

/**
 * Valida CPF pelo algoritmo do dígito verificador (módulo 11).
 *
 * Retorna `true` se o CPF for matematicamente válido. NÃO valida se existe
 * de verdade na Receita — só rejeita strings óbvias (000.000.000-00,
 * 111.111.111-11, etc) e CPFs com dígito verificador errado.
 *
 * Aceita string com ou sem máscara, ou números puros.
 */
export const isValidCPF = value => {
  const digits = onlyDigits(value);
  if (digits.length !== 11) return false;
  // Rejeita CPFs com todos os dígitos iguais (000.000.000-00 a 999.999.999-99)
  if (/^(\d)\1{10}$/.test(digits)) return false;

  const calcCheckDigit = (slice, weightStart) => {
    let sum = 0;
    for (let i = 0; i < slice.length; i += 1) {
      sum += Number(slice[i]) * (weightStart - i);
    }
    const remainder = (sum * 10) % 11;
    return remainder === 10 ? 0 : remainder;
  };

  const firstCheck = calcCheckDigit(digits.slice(0, 9), 10);
  if (firstCheck !== Number(digits[9])) return false;

  const secondCheck = calcCheckDigit(digits.slice(0, 10), 11);
  if (secondCheck !== Number(digits[10])) return false;

  return true;
};
