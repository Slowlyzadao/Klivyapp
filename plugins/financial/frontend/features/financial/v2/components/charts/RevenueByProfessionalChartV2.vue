<script setup>
/**
 * Receita por Profissional v2 — horizontal bar chart top 5.
 * Reusa endpoint v1 `/financial/reports/revenue_by_professional?period=YYYY-MM`
 * que retorna:
 *   { professionals: [{ id, name, total_cents, count, avg_ticket_cents }, ...] }
 *
 * Visual: barras horizontais com brand blue, ticks à esquerda com nomes.
 */
import { computed, ref, onMounted, watch } from 'vue';
import { Bar } from 'vue-chartjs';
import {
  Chart as ChartJS, BarElement, CategoryScale, LinearScale, Tooltip, Legend,
} from 'chart.js';
import FinancialV2 from '../../api/financialV2';

ChartJS.register(BarElement, CategoryScale, LinearScale, Tooltip, Legend);

const props = defineProps({
  from: { type: String, default: null },
  to:   { type: String, default: null },
  label:{ type: String, default: 'Mês atual · top 5' },
});

const professionals = ref([]);
const loading = ref(true);

async function fetchData() {
  loading.value = true;
  try {
    const params = (props.from && props.to) ? { from: props.from, to: props.to } : {};
    const { data } = await FinancialV2.reports.revenueByProfessional(params);
    professionals.value = (data?.professionals || []).slice(0, 5);
  } finally {
    loading.value = false;
  }
}

onMounted(fetchData);
watch(() => [props.from, props.to], fetchData);

const chartData = computed(() => ({
  labels: professionals.value.map(p => p.name || 'Sem profissional'),
  datasets: [{
    label: 'Receita',
    data: professionals.value.map(p => (p.total_cents || 0) / 100),
    backgroundColor: '#1f93ff',
    hoverBackgroundColor: '#0e7be0',
    borderRadius: 6,
    borderSkipped: false,
    barThickness: 22,
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
          const p = professionals.value[ctx.dataIndex];
          const avg = p?.avg_ticket_cents != null ? ` · ticket médio ${fmtBRL(p.avg_ticket_cents / 100)}` : '';
          return `${fmtBRL(v)}${avg}`;
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

const isEmpty = computed(() => !loading.value && professionals.value.length === 0);

// Formatter BR-friendly com separador de milhar (Intl.NumberFormat).
const fmtBRL = v => `R$ ${v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
</script>

<template>
  <div class="rprof-v2">
    <header class="rprof-v2__header">
      <div>
        <h3 class="rprof-v2__title">Receita por Profissional</h3>
        <p class="rprof-v2__subtitle">{{ label }}</p>
      </div>
    </header>
    <div class="rprof-v2__body">
      <div v-if="loading" class="rprof-v2__skel">
        <div class="rprof-v2__shimmer" />
      </div>
      <div v-else-if="isEmpty" class="rprof-v2__empty">
        <i class="i-lucide-users w-8 h-8" />
        <p>Nenhuma receita por profissional no mês.</p>
      </div>
      <Bar v-else :data="chartData" :options="chartOptions" />
    </div>
  </div>
</template>

<style scoped lang="scss">
.rprof-v2 {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px;
  display: flex; flex-direction: column;
  min-height: 320px;
}
.rprof-v2__header { margin-bottom: 12px; }
.rprof-v2__title {
  font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); margin: 0;
}
.rprof-v2__subtitle {
  font-size: 12px; color: rgb(var(--slate-11)); margin: 2px 0 0;
}
.rprof-v2__body { flex: 1; min-height: 220px; position: relative; }
.rprof-v2__skel { position: absolute; inset: 0; }
.rprof-v2__shimmer {
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
.rprof-v2__empty {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 8px;
  color: rgb(var(--slate-9));
  p { font-size: 13px; margin: 0; }
}
</style>
