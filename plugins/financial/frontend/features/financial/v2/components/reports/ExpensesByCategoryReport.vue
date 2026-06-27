<script setup>
/**
 * Despesas por Categoria — wireframe Hub Relatórios (2026-05-23).
 *
 * Estrutura hierárquica GRUPO → ITEM seguindo plano de contas canônico:
 *
 *   GRUPO          | ITEM                       | VALOR    | % TOTAL
 *   1. Pessoal     | (TOTAL GRUPO)              | R$ X     | 45.28%
 *   1. Pessoal     | Salários e Ordenados       | R$ Y     | 26.64%
 *   1. Pessoal     | Encargos Sociais           | R$ Z     | 18.65%
 *   2. Ocupação    | (TOTAL GRUPO)              | ...
 *
 * Sem KPI cards/trend pra ficar igual ao wireframe (visão tabular pura).
 * Drill-down por categoria mantido — clica num item, vê as despesas.
 */
import { ref, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL } from '../../composables/useMoney';

const props = defineProps({
  from: { type: String, required: true },
  to:   { type: String, required: true },
});

const notifyError = msg => useNotification.error(msg);
const loading = ref(false);
const data = ref({ summary: {}, groups: [], uncategorized: {} });

const drillCategoryId = ref(undefined);
const drillCategoryName = ref('');
const drillExpenses = ref([]);
const drillLoading = ref(false);

async function load() {
  loading.value = true;
  try {
    const res = await FinancialV2.reports.expensesByCategory({
      from: props.from, to: props.to,
    });
    data.value = res.data || { summary: {}, groups: [], uncategorized: {} };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar despesas por categoria.');
  } finally {
    loading.value = false;
  }
}

async function openDrill(item) {
  drillCategoryId.value = item.id;
  drillCategoryName.value = item.name;
  drillLoading.value = true;
  try {
    const res = await FinancialV2.reports.expensesByCategoryDrilldown(
      item.id == null ? null : item.id,
      { from: props.from, to: props.to },
    );
    drillExpenses.value = res.data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar despesas.');
  } finally {
    drillLoading.value = false;
  }
}

function closeDrill() {
  drillCategoryId.value = undefined;
  drillExpenses.value = [];
}

watch(() => [props.from, props.to], load);
onMounted(load);

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

defineExpose({
  exportCsv: () => {
    const rows = [['Grupo', 'Item', 'Valor', '% Total']];
    (data.value.groups || []).forEach(g => {
      rows.push([g.name, '(TOTAL GRUPO)', (g.total_cents/100).toFixed(2).replace('.', ','), `${g.percent_of_total}%`]);
      g.items.forEach(i => {
        rows.push([g.name, i.name, (i.total_cents/100).toFixed(2).replace('.', ','), `${i.percent_of_total}%`]);
      });
    });
    if (data.value.uncategorized?.count > 0) {
      rows.push(['Sem categoria', '(direto)',
        (data.value.uncategorized.total_cents/100).toFixed(2).replace('.', ','),
        '']);
    }
    return rows;
  },
});
</script>

