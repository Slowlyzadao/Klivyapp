<script setup>
/**
 * Fluxo de Caixa Diário v2 — line chart 30 dias.
 * Mostra entradas (verde), saídas (ruby) e saldo acumulado (azul brand).
 *
 * Reusa endpoint v1 `/financial/reports/cash_flow_chart` que retorna:
 *   { days: [{ date, income, outflow, balance }, ...] }
 *
 * Visual premium v2:
 *   - Linhas suaves (tension 0.35), pontos pequenos
 *   - Grid sutil, tooltip dark
 *   - Empty state minimalista
 */
import { computed, ref, onMounted, watch } from 'vue';
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

const props = defineProps({
  from: { type: String, default: null },
  to:   { type: String, default: null },
  label:{ type: String, default: 'Últimos 30 dias' },
});

const days = ref([]);
const loading = ref(true);

async function fetchData() {
  loading.value = true;
  try {
    const params = (props.from && props.to) ? { from: props.from, to: props.to } : {};
    const { data } = await FinancialV2.reports.cashFlowChart(params);
    days.value = data?.days || [];
  } finally {
    loading.value = false;
  }
}

onMounted(fetchData);
watch(() => [props.from, props.to], fetchData);

// Formatter BR-friendly com separador de milhar (Intl.NumberFormat).
// Resolve bug do tooltip mostrar "R$ 389274,07" em vez de "R$ 389.274,07".
const fmtBRL = v => `R$ ${v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const shortDate = d => {
  const date = new Date(d);
  return `${String(date.getDate()).padStart(2, '0')}/${String(date.getMonth() + 1).padStart(2, '0')}`;
};

const chartData = computed(() => ({
  labels: days.value.map(d => shortDate(d.date)),
  datasets: [
    {
      label: 'Entradas',
      data: days.value.map(d => (d.income_cents ?? d.income ?? 0) / 100),
      borderColor: '#10b981',
      backgroundColor: 'rgba(16, 185, 129, 0.08)',
      fill: true,
      tension: 0.35,
      pointRadius: 0,
      pointHoverRadius: 4,
      borderWidth: 2,
    },
    {
      label: 'Saídas',
      data: days.value.map(d => (d.outflow_cents ?? d.outflow ?? 0) / 100),
      borderColor: '#ef4444',
      backgroundColor: 'rgba(239, 68, 68, 0.08)',
      fill: true,
      tension: 0.35,
      pointRadius: 0,
      pointHoverRadius: 4,
      borderWidth: 2,
    },
    {
      label: 'Saldo acumulado',
      data: days.value.map(d => (d.balance_cents ?? d.balance ?? 0) / 100),
      borderColor: '#1f93ff',
      backgroundColor: 'transparent',
      fill: false,
      tension: 0.35,
      pointRadius: 0,
      pointHoverRadius: 4,
      borderWidth: 2,
      borderDash: [4, 3],
    },
  ],
}));

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  interaction: { intersect: false, mode: 'index' },
  plugins: {
    legend: {
      display: true,
      position: 'bottom',
      labels: { boxWidth: 10, boxHeight: 10, padding: 14, font: { size: 11 } },
    },
    tooltip: {
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      titleColor: '#fff',
      bodyColor: '#e2e8f0',
      borderColor: 'rgba(255,255,255,0.1)',
      borderWidth: 1,
      padding: 10,
      callbacks: {
        label: ctx => `${ctx.dataset.label}: ${fmtBRL(ctx.parsed.y)}`,
      },
    },
  },
  scales: {
    x: { grid: { display: false }, ticks: { font: { size: 10 }, maxRotation: 0 } },
    y: {
      grid: { color: 'rgba(148, 163, 184, 0.15)', drawBorder: false },
      ticks: {
        font: { size: 10 },
        callback: v => 'R$ ' + (v >= 1000 ? `${(v / 1000).toFixed(1)}k` : v.toFixed(0)),
      },
    },
  },
};

const isEmpty = computed(() => !loading.value && days.value.length === 0);
</script>

<template>
  <div class="cfdaily-v2">
    <header class="cfdaily-v2__header">
      <div>
        <h3 class="cfdaily-v2__title">Fluxo de Caixa Diário</h3>
        <p class="cfdaily-v2__subtitle">{{ label }}</p>
      </div>
    </header>
    <div class="cfdaily-v2__body">
      <div v-if="loading" class="cfdaily-v2__skel">
        <div class="cfdaily-v2__shimmer" />
      </div>
      <div v-else-if="isEmpty" class="cfdaily-v2__empty">
        <i class="i-lucide-line-chart w-8 h-8" />
        <p>Sem movimentações nos últimos 30 dias.</p>
      </div>
      <Line v-else :data="chartData" :options="chartOptions" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.cfdaily-v2 {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px 18px 14px;
  display: flex; flex-direction: column;
  min-height: 320px;
}
.cfdaily-v2__header { margin-bottom: 12px; }
.cfdaily-v2__title {
  font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); margin: 0;
}
.cfdaily-v2__subtitle {
  font-size: 12px; color: rgb(var(--slate-11)); margin: 2px 0 0;
}
.cfdaily-v2__body { flex: 1; min-height: 240px; position: relative; }
.cfdaily-v2__skel {
  position: absolute; inset: 0;
  display: flex; align-items: center; justify-content: center;
}
.cfdaily-v2__shimmer {
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
.cfdaily-v2__empty {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  color: rgb(var(--slate-9));
  p { font-size: 13px; margin: 0; }
}
</style>
