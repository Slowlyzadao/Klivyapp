/**
 * useInstallmentBreakdown — helpers de UX pra mostrar modificadores
 * (juros/multa/desconto/crédito/parcial) em listas de installments.
 *
 * Backend (InstallmentsController#serialize) expõe:
 *   - has_modifiers (boolean)
 *   - is_partial_payment (boolean)
 *   - total_interest_cents
 *   - total_fine_cents
 *   - total_discount_cents
 *   - total_credit_applied_cents
 *   - amount_cents (original) + received_amount_cents
 *
 * Uso:
 *   import { hasBreakdown, breakdownTooltipLabel } from '@plugins/financial/.../useInstallmentBreakdown'
 *   <Tooltip v-if="hasBreakdown(inst)" :label="breakdownTooltipLabel(inst)">
 *     <i class="i-lucide-info" />
 *   </Tooltip>
 */
import { centsToBRL } from './useMoney';

// Retorna true se vale mostrar o ícone info — quando há modificador OU
// pagamento parcial OU múltiplos recibos. Critério único pra todas as telas.
export function hasBreakdown(inst) {
  if (!inst) return false;
  return Boolean(inst.has_modifiers) || Boolean(inst.is_partial_payment) || (inst.receipts_count || 0) > 1;
}

// Variante pra Entry do Fluxo de Caixa — backend expõe (de PaymentReceipt
// ou Expense source): has_modifiers, gross_amount_cents, interest_amount_cents,
// fine/discount/credit. Não tem `is_partial_payment` nem `receipts_count`
// (não aplicáveis ao Entry — Entry é o lançamento final, não a parcela).
export function entryHasBreakdown(entry) {
  if (!entry) return false;
  return Boolean(entry.has_modifiers);
}

// Tooltip pro Entry — breakdown bruto > juros > multa > desconto > crédito > líquido.
// Direção (in/out) afeta o label final (creditado vs debitado).
export function entryBreakdownTooltipLabel(entry) {
  if (!entry) return '';
  const lines = [];
  const gross = Number(entry.gross_amount_cents) || 0;
  const interest = Number(entry.interest_amount_cents) || 0;
  const fine = Number(entry.fine_amount_cents) || 0;
  const discount = Number(entry.discount_amount_cents) || 0;
  const credit = Number(entry.credit_applied_cents) || 0;
  const net = Number(entry.amount_cents) || 0;
  const isIn = entry.direction === 'in';

  lines.push(`Valor original: ${centsToBRL(gross)}`);
  if (interest > 0) lines.push(`+ Juros: ${centsToBRL(interest)}`);
  if (fine > 0) lines.push(`+ Multa: ${centsToBRL(fine)}`);
  if (discount > 0) lines.push(`− Desconto: ${centsToBRL(discount)}`);
  if (credit > 0) lines.push(`− Crédito do paciente: ${centsToBRL(credit)}`);
  lines.push(`${isIn ? 'Creditado' : 'Debitado'} na conta: ${centsToBRL(net)}`);

  return lines.join('\n');
}

// Label do tooltip — breakdown legível em linhas separadas (multiline).
// Ordem fixa: bruto > juros > multa > desconto > crédito > líquido.
// Mostra apenas linhas com valor != 0 pra evitar ruído.
export function breakdownTooltipLabel(inst) {
  if (!inst) return '';
  const lines = [];
  const original = Number(inst.amount_cents) || 0;
  const received = Number(inst.received_amount_cents) || 0;
  const interest = Number(inst.total_interest_cents) || 0;
  const fine = Number(inst.total_fine_cents) || 0;
  const discount = Number(inst.total_discount_cents) || 0;
  const credit = Number(inst.total_credit_applied_cents) || 0;

  lines.push(`Valor original: ${centsToBRL(original)}`);
  if (interest > 0) lines.push(`+ Juros: ${centsToBRL(interest)}`);
  if (fine > 0) lines.push(`+ Multa: ${centsToBRL(fine)}`);
  if (discount > 0) lines.push(`− Desconto: ${centsToBRL(discount)}`);
  if (credit > 0) lines.push(`− Crédito do paciente: ${centsToBRL(credit)}`);

  // Linha de status — partial / completo / pago a mais
  if (inst.is_partial_payment) {
    const remaining = original - received;
    lines.push(`Pago: ${centsToBRL(received)} (saldo: ${centsToBRL(remaining)})`);
  } else if (received > 0) {
    lines.push(`Recebido: ${centsToBRL(received)}`);
  }

  if ((inst.receipts_count || 0) > 1) {
    lines.push(`${inst.receipts_count} recibos vinculados`);
  }

  return lines.join('\n');
}
