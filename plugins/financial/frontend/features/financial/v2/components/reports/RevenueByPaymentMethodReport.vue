<script setup>
/**
 * Receitas por Forma de Pagamento — wireframe Hub Relatórios (2026-05-23).
 *
 * Fonte: Entries de receita agrupadas por `payment_method`. Mostra mix
 * (PIX vs cartão vs dinheiro) pro operador avaliar custo de taxa
 * (MDR cartão vs PIX gratuito).
 *
 * Colunas: Forma · Qtd · Receita · Ticket médio · % Total
 */
import { ref, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';

const props = defineProps({
  from: { type: String, required: true },
  to:   { type: String, required: true },
});

const notifyError = msg => useNotification.error(msg);
const loading = ref(false);
const data = ref({ summary: {}, items: [] });

async function load() {
  loading.value = true;
  try {
    const res = await FinancialV2.reports.revenueByPaymentMethod({
      from: props.from, to: props.to,
    });
    data.value = res.data || { summary: {}, items: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar receitas por forma.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to], load);
onMounted(load);

defineExpose({
  exportCsv: () => {
    const rows = [['Forma', 'Qtd', 'Receita', 'Ticket médio', '% Total']];
    data.value.items.forEach(i => {
      rows.push([
        i.label, i.qty,
        (i.total_cents / 100).toFixed(2).replace('.', ','),
        i.ticket_avg_cents ? (i.ticket_avg_cents / 100).toFixed(2).replace('.', ',') : '',
        i.percent_of_total
      ]);
    });
    return rows;
  },
});
</script>

<template>
  <div class="rep-detail">
    <div class="rep-detail__summary">
      Total: <strong>{{ centsToBRL(data.summary.total_cents || 0) }}</strong>
      · {{ data.summary.transactions_count || 0 }} recebimentos
    </div>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" /><span>Carregando…</span>
    </div>
    <div v-else-if="data.items.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-credit-card w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma receita no período</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th>Forma</th>
            <th>Distribuição</th>
            <th class="finv2-table__th-num">Qtd</th>
            <th class="finv2-table__th-num">Receita</th>
            <th class="finv2-table__th-num">Ticket médio</th>
            <th class="finv2-table__th-num">% Total</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="i in data.items" :key="i.payment_method || 'null'">
            <td><strong>{{ i.label }}</strong></td>
            <td class="rep-detail__bar-cell">
              <div class="rep-detail__bar-track">
                <div
                  class="rep-detail__bar-fill"
                  :style="{ width: `${i.percent_of_total}%` }"
                />
              </div>
            </td>
            <td class="finv2-table__td-num">{{ i.qty }}</td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">{{ centsToBRL(i.total_cents) }}</td>
            <td class="finv2-table__td-num">
              {{ i.ticket_avg_cents != null ? centsToBRL(i.ticket_avg_cents) : '—' }}
            </td>
            <td class="finv2-table__td-num">{{ i.percent_of_total.toFixed(1) }}%</td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-detail__summary {
  padding: 10px 14px; margin-bottom: 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  font-size: 13px; color: rgb(var(--slate-11));
  strong { color: #047857; font-variant-numeric: tabular-nums; }
}
:root.dark .rep-detail__summary strong { color: #6ee7b7; }
.rep-detail__bar-cell { width: 25%; min-width: 120px; }
.rep-detail__bar-track {
  width: 100%; height: 8px; border-radius: 4px;
  background: rgb(var(--slate-3));
  overflow: hidden;
}
.rep-detail__bar-fill {
  height: 100%; border-radius: 4px;
  background: #10b981;
  transition: width 0.3s ease;
}
</style>
