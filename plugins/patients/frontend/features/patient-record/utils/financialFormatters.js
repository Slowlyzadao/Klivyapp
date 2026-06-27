/**
 * Helpers de formatação financeira (BRL).
 *
 * Extraído de FinancialTab.vue (Roadmap #11).
 */

export const formatCurrency = value => {
  if (!value) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(value);
};

export const formatCurrencyInput = val => {
  const num = parseFloat(String(val).replace(/\./g, '').replace(',', '.'));
  if (Number.isNaN(num)) return '';
  return num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};

export const parseCurrencyInput = val => {
  const cleaned = String(val).replace(/\./g, '').replace(',', '.');
  const num = parseFloat(cleaned);
  return Number.isNaN(num) ? 0 : num;
};

// Mascara de input em centavos: digita só dígitos, vê "1.234,56".
// Retorna a string formatada e atribui no target — mantém compat. com
// chamada original `@input="onSubtotalInput"`.
export const onSubtotalInput = (event, subtotalRefValue) => {
  const raw = event.target.value.replace(/\D/g, '');
  const cents = parseInt(raw || '0', 10);
  const num = cents / 100;
  const formatted = num.toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  // eslint-disable-next-line no-param-reassign
  event.target.value = formatted;
  if (subtotalRefValue && 'value' in subtotalRefValue) {
    subtotalRefValue.value = formatted;
  }
  return formatted;
};
