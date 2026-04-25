<script setup>
defineProps({
  message: { type: String, default: '' },
  icon: { type: String, default: 'i-lucide-bar-chart-2' },
});
</script>

<template>
  <div class="chart-empty">
    <i class="chart-empty__icon" :class="[icon]" />
    <p class="chart-empty__msg">
      {{ message || $t('FINANCIAL.CHARTS.EMPTY') }}
    </p>
  </div>
</template>
