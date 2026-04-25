<script setup>
import { computed } from 'vue';
import AsIcon from '../../../shared/AsIcon.vue';

const props = defineProps({
  coupon: { type: Object, required: true },
});

defineEmits(['edit', 'delete']);

const kindLabel = computed(() => ({
  trial:        'Trial',
  percent:      'Desconto %',
  fixed_value:  'Desconto R$',
  free_forever: 'Grátis Sempre',
}[props.coupon.kind] ?? props.coupon.kind));

const kindClass = computed(() => `as-badge--${props.coupon.kind}`);

function formatBRL(value) {
  return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(Number(value));
}

const summaryText = computed(() => {
  const c = props.coupon;
  if (c.kind === 'trial') return `${c.trial_days} dias grátis`;
  if (c.kind === 'percent') return `${c.discount_percent}% OFF por ${c.months_duration} ${c.months_duration === 1 ? 'mês' : 'meses'}`;
  if (c.kind === 'fixed_value') return `${formatBRL(c.discount_amount)} OFF por ${c.months_duration} ${c.months_duration === 1 ? 'mês' : 'meses'}`;
  if (c.kind === 'free_forever') return 'Grátis para sempre';
  return '—';
});

const usageText = computed(() => {
  const c = props.coupon;
  if (c.max_uses) return `${c.current_uses} / ${c.max_uses} usos`;
  return `${c.current_uses} usos (ilimitado)`;
});

const expiryText = computed(() => {
  if (!props.coupon.expires_at) return null;
  return new Date(props.coupon.expires_at).toLocaleDateString('pt-BR');
});

const isExpired = computed(() => {
  if (!props.coupon.expires_at) return false;
  return new Date(props.coupon.expires_at) < new Date();
});
</script>

<template>
  <div class="coupon-card" :class="{ 'coupon-card--inactive': !coupon.active }">
    <div class="coupon-card__left">
      <div class="coupon-card__code">{{ coupon.code }}</div>
      <div class="coupon-card__description">{{ coupon.description }}</div>
    </div>

    <div class="coupon-card__center">
      <span class="as-badge" :class="kindClass">{{ kindLabel }}</span>
      <span class="coupon-card__summary">{{ summaryText }}</span>
    </div>

    <div class="coupon-card__meta">
      <span class="coupon-card__usage">
        <AsIcon name="user" :size="13" /> {{ usageText }}
      </span>
      <span v-if="expiryText" class="coupon-card__expiry" :class="{ 'coupon-card__expiry--expired': isExpired }">
        <AsIcon name="calendar" :size="13" /> {{ isExpired ? 'Expirado em' : 'Expira em' }} {{ expiryText }}
      </span>
      <span v-if="!coupon.active" class="as-badge as-badge--inactive">Inativo</span>
    </div>

    <div class="coupon-card__actions">
      <button
        type="button"
        class="reset-base plan-card__action-btn"
        title="Editar cupom"
        @click="$emit('edit', coupon)"
      >
        <AsIcon name="edit" :size="14" />
        <span class="plan-card__action-label">Editar</span>
      </button>
      <button
        type="button"
        class="reset-base plan-card__action-btn plan-card__action-btn--danger"
        title="Excluir cupom"
        @click="$emit('delete', coupon)"
      >
        <AsIcon name="trash" :size="14" />
        <span class="plan-card__action-label">Excluir</span>
      </button>
    </div>
  </div>
</template>
