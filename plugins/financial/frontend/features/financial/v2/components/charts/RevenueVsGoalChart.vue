<script setup>
/**
 * RevenueVsGoalChart — Receita mensal vs Meta (canon Dashboard).
 *
 * Recebe array de meses do endpoint `reports/revenue_vs_goal`:
 *   [{ month: "2026-05", label: "Mai/26", revenue_cents, goal_cents, pct_attained }]
 *
 * Visual:
 *   - Barras mensais coloridas por % atingido:
 *     - vermelho < 60%
 *     - âmbar 60-99%
 *     - verde ≥ 100%
 *   - Linha tracejada horizontal mostrando a meta do mês mais recente
 *     (referência visual de "alvo").
 */
import { computed } from 'vue';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  BarElement,
  BarController,
  LineController,
  CategoryScale,
  LinearScale,
  Tooltip,
  Legend,
  LineElement,
  PointElement,
  Filler,
} from 'chart.js';

// Mixed chart (bar + line) precisa registrar AMBOS os controllers, não só
// os Elements. Sem `LineController`, Chart.js lança `"line" is not a
// registered controller` ao tentar renderizar o dataset `type: 'line'`
// (linha da meta).
ChartJS.register(
  BarElement, BarController, LineController,
  CategoryScale, LinearScale, Tooltip, Legend,
  LineElement, PointElement, Filler,
);

const props = defineProps({
  data: { type: Array, default: () => [] },
});

// Cor por % atingido
function colorByPct(pct) {
  if (pct == null) return '#94a3b8';      // sem meta → cinza
  if (pct >= 100)  return '#10b981';      // emerald
  if (pct >= 60)   return '#f59e0b';      // amber
  return '#ef4444';                       // red
}

const chartData = computed(() => {
  const labels = props.data.map(m => m.label);
  const revenueReais = props.data.map(m => (m.revenue_cents || 0) / 100);
  const goalReais    = props.data.map(m => (m.goal_cents || 0) / 100);

  return {
    labels,
    datasets: [
      {
        type: 'bar',
        label: 'Receita',
        data: revenueReais,
        backgroundColor: props.data.map(m => colorByPct(m.pct_attained)),
        borderRadius: 6,
        borderSkipped: false,
        barThickness: 22,
      },
      {
        type: 'line',
        label: 'Meta',
        data: goalReais,
        borderColor: '#10b981',
        borderWidth: 2,
        borderDash: [6, 6],
        backgroundColor: 'transparent',
        pointRadius: 0,
        pointHoverRadius: 4,
        tension: 0,
        spanGaps: true,
      },
    ],
  };
});

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
          const fmt = 'R$ ' + val.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
          if (ctx.dataset.label === 'Receita') {
            const pct = props.data[ctx.dataIndex]?.pct_attained;
            return ' Receita: ' + fmt + (pct != null ? ` (${pct}%)` : '');
          }
          return ' Meta: ' + fmt;
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

const isEmpty = computed(() => !props.data.length || props.data.every(m => !m.revenue_cents && !m.goal_cents));
</script>

<template>
  <div class="rvg-chart">
    <div v-if="isEmpty" class="rvg-chart__empty">
      Sem receita ou meta cadastrada nos últimos meses.
    </div>
    <Bar v-else :data="chartData" :options="chartOptions" />
  </div>
</template>

<style scoped lang="scss">
.rvg-chart {
  position: relative;
  height: 260px;
  width: 100%;
}
.rvg-chart__empty {
  display: flex;
  align-items: center;
  justify-content: center;
  height: 100%;
  color: rgb(var(--slate-9));
  font-size: 13px;
  font-style: italic;
}
</style>
