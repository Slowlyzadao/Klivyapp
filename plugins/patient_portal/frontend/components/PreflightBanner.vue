<template>
  <div v-if="visibleChecks.length > 0" class="pp-preflight" :class="{ 'pp-preflight--blocked': hasBlocking }">
    <div class="pp-preflight__header">
      <IconInfo :size="18" />
      <span>{{ hasBlocking ? 'Para solicitar agendamento, resolva:' : 'Antes do seu agendamento:' }}</span>
    </div>
    <ul class="pp-preflight__list">
      <li v-for="c in visibleChecks" :key="c.label" class="pp-preflight__item" :class="`pp-preflight__item--${c.status}`">
        <span class="pp-preflight__dot" />
        <div>
          <div class="pp-preflight__label">{{ c.label }}</div>
          <div v-if="c.message" class="pp-preflight__msg">{{ c.message }}</div>
        </div>
      </li>
    </ul>
  </div>
</template>

<script setup>
import { computed } from 'vue';
import IconInfo from './icons/IconInfo.vue';

const props = defineProps({
  checks: { type: Object, default: () => ({}) }
});

const visibleChecks = computed(() => Object.values(props.checks).filter(c => c && c.status !== 'skipped' && c.status !== 'ok'));
const hasBlocking   = computed(() => visibleChecks.value.some(c => c.status === 'blocked'));
</script>

<style scoped>
.pp-preflight {
  background: #fef3c7; border: 1px solid #fde68a;
  border-radius: 14px; padding: 12px 14px;
}
.pp-preflight--blocked { background: #fee2e2; border-color: #fecaca; }

.pp-preflight__header {
  display: flex; align-items: center; gap: 8px;
  font-weight: 700; font-size: 13px; color: #92400e;
  margin-bottom: 8px;
}
.pp-preflight--blocked .pp-preflight__header { color: #991b1b; }

.pp-preflight__list { list-style: none; padding: 0; margin: 0; display: flex; flex-direction: column; gap: 8px; }
.pp-preflight__item {
  display: flex; align-items: flex-start; gap: 10px;
  font-size: 13px; color: var(--pp-color-text);
}
.pp-preflight__dot {
  width: 8px; height: 8px; border-radius: 50%; margin-top: 6px; flex-shrink: 0;
}
.pp-preflight__item--blocked .pp-preflight__dot { background: #dc2626; }
.pp-preflight__item--warning .pp-preflight__dot { background: #d97706; }

.pp-preflight__label { font-weight: 600; }
.pp-preflight__msg   { font-size: 12px; color: var(--pp-color-text-muted); margin-top: 2px; }
</style>