<template>
  <div class="rep-detail">
    <div v-if="data.summary.total_cents" class="rep-detail__summary">
      Total despesas no período: <strong>{{ centsToBRL(data.summary.total_cents || 0) }}</strong>
      <span class="rep-detail__summary-hint">· combina despesas fixas + saídas manuais</span>
    </div>

    <div v-if="loading" class="finv2-state">
      <div class="finv2-spinner" /><span>Carregando…</span>
    </div>
    <div v-else-if="(!data.groups || data.groups.length === 0) && !data.uncategorized?.count" class="finv2-state">
      <div class="finv2-state__icon-wrap"><i class="i-lucide-pie-chart w-7 h-7" /></div>
      <p class="finv2-state__title">Nenhuma despesa lançada no período</p>
      <p class="finv2-state__hint">Inclui pendentes, vencidas e pagas. Ajuste o período ou registre despesas em A Pagar.</p>
    </div>
    <div v-else class="finv2-table-wrap">
      <table class="finv2-table rep-detail__cat-table">
        <thead>
          <tr>
            <th class="rep-detail__cat-th-grupo">Grupo</th>
            <th class="rep-detail__cat-th-item">Item</th>
            <th class="finv2-table__th-num">Valor</th>
            <th class="finv2-table__th-num">% Total</th>
            <th class="rep-detail__th-actions"></th>
          </tr>
        </thead>
        <tbody>
          <template v-for="g in data.groups" :key="g.id">
            <!-- Linha do GRUPO (cabeçalho com TOTAL GRUPO) -->
            <tr class="rep-detail__cat-row--group">
              <td class="rep-detail__cat-td-grupo">
                <strong>{{ g.name }}</strong>
              </td>
              <td class="rep-detail__cat-total-marker">(TOTAL GRUPO)</td>
              <td class="finv2-table__td-num finv2-table__td-num--strong rep-detail__cat-group-value">
                {{ centsToBRL(g.total_cents) }}
              </td>
              <td class="finv2-table__td-num rep-detail__cat-group-percent">
                {{ g.percent_of_total.toFixed(2) }}%
              </td>
              <td class="rep-detail__td-actions"></td>
            </tr>
            <!-- Itens do GRUPO -->
            <tr
              v-for="item in g.items"
              :key="`g${g.id}-i${item.id}`"
              class="rep-detail__cat-row--item"
            >
              <td class="rep-detail__cat-td-grupo rep-detail__cat-td-grupo--muted">{{ g.name }}</td>
              <td class="rep-detail__cat-td-item">{{ item.name }}</td>
              <td class="finv2-table__td-num">{{ centsToBRL(item.total_cents) }}</td>
              <td class="finv2-table__td-num">{{ item.percent_of_total.toFixed(2) }}%</td>
              <td class="rep-detail__td-actions">
                <BeclinicButton
                  size="xs"
                  variant="ghost"
                  color="slate"
                  icon="i-lucide-eye"
                  @click="openDrill(item)"
                />
              </td>
            </tr>
          </template>

          <!-- Sem categoria (linha especial, warning) -->
          <tr
            v-if="data.uncategorized?.count > 0"
            class="rep-detail__cat-row--uncategorized"
          >
            <td class="rep-detail__cat-td-grupo">
              <strong>Sem categoria</strong>
            </td>
            <td class="rep-detail__cat-total-marker rep-detail__cat-total-marker--warning">
              Reclassifique pra entrar no DRE
            </td>
            <td class="finv2-table__td-num finv2-table__td-num--strong">
              {{ centsToBRL(data.uncategorized.total_cents) }}
            </td>
            <td class="finv2-table__td-num">—</td>
            <td class="rep-detail__td-actions">
              <BeclinicButton
                size="xs"
                variant="ghost"
                color="amber"
                icon="i-lucide-eye"
                @click="openDrill({ id: null, name: 'Sem categoria' })"
              />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- Drill-down: lista de despesas da categoria escolhida -->
    <div v-if="drillCategoryId !== undefined" class="rep-detail__drill">
      <header class="rep-detail__drill-header">
        <h3>Despesas em "{{ drillCategoryName }}"</h3>
        <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" label="Fechar" @click="closeDrill" />
      </header>
      <div v-if="drillLoading" class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
      <div v-else-if="drillExpenses.length === 0" class="finv2-state">
        <p class="finv2-state__title">Nenhuma despesa nessa categoria.</p>
      </div>
      <div v-else class="finv2-table-wrap">
        <table class="finv2-table">
          <thead>
            <tr>
              <th>Descrição</th>
              <th>Vencimento</th>
              <th>Conta</th>
              <th>Pagamento</th>
              <th class="finv2-table__th-num">Valor</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in drillExpenses" :key="e.id">
              <td><strong>{{ e.description }}</strong></td>
              <td class="finv2-table__td-date">{{ formatDateBR(e.due_date) }}</td>
              <td class="finv2-table__td-muted">{{ e.bank_account?.name || '—' }}</td>
              <td class="finv2-table__td-muted">{{ e.payment_method || '—' }}</td>
              <td class="finv2-table__td-num finv2-table__td-num--strong">{{ centsToBRL(e.amount_cents) }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Sumário no topo (substitui os 4 KPI cards do design antigo) */
.rep-detail__summary {
  padding: 12px 16px;
  margin-bottom: 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  font-size: 13px;
  color: rgb(var(--slate-11));
  strong { color: #b91c1c; font-weight: 700; font-variant-numeric: tabular-nums; }
}
:root.dark .rep-detail__summary strong { color: #fca5a5; }
.rep-detail__summary-hint {
  color: rgb(var(--slate-9));
  font-size: 12px;
  margin-left: 4px;
}

/* Tabela hierárquica */
.rep-detail__cat-table {
  th, td { vertical-align: middle; }
}

.rep-detail__cat-th-grupo, .rep-detail__cat-td-grupo { width: 32%; min-width: 200px; }
.rep-detail__cat-th-item,  .rep-detail__cat-td-item  { width: 42%; min-width: 220px; }

/* Linhas de cabeçalho de GRUPO — destaque visual (igual wireframe) */
.rep-detail__cat-row--group td {
  background: rgba(20, 184, 166, 0.06); /* teal subtle */
  border-top: 1px solid rgb(var(--slate-4));
  padding-top: 14px;
  padding-bottom: 14px;
}
.rep-detail__cat-row--group strong {
  color: rgb(var(--teal-11));
  font-size: 14px;
}
:root.dark .rep-detail__cat-row--group td { background: rgba(20, 184, 166, 0.12); }
:root.dark .rep-detail__cat-row--group strong { color: #5eead4; }

.rep-detail__cat-total-marker {
  color: rgb(var(--teal-11));
  font-size: 11px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
}
:root.dark .rep-detail__cat-total-marker { color: #5eead4; }

.rep-detail__cat-group-value { color: rgb(var(--teal-11)); font-weight: 700; }
.rep-detail__cat-group-percent { color: rgb(var(--teal-11)); font-weight: 700; }
:root.dark .rep-detail__cat-group-value,
:root.dark .rep-detail__cat-group-percent { color: #5eead4; }

/* Linhas de ITEM — repete nome do grupo à esquerda em tom muted (igual wireframe) */
.rep-detail__cat-td-grupo--muted {
  color: rgb(var(--slate-9));
  font-size: 12.5px;
}
.rep-detail__cat-row--item:hover td { background: rgb(var(--slate-2)); }

/* Sem categoria — destaque amber */
.rep-detail__cat-row--uncategorized td {
  background: rgba(245, 158, 11, 0.06);
  border-top: 1px dashed rgb(var(--slate-5));
}
.rep-detail__cat-row--uncategorized strong { color: rgb(var(--amber-11)); }
.rep-detail__cat-total-marker--warning {
  color: rgb(var(--amber-11));
  font-style: italic;
  text-transform: none;
  letter-spacing: 0;
  font-weight: 500;
}
:root.dark .rep-detail__cat-row--uncategorized td { background: rgba(245, 158, 11, 0.12); }
:root.dark .rep-detail__cat-row--uncategorized strong,
:root.dark .rep-detail__cat-total-marker--warning { color: #fcd34d; }

.rep-detail__th-actions { width: 60px; text-align: right; }
.rep-detail__td-actions { text-align: right; white-space: nowrap; }

/* Drill-down (mantido — útil ao clicar num item) */
.rep-detail__drill {
  margin-top: 16px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--blue-7));
  border-radius: 12px;
  padding: 16px 18px;
  display: flex; flex-direction: column; gap: 12px;
}
.rep-detail__drill-header {
  display: flex; justify-content: space-between; align-items: center; gap: 8px;
}
.rep-detail__drill-header h3 {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
</style>
