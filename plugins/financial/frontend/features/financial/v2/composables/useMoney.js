/**
 * Helpers para trabalhar com valores em centavos (BIGINT vindo do backend v2).
 * Canon Parte 6 §"Valores em centavos".
 */

const BRL_FORMATTER = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
  minimumFractionDigits: 2,
  maximumFractionDigits: 2,
});

/** centsToBRL(92000) → "R$ 920,00" */
export const centsToBRL = (cents) => {
  if (cents === null || cents === undefined) return '—';
  const n = typeof cents === 'string' ? Number.parseInt(cents, 10) : cents;
  if (!Number.isFinite(n)) return '—';
  return BRL_FORMATTER.format(n / 100);
};

/** brlInputToCents("920,00") → 92000 — aceita string com vírgula ou ponto. */
export const brlInputToCents = (input) => {
  if (input === null || input === undefined || input === '') return 0;
  if (typeof input === 'number') return Math.round(input * 100);
  const cleaned = String(input)
    .replace(/[^\d,.-]/g, '')
    .replace(/\./g, '')
    .replace(',', '.');
  const value = Number.parseFloat(cleaned);
  if (!Number.isFinite(value)) return 0;
  return Math.round(value * 100);
};

/**
 * centsToInputString(92000) → "920,00"
 * centsToInputString(1234567) → "12.345,67"
 *
 * Para popular <input type="text"> de dinheiro. Usa toLocaleString pra
 * incluir separador de milhar (consistente com `formatCurrencyInput` que
 * o usuário enxerga ao digitar — sem flicker quando o valor inicial é
 * grande, ex.: parcela de R$ 12.345,00 pré-preenchida).
 */
export const centsToInputString = (cents) => {
  if (cents === null || cents === undefined) return '';
  const n = typeof cents === 'string' ? Number.parseInt(cents, 10) : cents;
  if (!Number.isFinite(n)) return '';
  return (n / 100).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};

/**
 * Mapeia o `kind` interno de Financial::BankAccount pra label PT-BR.
 * Centralizado aqui porque vários modais (ManualEntry, PayExpense,
 * ReceivePayment) montam dropdown de "Conta destino" e antes mostravam
 * o kind cru ("checking" — confunde o operador).
 */
export const bankKindLabel = (kind) => {
  const MAP = {
    checking:         'Conta corrente',
    savings:          'Poupança',
    cash:             'Caixa físico',
    card_receivable:  'Maquininha',
  };
  return MAP[kind] || kind || '—';
};

/**
 * Live formatter pra inputs de dinheiro: usuário digita só dígitos e o
 * valor aparece formatado com vírgula decimal + ponto de milhar.
 *
 *   "100"       → "1,00"
 *   "12345"     → "123,45"
 *   "1234567"   → "12.345,67"
 *
 * Uso:
 *   <input @input="(e) => myStr = formatCurrencyInput(e.target.value)" />
 *   ou no padrão "v-model + @input bridge":
 *     <input :value="myStr" @input="(e) => myStr = formatCurrencyInput(e.target.value)" />
 *
 * Mesma lógica de `onSubtotalInput` em
 * plugins/patients/frontend/features/patient-record/utils/financialFormatters.js,
 * mas isolada do DOM event pra ser usada como helper puro.
 */
export const formatCurrencyInput = (rawValue) => {
  const digits = String(rawValue ?? '').replace(/\D/g, '');
  if (!digits) return '';
  const cents = parseInt(digits, 10);
  return (cents / 100).toLocaleString('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
};

/**
 * Distribui um total em N parcelas, colocando o resto na ÚLTIMA.
 * Espelha Financial::Concerns::MoneyAttribute.split.
 *
 * splitCents(92000, 3) → [30666, 30666, 30668]
 */
export const splitCents = (totalCents, count) => {
  if (count <= 0) throw new Error('count must be > 0');
  if (count === 1) return [totalCents];
  const base = Math.floor(totalCents / count);
  const remainder = totalCents - base * count;
  return [...Array(count - 1).fill(base), base + remainder];
};

export default {
  centsToBRL,
  brlInputToCents,
  centsToInputString,
  splitCents,
};
