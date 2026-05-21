<script setup>
/**
 * Projeção de Fluxo de Caixa v2 — line chart 60 dias forward-looking.
 *
 * Eixo Y: saldo projetado começando do saldo atual.
 * Cada dia adiciona inflow (A Receber.due_date == dia) - outflow (A Pagar.due_date == dia).
 * Útil pro gestor antecipar quebra de caixa.
 *
 * Janela fixa em 60 dias — não respeita o period selector (forecast só faz
 * sentido olhando pra frente; "Ano anterior" não tem semântica de projeção).
 */
import { computed, ref, onMounted } from 'vue';
import { Line } from 'vue-chartjs';
import {
  Chart as ChartJS,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Legend,
  Filler,
} from 'chart.js';
import FinancialV2 from '../../api/financialV2';

ChartJS.register(LineElement, PointElement, LinearScale, CategoryScale, Tooltip, Legend, Filler);

const data = ref(null);
const loading = ref(true);

onMounted(async () => {
  try {
    const { data: payload } = await FinancialV2.reports.cashFlowProjection({ horizon: 60 });
    data.value = payload;
  } finally {
    loading.value = false;
  }
});

const shortDate = d => {
  const date = new Date(d);
  return `${String(date.getDate()).padStart(2, '0')}/${String(date.getMonth() + 1).padStart(2, '0')}`;
};

const days = computed(() => data.value?.days || []);

const goesNegative = computed(() => days.value.some(d => d.balance_cents < 0));
// Formatter BR-friendly com separador de milhar (Intl.NumberFormat).
const fmtBRL = v => `R$ ${v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

const lowestBalanceLabel = computed(() => {
  if (!data.value) return '';
  return fmtBRL(data.value.lowest_balance_cents / 100);
});

const chartData = computed(() => ({
  labels: days.value.map(d => shortDate(d.date)),
  datasets: [
    {
      label: 'Saldo projetado',
      data: days.value.map(d => d.balance_cents / 100),
      borderColor: '#1f93ff',
      backgroundColor: ctx => {
        const chart = ctx.chart;
        const { ctx: g, chartArea } = chart;
        if (!chartArea) return 'rgba(31, 147, 255, 0.10)';
        const gradient = g.createLinearGradient(0, chartArea.top, 0, chartArea.bottom);
        gradient.addColorStop(0, 'rgba(31, 147, 255, 0.25)');
        gradient.addColorStop(1, 'rgba(31, 147, 255, 0)');
        return gradient;
      },
      fill: true,
      tension: 0.25,
      pointRadius: 0,
      pointHoverRadius: 4,
      borderWidth: 2,
    },
  ],
}));

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      titleColor: '#fff',
      bodyColor: '#e2e8f0',
      padding: 10,
      callbacks: {
        title: items => {
          const idx = items[0].dataIndex;
          const day = days.value[idx];
          return day ? `Dia ${shortDate(day.date)}` : '';
        },
        label: ctx => {
          const idx = ctx.dataIndex;
          const d = days.value[idx] || {};
          const lines = [`Saldo: ${fmtBRL(d.balance_cents / 100)}`];
          if (d.inflow_cents > 0)  lines.push(`A receber: ${fmtBRL(d.inflow_cents / 100)}`);
          if (d.outflow_cents > 0) lines.push(`A pagar: ${fmtBRL(d.outflow_cents / 100)}`);
          return lines;
        },
      },
    },
  },
  scales: {
    x: {
      grid: { display: false },
      ticks: { font: { size: 10 }, maxRotation: 0, autoSkip: true, maxTicksLimit: 8 },
    },
    y: {
      grid: { color: 'rgba(148, 163, 184, 0.15)', drawBorder: false },
      ticks: {
        font: { size: 10 },
        callback: v => (v >= 1000 || v <= -1000 ? `R$ ${(v / 1000).toFixed(1)}k` : `R$ ${v.toFixed(0)}`),
      },
    },
  },
}));

const isEmpty = computed(() => !loading.value && days.value.length === 0);
</script>

<template>
  <div class="cfproj-v2">
    <header class="cfproj-v2__header">
      <div>
        <h3 class="cfproj-v2__title">Projeção de Fluxo de Caixa</h3>
        <p class="cfproj-v2__subtitle">
          Próximos 60 dias
          <template v-if="!loading && data">
            · saldo final estimado <strong>{{ fmtBRL(data.end_balance_cents / 100) }}</strong>
          </template>
        </p>
      </div>
      <div v-if="goesNegative" class="cfproj-v2__alert">
        <i class="i-lucide-alert-triangle w-4 h-4" />
        Saldo mínimo: <strong>{{ lowestBalanceLabel }}</strong>
      </div>
    </header>
    <div class="cfproj-v2__body">
      <div v-if="loading" class="cfproj-v2__skel"><div class="cfproj-v2__shimmer" /></div>
      <div v-else-if="isEmpty" class="cfproj-v2__empty">
        <i class="i-lucide-trending-up w-8 h-8" />
        <p>Sem A Receber/Pagar agendados nos próximos 60 dias.</p>
      </div>
      <Line v-else :data="chartData" :options="chartOptions" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.cfproj-v2 {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px 18px 14px;
  display: flex; flex-direction: column;
  min-height: 320px;
}
.cfproj-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start; gap: 12px;
  margin-bottom: 12px;
}
.cfproj-v2__title { font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); margin: 0; }
.cfproj-v2__subtitle {
  font-size: 12px; color: rgb(var(--slate-11)); margin: 2px 0 0;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}
.cfproj-v2__alert {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11.5px; font-weight: 500;
  padding: 4px 8px;
  background: rgba(245, 158, 11, 0.12);
  color: #b45309;
  border-radius: 6px;
  i { flex-shrink: 0; }
  strong { font-weight: 600; }
}
:root.dark .cfproj-v2__alert { color: #fcd34d; }
.cfproj-v2__body { flex: 1; min-height: 240px; position: relative; }
.cfproj-v2__skel { position: absolute; inset: 0; }
.cfproj-v2__shimmer {
  width: 100%; height: 100%;
  background: linear-gradient(90deg, rgb(var(--slate-3)) 0%, rgb(var(--slate-4)) 50%, rgb(var(--slate-3)) 100%);
  background-size: 200% 100%;
  animation: shimmer 1.4s ease-in-out infinite;
  border-radius: 8px;
  opacity: 0.5;
}
@keyframes shimmer {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}
.cfproj-v2__empty {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  color: rgb(var(--slate-9));
  p { font-size: 13px; margin: 0; }
}
</style>
