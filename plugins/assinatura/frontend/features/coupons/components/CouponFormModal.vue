<script setup>
import { computed } from 'vue';
import { COUPON_KINDS } from '../../../shared/constants.js';
import AsIcon from '../../../shared/AsIcon.vue';

const props = defineProps({
  form:      { type: Object, required: true },
  editingId: { type: Number, default: null },
  saving:    { type: Boolean, default: false },
  error:     { type: String, default: null },
});

const emit = defineEmits(['save', 'close', 'generate-code']);

const isPercent      = computed(() => props.form.kind === 'percent');
const isFixedValue   = computed(() => props.form.kind === 'fixed_value');
const isTrial        = computed(() => props.form.kind === 'trial');
const isFreeForever  = computed(() => props.form.kind === 'free_forever');
const title          = computed(() => props.editingId ? 'Editar Cupom' : 'Novo Cupom');
</script>

<template>
  <div class="as-modal-backdrop" @click.self="$emit('close')">
    <div class="as-modal">
      <div class="as-modal__header">
        <h2 class="as-modal__title">{{ title }}</h2>
        <button type="button" class="reset-base as-modal__close" @click="$emit('close')">
          <AsIcon name="close" :size="16" />
        </button>
      </div>

      <div class="as-modal__body">
        <div v-if="error" class="as-alert as-alert--error">{{ error }}</div>

        <div class="as-form-grid">
          <!-- Código -->
          <div class="as-field">
            <label class="as-label">Código <span class="as-required">*</span></label>
            <div class="as-input-group">
              <input v-model="form.code" class="as-input" type="text" placeholder="EX: PROMO50" style="text-transform:uppercase" />
              <button type="button" class="reset-base as-btn as-btn--ghost as-btn--sm" title="Gerar código aleatório" @click="$emit('generate-code')">
                <AsIcon name="refresh" :size="14" />
              </button>
            </div>
          </div>

          <!-- Tipo -->
          <div class="as-field">
            <label class="as-label">Tipo <span class="as-required">*</span></label>
            <select v-model="form.kind" class="as-select">
              <option v-for="k in COUPON_KINDS" :key="k.value" :value="k.value">
                {{ k.label }}
              </option>
            </select>
          </div>

          <!-- Descrição -->
          <div class="as-field as-field--full">
            <label class="as-label">Descrição <span class="as-required">*</span></label>
            <input v-model="form.description" class="as-input" type="text" placeholder="Ex: 50% de desconto por 3 meses" />
          </div>

          <!-- Campos condicionais: Trial -->
          <template v-if="isTrial">
            <div class="as-field">
              <label class="as-label">Dias de trial <span class="as-required">*</span></label>
              <input v-model="form.trial_days" class="as-input" type="number" min="1" placeholder="Ex: 7, 14, 30" />
            </div>
          </template>

          <!-- Campos condicionais: Percent -->
          <template v-if="isPercent">
            <div class="as-field">
              <label class="as-label">Desconto (%) <span class="as-required">*</span></label>
              <input v-model="form.discount_percent" class="as-input" type="number" min="1" max="100" placeholder="Ex: 50" />
            </div>
            <div class="as-field">
              <label class="as-label">Duração (meses) <span class="as-required">*</span></label>
              <input v-model="form.months_duration" class="as-input" type="number" min="1" placeholder="Ex: 1, 3, 6, 12" />
            </div>
          </template>

          <!-- Campos condicionais: Fixed value -->
          <template v-if="isFixedValue">
            <div class="as-field">
              <label class="as-label">Desconto (R$) <span class="as-required">*</span></label>
              <input v-model="form.discount_amount" class="as-input" type="number" min="0.01" step="0.01" placeholder="Ex: 50,00" />
            </div>
            <div class="as-field">
              <label class="as-label">Duração (meses) <span class="as-required">*</span></label>
              <input v-model="form.months_duration" class="as-input" type="number" min="1" placeholder="Ex: 1, 3, 6, 12" />
            </div>
          </template>

          <!-- Campos condicionais: Free forever -->
          <template v-if="isFreeForever">
            <div class="as-field as-field--full">
              <div class="coupon-free-badge">
                <AsIcon name="star" :size="14" />
                Grátis para sempre — sem campos adicionais necessários.
              </div>
            </div>
          </template>

          <!-- Separador de configurações opcionais -->
          <div class="as-field as-field--full">
            <div class="as-section-divider">Configurações opcionais</div>
          </div>

          <!-- Máx. usos -->
          <div class="as-field">
            <label class="as-label">Máximo de usos</label>
            <input v-model="form.max_uses" class="as-input" type="number" min="1" placeholder="Ilimitado se vazio" />
          </div>

          <!-- Expiração -->
          <div class="as-field">
            <label class="as-label">Expira em</label>
            <input v-model="form.expires_at" class="as-input" type="date" />
          </div>

          <!-- Ativo -->
          <div class="as-field as-field--center">
            <label class="as-label">Ativo</label>
            <label class="as-toggle">
              <input v-model="form.active" type="checkbox" />
              <span class="as-toggle__slider" />
            </label>
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
