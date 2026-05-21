<script setup>
/**
 * Sparkline — mini line chart inline pra KPIs.
 *
 * SVG puro (zero dependencies) — vue-chartjs aqui seria overkill: 4 sparklines
 * inicializariam 4 ChartJS instances que custam ~50ms cada no boot. SVG path
 * com smooth bezier custa ~0.1ms.
 *
 * Props:
 *   - values: Array<number> (≤30 pontos)
 *   - color: hex (default brand blue)
 *   - height: px (default 30)
 */
import { computed } from 'vue';

const props = defineProps({
  values: { type: Array, default: () => [] },
  color: { type: String, default: '#1f93ff' },
  height: { type: Number, default: 30 },
  fill: { type: Boolean, default: true },
});

const VIEW_W = 100;
const VIEW_H = 30;

const path = computed(() => {
  const vs = props.values;
  if (!vs.length) return null;
  if (vs.length === 1) {
    const y = VIEW_H / 2;
    return { line: `M 0 ${y} L ${VIEW_W} ${y}`, area: '' };
  }
  const min = Math.min(...vs);
  const max = Math.max(...vs);
  const range = max - min || 1;
  const stepX = VIEW_W / (vs.length - 1);
  const points = vs.map((v, i) => {
    const x = i * stepX;
    const y = VIEW_H - ((v - min) / range) * (VIEW_H - 4) - 2;
    return [x, y];
  });

  // Smooth path com curvas catmull-rom-ish (quadratic através de midpoints).
  let line = `M ${points[0][0].toFixed(2)} ${points[0][1].toFixed(2)}`;
  for (let i = 1; i < points.length; i++) {
    const [x0, y0] = points[i - 1];
    const [x1, y1] = points[i];
    const cx = (x0 + x1) / 2;
    line += ` Q ${cx.toFixed(2)} ${y0.toFixed(2)} ${cx.toFixed(2)} ${((y0 + y1) / 2).toFixed(2)}`;
    line += ` T ${x1.toFixed(2)} ${y1.toFixed(2)}`;
  }
  const area = `${line} L ${VIEW_W} ${VIEW_H} L 0 ${VIEW_H} Z`;
  return { line, area };
});

const isEmpty = computed(() => !props.values.length);
</script>

<template>
  <svg
    v-if="!isEmpty"
    class="sparkline"
    :viewBox="`0 0 ${VIEW_W} ${VIEW_H}`"
    :style="{ height: height + 'px', width: '100%' }"
    preserveAspectRatio="none"
    aria-hidden="true"
  >
    <path
      v-if="fill && path"
      :d="path.area"
      :fill="color"
      fill-opacity="0.12"
    />
    <path
      v-if="path"
      :d="path.line"
      fill="none"
      :stroke="color"
      stroke-width="1.5"
      stroke-linecap="round"
      stroke-linejoin="round"
      vector-effect="non-scaling-stroke"
    />
  </svg>
  <span v-else class="sparkline sparkline--empty" :style="{ height: height + 'px' }" />
</template>

<style scoped>
.sparkline { display: block; }
.sparkline--empty {
  display: block;
  background: linear-gradient(90deg, transparent, rgba(148, 163, 184, 0.1), transparent);
  border-radius: 2px;
}
</style>
