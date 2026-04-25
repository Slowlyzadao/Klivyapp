<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { Doughnut } from 'vue-chartjs';
import { Chart as ChartJS, ArcElement, Tooltip } from 'chart.js';
import { useChart } from '../composables/useChart';
import ChartSkeleton from './ChartSkeleton.vue';

const props = defineProps({
  data: {
    type: Object,
    default: () => ({
      meta: 0,
      realizado: 0,
      percentual: 0,
      ritmo_ideal: 0,
      delta_ritmo: 0,
      dias_restantes: 0,
    }),
  },
  loading: { type: Boolean, default: false },
});

ChartJS.register(ArcElement, Tooltip);

const { isDark, formatBRL } = useChart();
const { t } = useI18n();

const activeTab = ref('monthly');
const tabs = computed(() => [
  { id: 'monthly', label: t('FINANCIAL.CHARTS.REVENUE_GOAL.TAB_MONTHLY') },
  { id: 'quarterly', label: t('FINANCIAL.CHARTS.REVENUE_GOAL.TAB_QUARTERLY') },
  { id: 'annual', label: t('FINANCIAL.CHARTS.REVENUE_GOAL.TAB_ANNUAL') },
]);

const currentGauge = computed(() => {
  const d = props.data || {};
  if (activeTab.value === 'quarterly') {
    return {
      meta: d.meta_trimestral || 0,
      realizado: d.realizado_trimestral || 0,
      percentual: d.percentual_trimestral || 0,
      delta_ritmo: d.delta_ritmo_trimestral || 0,
      dias_restantes: d.dias_restantes_trimestral || 0,
      ritmo_ideal: d.ritmo_ideal_trimestral || 0,
    };
  }
  if (activeTab.value === 'annual') {
    return {
      meta: d.meta_anual || 0,
      realizado: d.realizado_anual || 0,
      percentual: d.percentual_anual || 0,
      delta_ritmo: d.delta_ritmo_anual || 0,
      dias_restantes: d.dias_restantes_anual || 0,
      ritmo_ideal: d.ritmo_ideal_anual || 0,
    };
  }
  return {
    meta: d.meta || 0,
    realizado: d.realizado || 0,
    percentual: d.percentual || 0,
    delta_ritmo: d.delta_ritmo || 0,
    dias_restantes: d.dias_restantes || 0,
    ritmo_ideal: d.ritmo_ideal || 0,
  };
});

const gaugeColor = computed(() => {
  const p = currentGauge.value.percentual;
  if (p >= 85) return '#10B981';
  if (p >= 60) return '#F59E0B';
  return '#EF4444';
});

const trackColor = computed(() => (isDark.value ? '#1E293B' : '#F1F5F9'));

const pctLabel = computed(() => {
  const format = val => (val != null ? val.toFixed(1) : 0.0);
  return `${format(currentGauge.value.percentual)}%`;
});

const chartData = computed(() => {
  const p = currentGauge.value.percentual || 0;
  return {
    datasets: [
      {
        data: [p, Math.max(0, 100 - p)],
        backgroundColor: [gaugeColor.value, trackColor.value],
        borderWidth: 0,
      },
    ],
  };
});

const chartOptions = computed(() => ({
  responsive: true,
  maintainAspectRatio: false,
  rotation: -90,
  circumference: 180,
  cutout: '75%',
  plugins: {
    legend: { display: false },
    tooltip: { enabled: false },
  },
}));

const isBehind = computed(() => {
  let diffDays = 10;
  if (activeTab.value === 'annual') {
    diffDays = 30;
  } else if (activeTab.value === 'quarterly') {
    diffDays = 15;
  }
  return (
    currentGauge.value.delta_ritmo < 0 &&
    currentGauge.value.dias_restantes < diffDays
  );
});
</script>

<template>
  <div class="gauge-wrapper">
    <template v-if="loading">
      <ChartSkeleton height="160px" :bars="1" />
    </template>
    <template v-else>
      <div class="financial-period-selector mb-4 mx-auto w-fit">
        <button
          v-for="tab in tabs"
          :key="tab.id"
          class="financial-period-btn"
          :class="{ 'financial-period-btn--active': activeTab === tab.id }"
          @click="activeTab = tab.id"
        >
          {{ tab.label }}
        </button>
      </div>

      <!-- Gauge -->
      <div class="gauge-chart-area">
        <Doughnut :data="chartData" :options="chartOptions" />
        <div class="gauge-center-text">
          <span class="gauge-pct" :style="{ color: gaugeColor }">
            {{ pctLabel }}
          </span>
          <span class="gauge-subtitle">
            {{ t('FINANCIAL.CHARTS.REVENUE_GOAL.GOAL_REACHED') }}
          </span>
          <span class="gauge-value">{{
            formatBRL(currentGauge.realizado)
          }}</span>
        </div>
      </div>

      <!-- Métricas abaixo do gauge -->
      <div class="gauge-metrics">
        <div class="gauge-metric">
          <span class="gauge-metric__label">
            {{ t('FINANCIAL.CHARTS.REVENUE_GOAL.GOAL') }}
          </span>
          <span class="gauge-metric__value">{{
            formatBRL(currentGauge.meta)
          }}</span>
        </div>
        <div class="gauge-metric">
          <span class="gauge-metric__label">
            {{ t('FINANCIAL.CHARTS.REVENUE_GOAL.IDEAL_PACE') }}
          </span>
          <span class="gauge-metric__value">{{
            formatBRL(currentGauge.ritmo_ideal)
          }}</span>
        </div>
        <div class="gauge-metric">
          <span class="gauge-metric__label">
            {{ t('FINANCIAL.CHARTS.REVENUE_GOAL.REMAINING_DAYS') }}
          </span>
          <span class="gauge-metric__value">{{
            currentGauge.dias_restantes
          }}</span>
        </div>
      </div>

      <!-- Alerta de atraso -->
      <div v-if="isBehind" class="gauge-alert">
        <i class="i-lucide-alert-triangle gauge-alert__icon" />
        <span>
          {{
            t('FINANCIAL.CHARTS.REVENUE_GOAL.ALERT_BEHIND', {
              delta: formatBRL(Math.abs(currentGauge.delta_ritmo)),
              days: currentGauge.dias_restantes,
            })
          }}
        </span>
      </div>
    </template>
  </div>
</template>
