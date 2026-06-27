<script setup>
/**
 * Sumário agregado da simulação do plano de pagamento.
 * Lê `totals` da resposta de POST /budgets/:id/simulate_plan e mostra:
 *   - Bruto total
 *   - Total de taxa
 *   - Líquido total (= bruto - taxa)
 *   - Comissão estimada (sobre a base configurada na CommissionRule)
 *   - Contagem de parcelas
 *   - Aviso se nem todas as fees foram resolvidas
 */
import { centsToBRL } from '../../composables/useMoney';

defineProps({
  // Resposta data.totals do backend
  totals: { type: Object, required: true },
  // Total alvo do budget — pra checar se soma bate
  budgetTotalCents: { type: Number, default: 0 },
});
</script>

<template>
  <div class="net-card">
    <!-- Quando há passthrough: mostra "Cliente paga" e "Clínica recebe" separados.
         Quando não há (modelo absorb): mostra "Bruto / Taxas / Líquido" tradicional. -->
    <template v-if="totals.has_passthrough_rows">
      <div class="row">
        <span class="label">
          <i class="i-lucide-credit-card w-3 h-3" />
          Cliente paga
        </span>
        <span class="value">{{ centsToBRL(totals.total_amount_for_patient_cents) }}</span>
      </div>

      <div class="row muted-sub">
        <span class="label">
          Inclui taxa (MDR) repassada
        </span>
        <span class="value negative">− {{ centsToBRL(totals.total_fee_cents) }}</span>
      </div>

      <div class="row emphasis">
        <span class="label">Clínica recebe</span>
        <span class="value">{{ centsToBRL(totals.total_net_cents) }}</span>
      </div>
    </template>

    <template v-else>
      <div class="row">
        <span class="label">Total bruto</span>
        <span class="value">{{ centsToBRL(totals.gross_cents) }}</span>
      </div>

      <div class="row" :class="{ muted: totals.total_fee_cents === 0 }">
        <span class="label">
          <i class="i-lucide-minus w-3 h-3" />
          Taxas (clínica absorve)
        </span>
        <span class="value negative">
          {{ totals.total_fee_cents > 0 ? '−' : '' }} {{ centsToBRL(totals.total_fee_cents) }}
        </span>
      </div>

      <div class="row emphasis">
        <span class="label">Clínica recebe</span>
        <span class="value">{{ centsToBRL(totals.total_net_cents) }}</span>
      </div>
    </template>

    <div v-if="totals.expected_commission_cents > 0" class="row commission">
      <span class="label">
        <i class="i-lucide-user-check w-3 h-3" />
        Comissão estimada
      </span>
      <span class="value">{{ centsToBRL(totals.expected_commission_cents) }}</span>
    </div>

    <div class="row footer">
      <span class="label">{{ totals.installments_count }} parcela(s)</span>
      <span v-if="!totals.all_fees_resolved" class="warn-pill">
        <i class="i-lucide-alert-circle w-3 h-3" />
        Sem taxa cadastrada em parte das parcelas
      </span>
    </div>

    <div v-if="budgetTotalCents > 0 && totals.total_net_cents !== budgetTotalCents" class="mismatch">
      <i class="i-lucide-alert-triangle w-4 h-4" />
      Clínica recebe {{ centsToBRL(totals.total_net_cents) }} mas total do orçamento é
      {{ centsToBRL(budgetTotalCents) }}.
    </div>
  </div>
</template>

<style scoped lang="scss">
.net-card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 10px;
  padding: 16px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  font-size: 14px;
}

.row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;

  .label {
    display: inline-flex; align-items: center; gap: 6px;
    color: rgb(var(--slate-11));
  }
  .value {
    font-variant-numeric: tabular-nums;
    color: rgb(var(--slate-12));
    font-weight: 500;
  }
  .value.negative { color: rgb(var(--ruby-11)); }

  &.emphasis {
    padding: 10px 0;
    border-top: 1px solid rgb(var(--slate-4));
    border-bottom: 1px solid rgb(var(--slate-4));
    .label, .value {
      font-weight: 600;
      font-size: 16px;
      color: rgb(var(--blue-11));
    }
  }

  &.commission .value {
    color: rgb(var(--amber-11));
  }

  &.muted { opacity: 0.6; }
  &.muted-sub {
    padding-left: 16px;
    font-size: 12px;
    .label { color: rgb(var(--slate-10)); }
  }

  &.footer {
    margin-top: 4px;
    .label { font-size: 12px; color: rgb(var(--slate-10)); }
  }
}

.warn-pill {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 3px 8px;
  background: rgb(var(--amber-3));
  color: rgb(var(--amber-11));
  border: 1px solid rgb(var(--amber-7));
  border-radius: 999px;
  font-size: 11px;
}

.mismatch {
  display: inline-flex; align-items: center; gap: 6px;
  padding: 10px 12px;
  background: rgb(var(--ruby-3));
  color: rgb(var(--ruby-11));
  border: 1px solid rgb(var(--ruby-7));
  border-radius: 6px;
  font-size: 12px;
  margin-top: 4px;
}
</style>
