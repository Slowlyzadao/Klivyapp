<template>
  <router-link
    v-if="show"
    :to="{ name: 'financial' }"
    class="pp-overdue"
    :class="severityClass"
  >
    <IconWallet :size="20" />
    <div class="pp-overdue__body">
      <div class="pp-overdue__title">{{ title }}</div>
      <div class="pp-overdue__text">{{ text }}</div>
    </div>
    <IconChevronRight :size="18" />
  </router-link>
</template>

<script setup>
// Banner de inadimplência — exibido na Home e em outras telas que precisem
// (Sprint H, PRD §9.3).
//
// Componente "burro": recebe `restriction` (payload do backend) e decide
// visualmente; toda a regra de quem bloqueia está no
// PatientPortal::OverdueRestrictionChecker (backend).
import { computed } from 'vue';
import IconWallet from './icons/IconWallet.vue';
import IconChevronRight from './icons/IconChevronRight.vue';

const props = defineProps({
  restriction: { type: Object, default: () => ({}) }
});

const level = computed(() => props.restriction?.level || 'none');
const show  = computed(() => level.value && level.value !== 'none');

const severityClass = computed(() => ({
  'pp-overdue--warn':  level.value === 'warn',
  'pp-overdue--block': ['limit_scheduling', 'limit_messaging', 'full_block'].includes(level.value)
}));

const title = computed(() => {
  switch (level.value) {
    case 'warn':              return 'Você tem parcelas vencidas';
    case 'limit_scheduling':  return 'Agendamento temporariamente bloqueado';
    case 'limit_messaging':   return 'Mensagens e agendamento bloqueados';
    case 'full_block':        return 'Portal restrito por inadimplência';
    default:                  return '';
  }
});

const text = computed(() => {
  const days = props.restriction?.days_overdue ?? 0;
  const amountCents = props.restriction?.overdue_total_cents ?? 0;
  const amount = (amountCents / 100).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL' });
  if (level.value === 'warn') {
    return `${amount} em aberto há ${days} dia(s). Regularize para evitar bloqueios.`;
  }
  return `${amount} em aberto há ${days} dia(s). Quite para liberar.`;
});
</script>

<style scoped>
.pp-overdue {
  display: flex; align-items: center; gap: 12px;
  margin: 0 16px 16px; padding: 14px 16px;
  border-radius: 14px;
  text-decoration: none;
  border: 1px solid;
  transition: transform 120ms ease;
}
.pp-overdue:active { transform: scale(0.99); }

.pp-overdue--warn  { background: #fef3c7; border-color: #fde68a; color: #92400e; }
.pp-overdue--block { background: #fee2e2; border-color: #fecaca; color: #991b1b; }

.pp-overdue__body  { flex: 1; min-width: 0; }
.pp-overdue__title { font-size: 14px; font-weight: 700; }
.pp-overdue__text  { font-size: 12px; margin-top: 2px; opacity: 0.9; }
</style>
