<script setup>
defineProps({
  height: { type: String, default: '220px' },
  bars: { type: Number, default: 8 },
});

// Alturas pré-geradas para parecerem naturais (não verdadeiramente aleatórias)
const barHeights = [45, 70, 35, 85, 55, 65, 40, 78];
</script>

<template>
  <div class="chart-skeleton" :style="{ height }">
    <div
      v-for="(h, i) in barHeights.slice(0, bars)"
      :key="i"
      class="chart-skeleton__bar"
      :style="{ height: h + '%' }"
    />
  </div>
</template>
