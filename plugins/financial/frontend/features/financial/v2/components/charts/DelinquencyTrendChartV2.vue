<script setup>
/**
 * Tendência de Inadimplência v2 — line chart 12 meses.
 *
 * Eixo Y esquerdo: % inadimplência (vencido em aberto ÷ faturado no mês).
 * Eixo Y direito: valor inadimplente em R$ (barras de apoio).
 *
 * Útil pra ver se a inadimplência tá piorando ou melhorando ao longo do tempo.
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

const series = ref([]);
const loading = ref(true);

// Formatter BR-friendly com separador de milhar (Intl.NumberFormat).
const fmtBRL = v => `R$ ${v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

onMounted(async () => {
  try {
    const { data } = await FinancialV2.reports.delinquencyTrend({ months: 12 });
    series.value = data?.series || [];
  } finally {
    loading.value = false;
  }
});

const chartData = computed(() => ({
  labels: series.value.map(s => s.label),
  datasets: [
    {
      label: '% Inadimplência',
      data: series.value.map(s => s.pct),
      borderColor: '#dc2626',
      backgroundColor: 'rgba(220, 38, 38, 0.10)',
      fill: true,
      tension: 0.3,
      pointRadius: 3,
      pointHoverRadius: 5,
      pointBackgroundColor: '#dc2626',
      pointBorderColor: '#fff',
      pointBorderWidth: 1.5,
      borderWidth: 2,
    },
  ],
}));

const chartOptions = {
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
        label: ctx => {
          const idx = ctx.dataIndex;
          const s = series.value[idx] || {};
          const inv = (s.invoiced_cents || 0) / 100;
          const del = (s.delinquent_cents || 0) / 100;
          return [
            `${s.pct}% inadimplente`,
            `${fmtBRL(del)} de ${fmtBRL(inv)}`,
          ];
        },
      },
    },
  },
  scales: {
    x: { grid: { display: false }, ticks: { font: { size: 10 } } },
    y: {
      grid: { color: 'rgba(148, 163, 184, 0.15)', drawBorder: false },
      beginAtZero: true,
      ticks: { font: { size: 10 }, callback: v => `${v}%` },
    },
  },
};

const latestPct = computed(() => series.value.at(-1)?.pct ?? 0);
const previousPct = computed(() => series.value.at(-2)?.pct ?? 0);
const trendDirection = computed(() => {
  const diff = latestPct.value - previousPct.value;
  if (Math.abs(diff) < 0.5) return 'flat';
  return diff > 0 ? 'up' : 'down';
});

const isEmpty = computed(() =>
  !loading.value && (series.value.length === 0 || series.value.every(s => s.invoiced_cents === 0))
);
</script>

<template>
  <div class="dtrend-v2">
    <header class="dtrend-v2__header">
      <div>
        <h3 class="dtrend-v2__title">Tendência de Inadimplência</h3>
        <p class="dtrend-v2__subtitle">
          Últimos 12 meses
          <template v-if="!loading && !isEmpty">
            · atual <strong>{{ latestPct }}%</strong>
          </template>
        </p>
      </div>
      <span
        v-if="!loading && !isEmpty"
        :class="['dtrend-v2__trend', `dtrend-v2__trend--${trendDirection}`]"
      >
        <i v-if="trendDirection === 'up'" class="i-lucide-trending-up w-3.5 h-3.5" />
        <i v-else-if="trendDirection === 'down'" class="i-lucide-trending-down w-3.5 h-3.5" />
        <i v-else class="i-lucide-minus w-3.5 h-3.5" />
        {{
          trendDirection === 'up'
            ? 'Piorando'
            : trendDirection === 'down'
            ? 'Melhorando'
            : 'Estável'
        }}
      </span>
    </header>
    <div class="dtrend-v2__body">
      <div v-if="loading" class="dtrend-v2__skel"><div class="dtrend-v2__shimmer" /></div>
      <div v-else-if="isEmpty" class="dtrend-v2__empty">
        <i class="i-lucide-check-circle-2 w-8 h-8" />
        <p>Sem inadimplência registrada nos últimos 12 meses.</p>
      </div>
      <Line v-else :data="chartData" :options="chartOptions" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.dtrend-v2 {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px 18px 14px;
  display: flex; flex-direction: column;
  min-height: 320px;
}
.dtrend-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start; gap: 12px;
  margin-bottom: 12px;
}
.dtrend-v2__title { font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); margin: 0; }
.dtrend-v2__subtitle {
  font-size: 12px; color: rgb(var(--slate-11)); margin: 2px 0 0;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}
.dtrend-v2__trend {
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11.5px; font-weight: 500;
  padding: 4px 8px;
  border-radius: 6px;
  &--up   { color: #b91c1c; background: rgba(220, 38, 38, 0.12); }
  &--down { color: #047857; background: rgba(16, 185, 129, 0.12); }
  &--flat { color: rgb(var(--slate-11)); background: rgb(var(--slate-3)); }
}
:root.dark .dtrend-v2__trend--up   { color: #fca5a5; }
:root.dark .dtrend-v2__trend--down { color: #6ee7b7; }
.dtrend-v2__body { flex: 1; min-height: 240px; position: relative; }
.dtrend-v2__skel { position: absolute; inset: 0; }
.dtrend-v2__shimmer {
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
.dtrend-v2__empty {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  color: #10b981;
  p { font-size: 13px; margin: 0; color: rgb(var(--slate-11)); }
}
</style>
