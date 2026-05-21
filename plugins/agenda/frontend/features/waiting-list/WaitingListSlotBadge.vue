<script setup>
/**
 * waiting-list/WaitingListSlotBadge.vue
 *
 * Badge verde pastel exibido em blocos de horário vagos no calendário
 * quando há contatos na lista de espera com preferência por aquele período/horário.
 * Renderizado diretamente dentro do slot de timeline (view semana/dia).
 */
import { computed } from 'vue';

const props = defineProps({
  /** Entradas da lista de espera que coincidem com este slot */
  entries: {
    type: Array,
    default: () => [],
  },
});

const label = computed(() => {
  const n = props.entries.length;
  if (n === 1)
    return `Disponível para lista de espera (${props.entries[0].contactName})`;
  return `Disponível para lista de espera (${n} pacientes)`;
});
</script>

<template>
  <div class="wl-slot-badge" :title="label">
    <span class="i-ph-clock-countdown wl-slot-icon" />
    <span class="wl-slot-text">{{ label }}</span>
  </div>
</template>

<style scoped>
.wl-slot-badge {
  position: absolute;
  inset: 2px;
  border-radius: 4px;
  background: rgba(34, 197, 94, 0.1);
  border: 1px solid rgba(34, 197, 94, 0.25);
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 6px;
  pointer-events: none;
  overflow: hidden;
}

.wl-slot-icon {
  @apply text-sm;
  color: #16a34a;
  flex-shrink: 0;
}

.wl-slot-text {
  @apply text-sm;
  color: #16a34a;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  line-height: 1.3;
}
</style>
