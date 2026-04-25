<script setup>
import { computed } from 'vue';
import { useFormatCurrency } from '../composables/useFormatCurrency';

const props = defineProps({
  data: { type: Array, default: () => [] },
});

const { formatCurrency } = useFormatCurrency();

const chartMax = computed(() => {
  if (!props.data.length) return 1;
  return Math.max(...props.data.map(d => d.total), 1);
});

function barHeight(value) {
  return Math.max((value / chartMax.value) * 140, 2);
}

function shortCurrency(value) {
  if (value >= 1000) {
    return `R$ ${(value / 1000).toFixed(1)}k`;
  }
  return formatCurrency(value);
}
</script>

<template>
  <div class="msc-chart">
    <div class="msc-bars">
      <div v-for="month in data" :key="month.month" class="msc-column">
        <span class="msc-value">{{ shortCurrency(month.total) }}</span>
        <div
          class="msc-bar"
          :style="{ height: barHeight(month.total) + 'px' }"
          :title="formatCurrency(month.total)"
        />
        <span class="msc-label">{{ month.label }}</span>
      </div>
    </div>
  </div>
</template>
