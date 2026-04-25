<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Doughnut, Bar } from 'vue-chartjs';
import {
  Chart as ChartJS,
  ArcElement,
  BarElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Legend,
} from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';
import ChartEmptyState from './ChartEmptyState.vue';

const props = defineProps({
  data: { type: Object, default: () => ({ atual: {}, historico: [] }) },
  loading: { type: Boolean, default: false },
});

ChartJS.register(
  ArcElement,
  BarElement,
  LinearScale,
  CategoryScale,
  Tooltip,
  Legend
);

const { isDark, defaultTooltip, formatBRL } = useChart();
const { t } = useI18n();

const CATEGORY_COLORS = {
  particular: '#10B981',
  convenio: '#3B82F6',
  plano: '#8B5CF6',
  outros: '#94A3B8',
};

const atualEntries = computed(() =>
  Object.entries(props.data.atual || {}).filter(([, v]) => v > 0)
);

const totalAtual = computed(() =>
  atualEntries.value.reduce((s, [, v]) => s + v, 0)
);

const dominantCategory = computed(() => {
  if (totalAtual.value <= 0) return null;
  const sorted = [...atualEntries.value].sort((a, b) => b[1] - a[1]);
  const [key, val] = sorted[0] || [];
  const pct = (val / totalAtual.value) * 100;
  return pct > 60 ? { key, pct: pct.toFixed(1) } : null;
});


const donutData = computed(() => ({
  labels: atualEntries.value.map(([k]) =>
    t(`FINANCIAL.CHARTS.COMPOSITION.${k.toUpperCase()}`)
  ),
  datasets: [
    {
      data: atualEntries.value.map(([, v]) => v),
      backgroundColor: atualEntries.value.map(
        ([k]) => CATEGORY_COLORS[k] || '#94A3B8'
      ),
      borderWidth: 0,
    },
  ],
}));

const donutOptions = computed(() => ({
  cutout: '70%',
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx =>
          ` ${formatBRL(ctx.raw)} (${((ctx.raw / totalAtual.value) * 100).toFixed(1)}%)`,
      },
    },
  },
}));

const historico = computed(() => props.data.historico || []);
const keys = ['particular', 'convenio', 'plano', 'outros'];

const stackedData = computed(() => ({
  labels: historico.value.map(h => h.mes),
  datasets: keys.map(k => ({
    label: t(`FINANCIAL.CHARTS.COMPOSITION.${k.toUpperCase()}`),
    data: historico.value.map(h => h[k] ?? 0),
    backgroundColor: CATEGORY_COLORS[k],
    stack: 's',
    borderRadius: 2,
  })),
}));

const stackedOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  plugins: {
    legend: { display: false },
    tooltip: {
      ...defaultTooltip,
      callbacks: {
        label: ctx => ` ${ctx.dataset.label}: ${formatBRL(ctx.raw)}`,
      },
    },
  },
  scales: {
    x: {
      stacked: true,
      grid: { display: false },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 10 },
      },
    },
    y: {
      stacked: true,
      grid: { color: isDark.value ? '#334155' : '#E2E8F0' },
      ticks: {
        color: isDark.value ? '#94A3B8' : '#64748B',
        font: { size: 10 },
        callback: v => formatBRL(v),
      },
    },
  },
}));
</script>

<template>
  <div class="composition-wrapper">
    <div v-if="dominantCategory" class="composition-alert">
      <i class="i-lucide-alert-triangle composition-alert__icon" />
      <span>
        {{
          t('FINANCIAL.CHARTS.COMPOSITION.ALERT_CONCENTRATION', {
            category: t(
              `FINANCIAL.CHARTS.COMPOSITION.${dominantCategory.key.toUpperCase()}`
            ),
            pct: dominantCategory.pct,
          })
        }}
      </span>
    </div>

    <template v-if="loading">
      <ChartSkeleton height="240px" />
    </template>
    <template v-else-if="!atualEntries.length">
      <ChartEmptyState :message="t('FINANCIAL.CHARTS.EMPTY')" />
    </template>
    <template v-else>
      <div class="composition-charts">
        <!-- Donut -->
        <div class="composition-donut-wrap">
          <div class="composition-donut-container">
            <Doughnut
              :data="donutData"
              :options="donutOptions"
            />
            <div class="composition-donut-total">{{ formatBRL(totalAtual) }}</div>
          </div>
          <div class="composition-legend">
            <span
              v-for="[key] in atualEntries"
              :key="key"
              class="composition-legend__item"
              :style="{ '--c': CATEGORY_COLORS[key] }"
              >{{
                t(`FINANCIAL.CHARTS.COMPOSITION.${key.toUpperCase()}`)
              }}</span
            >
          </div>
        </div>
        <!-- Stacked bars -->
        <div class="composition-stacked-wrap">
          <Bar :data="stackedData" :options="stackedOptions" />
        </div>
      </div>
    </template>
  </div>
</template>
