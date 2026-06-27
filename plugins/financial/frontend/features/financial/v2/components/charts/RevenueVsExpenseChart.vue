<script setup>
/**
 * RevenueVsExpenseChart — Receita vs Despesa últimos N meses.
 *
 * Reusa `reports/revenue_vs_goal` (já agrega receita por mês) + chama
 * `reports/dre` por mês pra obter despesas. Pra simplificar inicialmente,
 * usa `cash_flow_chart` que retorna entradas/saídas agregadas no período
 * desejado.
 *
 * Visual: barras agrupadas (verde = receita, vermelho = despesa) por mês.
 */
import { computed, ref, onMounted, watch } from 'vue';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS, BarElement, CategoryScale, LinearScale, Tooltip, Legend,
} from 'chart.js';
import FinancialV2 from '../../api/financialV2';

ChartJS.register(BarElement, CategoryScale, LinearScale, Tooltip, Legend);

const props = defineProps({
  months: { type: Number, default: 6 },
});

const series = ref([]); // [{ label, revenue_cents, expense_cents }]
const loading = ref(true);

async function fetchData() {
  loading.value = true;
  try {
    // Pega `revenue_vs_goal` pra ter receita agregada por mês
    const { data } = await FinancialV2.reports.revenueVsGoal({ months: props.months });
    const months = data?.months || [];

    // Pra despesa, chama DRE de cada mês — N pequeno (≤24) então aceitável
    const expensePromises = months.map(m => {
      const [year, month] = m.month.split('-').map(Number);
      const start = `${year}-${String(month).padStart(2, '0')}-01`;
      const end = new Date(year, month, 0).toISOString().slice(0, 10);
      return FinancialV2.reports.dre({ from: start, to: end })
        .then(res => res?.data?.total_despesa_cents || 0)
        .catch(() => 0);
    });
    const expenses = await Promise.all(expensePromises);

    series.value = months.map((m, i) => ({
      label: m.label,
      revenue_cents: m.revenue_cents,
      expense_cents: expenses[i],
    }));
  } finally {
    loading.value = false;
  }
}

onMounted(fetchData);
watch(() => props.months, fetchData);

const chartData = computed(() => ({
  labels: series.value.map(s => s.label),
  datasets: [
    {
      label: 'Receita',
      data: series.value.map(s => (s.revenue_cents || 0) / 100),
      backgroundColor: '#10b981',
      hoverBackgroundColor: '#0d9268',
      borderRadius: 6,
      borderSkipped: false,
      barThickness: 18,
    },
    {
      label: 'Despesa',
      data: series.value.map(s => (s.expense_cents || 0) / 100),
      backgroundColor: '#ef4444',
      hoverBackgroundColor: '#dc2626',
      borderRadius: 6,
      borderSkipped: false,
      barThickness: 18,
    },
  ],
}));

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { mode: 'index', intersect: false },
  plugins: {
    legend: {
      display: true,
      position: 'top',
      labels: {
        color: 'rgba(148, 163, 184, 0.85)',
        font: { size: 11, weight: '600' },
        boxWidth: 12,
        padding: 12,
      },
    },
    tooltip: {
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      padding: 10,
      titleFont: { size: 12, weight: '600' },
      bodyFont: { size: 12 },
      callbacks: {
        label(ctx) {
          const val = ctx.parsed.y;
          return ' ' + ctx.dataset.label + ': R$ ' + val.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
        },
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: { color: 'rgba(148, 163, 184, 0.7)', font: { size: 11 } },
    },
    y: {
      beginAtZero: true,
      grid: { color: 'rgba(148, 163, 184, 0.1)' },
      ticks: {
        color: 'rgba(148, 163, 184, 0.7)',
        font: { size: 11 },
        callback(v) {
          if (Math.abs(v) >= 1_000_000) return 'R$ ' + (v / 1_000_000).toFixed(1) + 'M';
          if (Math.abs(v) >= 1_000)     return 'R$ ' + Math.round(v / 1_000) + 'K';
          return 'R$ ' + v;
        },
      },
    },
  },
};

const isEmpty = computed(() => !series.value.length || series.value.every(s => !s.revenue_cents && !s.expense_cents));
</script>

<template>
  <div class="rve-chart">
    <div v-if="loading && !series.length" class="rve-chart__loading">
      <div class="rve-chart__spinner" /> Carregando...
    </div>
    <div v-else-if="isEmpty" class="rve-chart__empty">
      Sem movimentações nos últimos meses.
    </div>
    <Bar v-else :data="chartData" :options="chartOptions" />
  </div>
</template>

<style scoped lang="scss">
.rve-chart {
  position: relative;
  height: 260px;
  width: 100%;
}
.rve-chart__loading, .rve-chart__empty {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  gap: 8px;
  color: rgb(var(--slate-9));
  font-size: 13px;
  font-style: italic;
}
.rve-chart__spinner {
  width: 14px; height: 14px;
  border: 2px solid rgba(148, 163, 184, 0.3);
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }
</style>
