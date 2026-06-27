<script setup>
/**
 * Receitas por Procedimento — wireframe Hub Relatórios (2026-05-23).
 *
 * Fonte: `BudgetItem` agrupado por `description`, dentro de orçamentos
 * `aprovado`/`concluido` no período. Já existe `Charts.top_procedures`
 * (limit 10 pro dashboard) — este endpoint retorna a lista COMPLETA
 * com `percent_of_total` calculado.
 *
 * Colunas: # · Procedimento · QTD · Receita · Ticket médio · % total
 */
import { ref, computed, watch, onMounted } from 'vue';
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
    const res = await FinancialV2.reports.revenueByProcedure({
      from: props.from, to: props.to,
    });
    data.value = res.data || { summary: {}, items: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar receitas por procedimento.');
  } finally {
    loading.value = false;
  }
}

watch(() => [props.from, props.to], load);
onMounted(load);

defineExpose({
  exportCsv: () => {
    const rows = [['#', 'Procedimento', 'QTD', 'Receita', 'Ticket médio', '% Total']];
    data.value.items.forEach(i => {
      rows.push([
        i.rank, i.name, i.qty,
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
      · {{ data.summary.procedures_count || 0 }}
      {{ (data.summary.procedures_count || 0) === 1 ? 'procedimento' : 'procedimentos' }}
      · {{ (data.summary.total_quantity || 0).toLocaleString('pt-BR') }} executados
    </div>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" /><span>Carregando…</span>
    </div>
    <div v-else-if="data.items.length === 0" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-clipboard-list w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhum procedimento no período</p>
      <p class="finv2-state__hint">Orçamentos aprovados ou concluídos aparecem aqui.</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table">
        <thead>
          <tr>
            <th class="rep-detail__th-rank">#</th>
            <th>Procedimento</th>
            <th class="finv2-table__th-num">QTD</th>
            <th class="finv2-table__th-num">Receita</th>
            <th class="finv2-table__th-num">Ticket médio</th>
            <th class="finv2-table__th-num">% Total</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="i in data.items" :key="i.rank">
            <td class="rep-detail__td-rank">{{ i.rank }}</td>
            <td><strong>{{ i.name }}</strong></td>
            <td class="finv2-table__td-num">{{ i.qty.toLocaleString('pt-BR') }}</td>
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
.rep-detail__th-rank, .rep-detail__td-rank {
  width: 40px; text-align: center;
  font-variant-numeric: tabular-nums; color: rgb(var(--slate-9));
}
</style>
