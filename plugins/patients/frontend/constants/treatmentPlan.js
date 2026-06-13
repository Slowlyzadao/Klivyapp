/**
 * Constants do módulo Plano de Tratamento.
 *
 * Extraído de TreatmentPlanTab.vue (Roadmap #11). Status do TreatmentItem
 * mapeado para badge visual — backend evolui automaticamente:
 *   proposto → em_execucao (ao registrar 1ª sessão linkada)
 *   → concluido (todas as sessões registradas)
 */

export const ITEM_STATUS_CONFIG = {
  proposto: { label: 'Proposto', cls: 'rp-status--blue' },
  aprovado: { label: 'Aprovado', cls: 'rp-status--green' },
  approved: { label: 'Aprovado', cls: 'rp-status--green' },
  em_execucao: { label: 'Em execução', cls: 'rp-status--amber' },
  concluido: { label: 'Concluído', cls: 'rp-status--teal' },
  cancelado: { label: 'Cancelado', cls: 'rp-status--slate' },
};

export const itemStatusConfig = item => {
  return (
    ITEM_STATUS_CONFIG[item.status] || {
      label: item.status || '—',
      cls: 'rp-status--blue',
    }
  );
};

export const itemSessionProgress = item => {
  const planned = Number(item.sessions_planned) || 0;
  const done = Number(item.sessions_done) || 0;
  if (planned <= 0) return 0;
  return Math.min(100, Math.round((done / planned) * 100));
};

// Subtotal antes do desconto.
export const itemGrossSubtotal = item =>
  (Number(item.unit_price) || 0) * (Number(item.sessions_planned) || 1);

// Desconto aplicado: percentual sobre o bruto OU valor fixo (limitado ao bruto).
export const itemDiscountAmount = item => {
  const value = Number(item.discount_value) || 0;
  if (value <= 0 || !item.discount_type) return 0;
  const gross = itemGrossSubtotal(item);
  if (item.discount_type === 'percentual') return gross * (value / 100);
  return Math.min(value, gross);
};

// Subtotal final exibido na tabela e somado no total do plano. Espelha o
// `net_subtotal` calculado no backend (TreatmentItem#net_subtotal).
export const itemSubtotal = item =>
  Math.max(itemGrossSubtotal(item) - itemDiscountAmount(item), 0);

export const planTotal = plan =>
  (plan.treatment_items || []).reduce((sum, item) => sum + itemSubtotal(item), 0);
