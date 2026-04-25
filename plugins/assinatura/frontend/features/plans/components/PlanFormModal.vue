<script setup>
import { PLAN_FEATURES, PLAN_LIMITS, PLAN_COLORS } from '../../../shared/constants.js';
import PlanFeatureItem from './PlanFeatureItem.vue';
import AsIcon from '../../../shared/AsIcon.vue';

const props = defineProps({
  form:      { type: Object, required: true },
  editingId: { type: Number, default: null },
  saving:    { type: Boolean, default: false },
  error:     { type: String, default: null },
});

const emit = defineEmits(['save', 'close', 'toggle-feature']);

const title = () => (props.editingId ? 'Editar Plano' : 'Novo Plano');
</script>

<template>
  <div class="as-modal-backdrop" @click.self="$emit('close')">
    <div class="as-modal">
      <div class="as-modal__header">
        <h2 class="as-modal__title">{{ title() }}</h2>
        <button type="button" class="reset-base as-modal__close" @click="$emit('close')">
          <AsIcon name="close" :size="16" />
        </button>
      </div>

      <div class="as-modal__body">
        <div v-if="error" class="as-alert as-alert--error">{{ error }}</div>

        <div class="as-form-grid">
          <!-- Nome -->
          <div class="as-field as-field--full">
            <label class="as-label">Nome do plano <span class="as-required">*</span></label>
            <input v-model="form.name" class="as-input" type="text" placeholder="Ex: Básico, Pro, Enterprise" />
          </div>

          <!-- Descrição -->
          <div class="as-field as-field--full">
            <label class="as-label">Descrição</label>
            <textarea v-model="form.description" class="as-input as-textarea" rows="2" placeholder="Descrição breve do plano..." />
          </div>

          <!-- Preço Mensal -->
          <div class="as-field">
            <label class="as-label">Preço Mensal (R$) <span class="as-required">*</span></label>
            <input v-model="form.price_monthly" class="as-input" type="number" min="0" step="0.01" placeholder="0,00" />
          </div>

          <!-- Preço Anual -->
          <div class="as-field">
            <label class="as-label">Preço Anual (R$)</label>
            <input v-model="form.price_yearly" class="as-input" type="number" min="0" step="0.01" placeholder="0,00 (opcional)" />
          </div>

          <!-- Ordem de exibição -->
          <div class="as-field">
            <label class="as-label">Ordem de exibição</label>
            <input v-model="form.display_order" class="as-input" type="number" min="0" />
          </div>

          <!-- Ativo -->
          <div class="as-field as-field--center">
            <label class="as-label">Ativo</label>
            <label class="as-toggle">
              <input v-model="form.active" type="checkbox" />
              <span class="as-toggle__slider" />
            </label>
          </div>

          <!-- Cor -->
          <div class="as-field as-field--full">
            <label class="as-label">Cor do plano</label>
            <div class="as-color-picker">
              <button
                v-for="color in PLAN_COLORS"
                :key="color"
                type="button"
                class="reset-base as-color-swatch"
                :class="{ 'as-color-swatch--active': form.color === color }"
                :style="{ background: color }"
                @click="form.color = color"
              />
              <input v-model="form.color" class="as-input as-input--color-text" type="text" placeholder="#5B5BD6" />
            </div>
          </div>

          <!-- Limites do Plano -->
          <div class="as-field as-field--full">
            <label class="as-label">Limites do plano</label>
            <p class="as-hint">Deixe em branco para ilimitado</p>
            <div class="as-limits-grid">
              <div v-for="limit in PLAN_LIMITS" :key="limit.key" class="as-limit-field">
                <label class="as-limit-label">{{ limit.label }}</label>
                <input
                  v-model="form.limits[limit.key]"
                  class="as-input as-input--sm"
                  type="number"
                  min="0"
                  :placeholder="limit.placeholder"
                />
              </div>
            </div>
          </div>

          <!-- Recursos -->
          <div class="as-field as-field--full">
            <label class="as-label">Recursos incluídos</label>
            <div class="as-features-grid">
              <PlanFeatureItem
                v-for="feat in PLAN_FEATURES"
                :key="feat.key"
                :feature-key="feat.key"
                :label="feat.label"
                :icon="feat.icon"
                :checked="form.features.includes(feat.key)"
                @toggle="$emit('toggle-feature', $event)"
              />
            </div>
          </div>
        </div>
      </div>

      <div class="as-modal__footer">
        <button type="button" class="reset-base as-btn as-btn--ghost" :disabled="saving" @click="$emit('close')">
          Cancelar
        </button>
        <button type="button" class="reset-base as-btn as-btn--primary" :disabled="saving" @click="$emit('save')">
          <AsIcon v-if="saving" name="loader" :size="14" class="as-spin" />
          {{ saving ? 'Salvando...' : 'Salvar' }}
        </button>
      </div>
    </div>
  </div>
</template>
