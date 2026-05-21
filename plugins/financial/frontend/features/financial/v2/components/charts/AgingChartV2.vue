<script setup>
/**
 * Aging Inadimplência v2 — stacked bar por faixa.
 * Reusa endpoint v1 `/financial/reports/delinquency_aging` que retorna:
 *   { buckets: [{ label, count, total_cents }, ...] }
 *
 * Faixas típicas: 0-30, 31-60, 61-90, 91+ dias.
 * Visual: barras horizontais com gradiente amber→ruby conforme intensidade.
 */
import { computed, ref, onMounted } from 'vue';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS, BarElement, CategoryScale, LinearScale, Tooltip, Legend,
} from 'chart.js';
import FinancialV2 from '../../api/financialV2';

ChartJS.register(BarElement, CategoryScale, LinearScale, Tooltip, Legend);

const buckets = ref([]);
const loading = ref(true);

onMounted(async () => {
  try {
    const { data } = await FinancialV2.reports.delinquencyAging();
    buckets.value = data?.buckets || [];
  } finally {
    loading.value = false;
  }
});

// Gradiente: 0-30 amber, 31-60 amber escuro, 61-90 ruby claro, 90+ ruby.
const COLORS = ['#f59e0b', '#ea580c', '#dc2626', '#991b1b'];

const chartData = computed(() => ({
  labels: buckets.value.map(b => b.label),
  datasets: [{
    label: 'Total vencido',
    data: buckets.value.map(b => (b.total_cents || 0) / 100),
    backgroundColor: buckets.value.map((_, i) => COLORS[i] || '#64748b'),
    borderRadius: 6,
    borderSkipped: false,
    barThickness: 28,
  }],
}));

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  indexAxis: 'y',
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      titleColor: '#fff',
      bodyColor: '#e2e8f0',
      padding: 10,
      callbacks: {
        label: ctx => {
          const v = ctx.parsed.x;
          const count = buckets.value[ctx.dataIndex]?.count || 0;
          return `${fmtBRL(v)} · ${count} parcela(s)`;
        },
      },
    },
  },
  scales: {
    x: {
      grid: { color: 'rgba(148, 163, 184, 0.15)', drawBorder: false },
      ticks: {
        font: { size: 10 },
        callback: v => (v >= 1000 ? `R$ ${(v / 1000).toFixed(1)}k` : `R$ ${v.toFixed(0)}`),
      },
    },
    y: { grid: { display: false }, ticks: { font: { size: 11 } } },
  },
};

const total = computed(() => buckets.value.reduce((s, b) => s + (b.total_cents || 0), 0));
// Formatter BR-friendly com separador de milhar (Intl.NumberFormat).
const fmtBRL = v => `R$ ${v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fmt = c => fmtBRL(c / 100);
const isEmpty = computed(() => !loading.value && total.value === 0);
</script>

<template>
  <div class="aging-v2">
    <header class="aging-v2__header">
      <div>
        <h3 class="aging-v2__title">Aging Inadimplência</h3>
        <p class="aging-v2__subtitle">
          Parcelas vencidas por faixa
          <strong v-if="!isEmpty && !loading"> · total {{ fmt(total) }}</strong>
        </p>
      </div>
    </header>
    <div class="aging-v2__body">
      <div v-if="loading" class="aging-v2__skel">
        <div class="aging-v2__shimmer" />
      </div>
      <div v-else-if="isEmpty" class="aging-v2__empty">
        <i class="i-lucide-check-circle-2 w-8 h-8" />
        <p>Tudo em dia — nenhuma parcela vencida.</p>
      </div>
      <Bar v-else :data="chartData" :options="chartOptions" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.aging-v2 {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px;
  display: flex; flex-direction: column;
  min-height: 320px;
}
.aging-v2__header { margin-bottom: 12px; }
.aging-v2__title {
  font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); margin: 0;
}
.aging-v2__subtitle {
  font-size: 12px; color: rgb(var(--slate-11)); margin: 2px 0 0;
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}
.aging-v2__body { flex: 1; min-height: 220px; position: relative; }
.aging-v2__skel { position: absolute; inset: 0; }
.aging-v2__shimmer {
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
.aging-v2__empty {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  color: #10b981;
  p { font-size: 13px; margin: 0; color: rgb(var(--slate-11)); }
}
</style>
