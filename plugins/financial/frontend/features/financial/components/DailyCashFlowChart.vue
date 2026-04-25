<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useFormatCurrency } from '../composables/useFormatCurrency';

const props = defineProps({
  data: { type: Array, default: () => [] },
});

const { t } = useI18n();
const { formatCurrency } = useFormatCurrency();

const chartMax = computed(() => {
  if (!props.data.length) return 1;
  return Math.max(...props.data.map(d => Math.max(d.entradas, d.saidas)), 1);
});

function barHeight(value) {
  return Math.max((value / chartMax.value) * 140, 2);
}

function formatDay(dateStr) {
  if (!dateStr) return '';
  const d = new Date(dateStr + 'T12:00:00');
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
}
</script>

<template>
  <div class="dcf-chart">
    <div class="dcf-bars">
      <div v-for="day in data" :key="day.date" class="dcf-column">
        <div class="dcf-bar-pair">
          <div
            class="dcf-bar dcf-bar--income"
            :style="{ height: barHeight(day.entradas) + 'px' }"
            :title="formatCurrency(day.entradas)"
          />
          <div
            class="dcf-bar dcf-bar--expense"
            :style="{ height: barHeight(day.saidas) + 'px' }"
            :title="formatCurrency(day.saidas)"
          />
        </div>
        <span class="dcf-label">{{ formatDay(day.date) }}</span>
      </div>
    </div>
    <div class="dcf-legend">
      <span class="dcf-legend__item dcf-legend__item--income">
        {{ t('FINANCIAL.DASHBOARD.CHART_ENTRIES') }}
      </span>
      <span class="dcf-legend__item dcf-legend__item--expense">
        {{ t('FINANCIAL.DASHBOARD.CHART_EXITS') }}
      </span>
    </div>
  </div>
</template>
