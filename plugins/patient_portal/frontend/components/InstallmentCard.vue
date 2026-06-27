<template>
  <router-link :to="{ name: 'installment-detail', params: { id: installment.id } }" class="pp-inst-card" :class="modifier">
    <div class="pp-inst-card__leading">
      <div class="pp-inst-card__num">{{ installment.number }}/{{ installment.total_in_series }}</div>
      <div class="pp-inst-card__date">{{ formattedDate }}</div>
    </div>
    <div class="pp-inst-card__body">
      <div class="pp-inst-card__amount">{{ formatCurrency(installment.amount_cents) }}</div>
      <Badge :variant="badgeVariant" size="sm">{{ statusLabel }}</Badge>
    </div>
    <IconChevronRight :size="18" class="pp-inst-card__chevron" />
  </router-link>
</template>

<script setup>
import { computed } from 'vue';
import Badge from './Badge.vue';
import IconChevronRight from './icons/IconChevronRight.vue';
import { formatCurrency, formatDate } from '../utils/format';

const props = defineProps({
  installment: { type: Object, required: true }
});

const STATUS_LABELS = {
  pendente:    'A vencer',
  parcial:     'Parcial',
  recebido:    'Pago',
  vencido:     'Vencida',
  estornado:   'Estornado',
  cancelado:   'Cancelado',
  renegociado: 'Renegociado'
};

const STATUS_VARIANTS = {
  pendente: 'primary',
  parcial:  'warning',
  recebido: 'success',
  vencido:  'danger',
  estornado: 'neutral',
  cancelado: 'neutral',
  renegociado: 'neutral'
};

const statusLabel  = computed(() => STATUS_LABELS[props.installment.status] || props.installment.status);
const badgeVariant = computed(() => STATUS_VARIANTS[props.installment.status] || 'neutral');
const formattedDate = computed(() => formatDate(props.installment.due_date));
const modifier = computed(() => props.installment.status === 'vencido' ? 'pp-inst-card--overdue' : '');
</script>

<style scoped>
.pp-inst-card {
  display: flex; align-items: center; gap: 12px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  padding: 14px; text-decoration: none; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-inst-card:hover  { box-shadow: 0 4px 12px rgba(15, 23, 42, .06); border-color: var(--pp-color-primary); }
.pp-inst-card:active { transform: scale(0.99); }
.pp-inst-card--overdue { border-color: #fecaca; background: #fef2f2; }

.pp-inst-card__leading {
  flex-shrink: 0; min-width: 70px;
  display: flex; flex-direction: column; gap: 2px;
}
.pp-inst-card__num  { font-size: 11px; font-weight: 700; color: var(--pp-color-text-muted); text-transform: uppercase; letter-spacing: 1px; }
.pp-inst-card__date { font-size: 13px; font-weight: 600; color: var(--pp-color-text); }

.pp-inst-card__body { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 4px; }
.pp-inst-card__amount { font-size: 16px; font-weight: 700; color: var(--pp-color-text); }
.pp-inst-card__body :deep(.pp-badge) { align-self: flex-start; }

.pp-inst-card__chevron { color: var(--pp-color-text-muted); flex-shrink: 0; }
</style>
