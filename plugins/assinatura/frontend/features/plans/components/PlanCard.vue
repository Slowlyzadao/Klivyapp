<script setup>
import { ref, computed } from 'vue';
import { PLAN_FEATURES, PLAN_LIMITS, formatPrice, getCheckoutUrl } from '../../../shared/constants.js';
import AsIcon from '../../../shared/AsIcon.vue';

const props = defineProps({
  plan: { type: Object, required: true },
});

const emit = defineEmits(['edit', 'delete']);

const LIMIT_LABELS = Object.fromEntries(PLAN_LIMITS.map(l => [l.key, l.label]));

const activeFeatures = computed(() =>
  PLAN_FEATURES.filter(f => props.plan.features?.includes(f.key))
);

const yearlyLabel = computed(() =>
  props.plan.price_yearly ? formatPrice(props.plan.price_yearly) + '/ano' : null
);

const planLimits = computed(() =>
  Object.entries(props.plan.limits || {}).filter(([, v]) => v != null)
);

const checkoutUrl = computed(() => getCheckoutUrl(props.plan));

const copied = ref(false);

function copyLink() {
  navigator.clipboard.writeText(checkoutUrl.value);
  copied.value = true;
  setTimeout(() => { copied.value = false; }, 2000);
}
</script>

<template>
  <div class="plan-card" :style="{ '--plan-color': plan.color }">
    <div class="plan-card__header">
      <div class="plan-card__color-bar" />
      <div class="plan-card__badges">
        <span v-if="!plan.active" class="plan-card__badge plan-card__badge--inactive">
          Inativo
        </span>
      </div>
      <div class="plan-card__actions">
        <button
          type="button"
          class="reset-base plan-card__action-btn"
          title="Editar plano"
          @click="$emit('edit', plan)"
        >
          <AsIcon name="edit" :size="16" />
          <span class="plan-card__action-label">Editar</span>
        </button>
        <button
          type="button"
          class="reset-base plan-card__action-btn plan-card__action-btn--danger"
          title="Excluir plano"
          @click="$emit('delete', plan)"
        >
          <AsIcon name="trash" :size="16" />
          <span class="plan-card__action-label">Excluir</span>
        </button>
      </div>
    </div>

    <div class="plan-card__body">
      <h3 class="plan-card__name">{{ plan.name }}</h3>
      <p v-if="plan.description" class="plan-card__description">{{ plan.description }}</p>

      <div class="plan-card__pricing">
        <div class="plan-card__price-main">
          <span class="plan-card__price-value">{{ formatPrice(plan.price_monthly) }}</span>
          <span class="plan-card__price-period">/mês</span>
        </div>
        <div v-if="yearlyLabel" class="plan-card__price-yearly">
          {{ yearlyLabel }}
        </div>
      </div>

      <div v-if="planLimits.length" class="plan-card__limits">
        <div class="plan-card__section-title">Limites</div>
        <div class="plan-card__limits-list">
          <div v-for="[key, val] in planLimits" :key="key" class="plan-card__limit-row">
            <span class="plan-card__limit-name">{{ LIMIT_LABELS[key] || key }}</span>
            <span class="plan-card__limit-val">{{ val.toLocaleString('pt-BR') }}</span>
          </div>
        </div>
      </div>

      <div v-if="activeFeatures.length" class="plan-card__features">
        <div class="plan-card__section-title">Recursos</div>
        <div
          v-for="feature in activeFeatures"
          :key="feature.key"
          class="plan-card__feature"
        >
          <AsIcon :name="feature.icon" :size="14" class="plan-card__feature-icon" />
          <span>{{ feature.label }}</span>
        </div>
      </div>
      <p v-else-if="!planLimits.length" class="plan-card__no-features">Nenhum recurso configurado</p>
    </div>

    <div class="plan-card__footer">
      <span class="plan-card__order">Ordem: {{ plan.display_order }}</span>
      <div class="plan-card__checkout">
        <span class="plan-card__checkout-url" :title="checkoutUrl">{{ checkoutUrl }}</span>
        <button
          type="button"
          class="reset-base plan-card__copy-btn"
          :title="copied ? 'Link copiado!' : 'Copiar link de checkout'"
          @click="copyLink"
        >
          <AsIcon :name="copied ? 'check' : 'copy'" :size="14" />
        </button>
      </div>
    </div>
  </div>
</template>
