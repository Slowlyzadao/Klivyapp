<script setup>
/**
 * Composição de Receita v2 — donut chart top 5 categorias.
 * Reusa endpoint v1 `/financial/reports/revenue_composition` que retorna:
 *   { months: 6, series: [{ category, label, total_cents }, ...] }
 *
 * Visual:
 *   - Top 5 categorias + "Outras" se sobrar
 *   - Paleta semântica suave (não-saturada)
 *   - Legenda lateral com valor e %
 */
import { computed, ref, onMounted, watch } from 'vue';
import { Doughnut } from 'vue-chartjs';
import { Chart as ChartJS, ArcElement, Tooltip, Legend } from 'chart.js';
import FinancialV2 from '../../api/financialV2';

ChartJS.register(ArcElement, Tooltip, Legend);

const props = defineProps({
  from: { type: String, default: null },
  to:   { type: String, default: null },
  label:{ type: String, default: 'Últimos 6 meses · top 5 categorias' },
});

const series = ref([]);
const loading = ref(true);

async function fetchData() {
  loading.value = true;
  try {
    const params = (props.from && props.to) ? { from: props.from, to: props.to } : { months: 6 };
    const { data } = await FinancialV2.reports.revenueComposition(params);
    series.value = data?.series || [];
  } finally {
    loading.value = false;
  }
}

onMounted(fetchData);
watch(() => [props.from, props.to], fetchData);

const PALETTE = ['#3b82f6', '#10b981', '#f59e0b', '#a855f7', '#ec4899', '#64748b'];

const top5 = computed(() => {
  const sorted = [...series.value].sort((a, b) => (b.total_cents || 0) - (a.total_cents || 0));
  if (sorted.length <= 5) return sorted;
  const top = sorted.slice(0, 5);
  const rest = sorted.slice(5).reduce((s, it) => s + (it.total_cents || 0), 0);
  return [...top, { label: 'Outras', total_cents: rest }];
});

const total = computed(() => top5.value.reduce((s, it) => s + (it.total_cents || 0), 0));

const chartData = computed(() => ({
  labels: top5.value.map(s => s.label || s.category || 'Sem categoria'),
  datasets: [{
    data: top5.value.map(s => (s.total_cents || 0) / 100),
    backgroundColor: top5.value.map((_, i) => PALETTE[i % PALETTE.length]),
    borderWidth: 0,
    hoverOffset: 8,
  }],
}));

const chartOptions = {
  responsive: true,
  maintainAspectRatio: false,
  cutout: '65%',
  plugins: {
    legend: { display: false },
    tooltip: {
      backgroundColor: 'rgba(15, 23, 42, 0.95)',
      titleColor: '#fff',
      bodyColor: '#e2e8f0',
      padding: 10,
      callbacks: {
        label: ctx => {
          const v = ctx.parsed;
          const pct = total.value > 0 ? ((v * 100) / (total.value / 100)).toFixed(1) : 0;
          return `${ctx.label}: ${fmtBRL(v)} (${pct}%)`;
        },
      },
    },
  },
};

// Formatter BR-friendly com separador de milhar (Intl.NumberFormat).
const fmtBRL = v => `R$ ${v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const fmt = c => fmtBRL(c / 100);
const pct = c => (total.value > 0 ? ((c * 100) / total.value).toFixed(1) + '%' : '—');
const isEmpty = computed(() => !loading.value && top5.value.length === 0);
</script>

<template>
  <!-- Header interno removido: o card pai (`dash-v2__chart-card`) já tem
       título + subtítulo do gráfico. Manter aqui duplicava texto sem
       agregar info. Componente segue auto-contido (loading/empty/legend). -->
  <div class="rcomp-v2">
    <div class="rcomp-v2__body">
      <div v-if="loading" class="rcomp-v2__skel">
        <div class="rcomp-v2__shimmer" />
      </div>
      <div v-else-if="isEmpty" class="rcomp-v2__empty">
        <i class="i-lucide-pie-chart w-8 h-8" />
        <p>Sem receita registrada nos últimos 6 meses.</p>
      </div>
      <template v-else>
        <div class="rcomp-v2__chart">
          <Doughnut :data="chartData" :options="chartOptions" />
          <div class="rcomp-v2__center">
            <span class="rcomp-v2__center-label">Total</span>
            <strong class="rcomp-v2__center-value">{{ fmt(total) }}</strong>
          </div>
        </div>
        <ul class="rcomp-v2__legend">
          <li v-for="(s, i) in top5" :key="s.label || s.category" class="rcomp-v2__legend-item">
            <span class="rcomp-v2__dot" :style="{ background: PALETTE[i % PALETTE.length] }" />
            <span class="rcomp-v2__legend-name">{{ s.label || s.category || 'Sem categoria' }}</span>
            <span class="rcomp-v2__legend-value">{{ fmt(s.total_cents) }} · {{ pct(s.total_cents) }}</span>
          </li>
        </ul>
      </template>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Wrapper sem background/border/padding — o card pai já é o quadro.
   Mantém só altura mínima + flex pra esqueleto/empty preencherem. */
.rcomp-v2 {
  display: flex; flex-direction: column;
  min-height: 280px;
}
.rcomp-v2__body {
  flex: 1; display: grid; grid-template-columns: 1fr 1fr; gap: 16px;
  align-items: center;
  position: relative;
}
.rcomp-v2__chart {
  position: relative; height: 200px;
}
.rcomp-v2__center {
  position: absolute; inset: 0;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  pointer-events: none;
}
.rcomp-v2__center-label { font-size: 11px; color: rgb(var(--slate-11)); }
.rcomp-v2__center-value {
  font-size: 16px; font-weight: 700; color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
.rcomp-v2__legend {
  list-style: none; margin: 0; padding: 0;
  display: flex; flex-direction: column; gap: 8px;
}
.rcomp-v2__legend-item {
  display: flex; align-items: center; gap: 8px; font-size: 12.5px;
}
.rcomp-v2__dot {
  width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
}
.rcomp-v2__legend-name {
  color: rgb(var(--slate-12)); font-weight: 500; flex: 1; min-width: 0;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.rcomp-v2__legend-value {
  color: rgb(var(--slate-11)); font-variant-numeric: tabular-nums; flex-shrink: 0;
}

.rcomp-v2__skel, .rcomp-v2__empty {
  position: absolute; inset: 0; grid-column: 1 / -1;
  display: flex; align-items: center; justify-content: center; flex-direction: column; gap: 8px;
  color: rgb(var(--slate-9));
  p { font-size: 13px; margin: 0; }
}
.rcomp-v2__shimmer {
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

@media (max-width: 640px) {
  .rcomp-v2__body { grid-template-columns: 1fr; }
}
</style>
