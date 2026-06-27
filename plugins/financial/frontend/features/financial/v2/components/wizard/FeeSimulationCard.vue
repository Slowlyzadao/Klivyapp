<script setup>
/**
 * Card de simulação de taxa pra UM PaymentMethod isolado.
 * Usado em Step 4 do wizard quando o operador quer ver a taxa de um
 * método específico sem montar o plano completo (ex: "quanto é Cielo 10x
 * pra R$ 1.000?").
 *
 * Não recebe paymentMethods inteiros — só o id + amount + installments.
 * Faz chamada read-only ao backend (debounced no pai).
 */
import { computed } from 'vue';
import { centsToBRL } from '../../composables/useMoney';

const props = defineProps({
  // Resposta do GET /payment_methods/:id/simulate_fee — pode ser null enquanto carrega
  simulation: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const feePercent = computed(() => {
  if (!props.simulation) return null;
  return (props.simulation.fee_percent_basis_points || 0) / 100;
});
</script>

<template>
  <div class="fee-card" :class="{ 'fee-card--loading': loading }">
    <div v-if="loading" class="fee-loading">
      <span class="dot" />
      <span class="dot" />
      <span class="dot" />
    </div>

    <template v-else-if="simulation">
      <header class="fee-header">
        <strong>{{ simulation.payment_method_name }}</strong>
        <span class="installments">{{ simulation.installments_count }}x</span>
      </header>

      <div v-if="!simulation.fee_resolved" class="fee-empty">
        <i class="i-lucide-info w-4 h-4" />
        Sem taxa cadastrada para esta configuração — assumindo 0%.
      </div>

      <template v-else>
        <dl class="fee-grid">
          <div>
            <dt>Bruto</dt>
            <dd>{{ centsToBRL(simulation.amount_cents) }}</dd>
          </div>
          <div>
            <dt>Taxa</dt>
            <dd class="negative">
              <span v-if="feePercent">{{ feePercent.toFixed(2) }}%</span>
              <span v-if="feePercent && simulation.fee_fixed_cents"> + </span>
              <span v-if="simulation.fee_fixed_cents">{{ centsToBRL(simulation.fee_fixed_cents) }}</span>
              <span class="amount">= − {{ centsToBRL(simulation.fee_amount_cents) }}</span>
            </dd>
          </div>
          <div>
            <dt>Líquido</dt>
            <dd class="emphasis">{{ centsToBRL(simulation.net_amount_cents) }}</dd>
          </div>
          <div v-if="simulation.liquidation_days > 0">
            <dt>Liquidação</dt>
            <dd>D+{{ simulation.liquidation_days }} ({{ simulation.expected_liquidation_date }})</dd>
          </div>
        </dl>
      </template>
    </template>

    <div v-else class="fee-placeholder">
      Selecione método e valor para simular a taxa.
    </div>
  </div>
</template>

<style scoped lang="scss">
.fee-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 12px;
  font-size: 13px;
}

.fee-loading {
  display: inline-flex; gap: 6px;
  .dot {
    width: 6px; height: 6px;
    border-radius: 50%;
    background: rgb(var(--slate-9));
    animation: pulse 1.4s infinite;
    &:nth-child(2) { animation-delay: 0.2s; }
    &:nth-child(3) { animation-delay: 0.4s; }
  }
}
@keyframes pulse { 0%, 80%, 100% { opacity: 0.3; } 40% { opacity: 1; } }

.fee-header {
  display: flex; align-items: center; gap: 8px;
  margin-bottom: 8px;
  .installments {
    font-size: 11px;
    padding: 2px 6px;
    background: rgb(var(--blue-3));
    color: rgb(var(--blue-11));
    border-radius: 4px;
  }
}

.fee-empty {
  display: inline-flex; align-items: center; gap: 6px;
  color: rgb(var(--slate-10));
  font-size: 12px;
}

.fee-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 8px;
  margin: 0;

  > div { display: flex; flex-direction: column; gap: 2px; }
  dt {
    font-size: 11px;
    color: rgb(var(--slate-10));
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }
  dd {
    margin: 0;
    font-variant-numeric: tabular-nums;
    color: rgb(var(--slate-12));

    &.negative { color: rgb(var(--ruby-11)); }
    &.emphasis { font-weight: 600; color: rgb(var(--blue-11)); }
    .amount { margin-left: 4px; font-weight: 500; }
  }
}

.fee-placeholder {
  color: rgb(var(--slate-9));
  font-style: italic;
}
</style>
