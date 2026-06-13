<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';

const props = defineProps({
  open: { type: Boolean, default: false },
  initialItem: { type: Object, default: null },
  agendaServices: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  /**
   * Quando true, footer mostra "Adicionar depois" em vez de "Cancelar"
   * (usado no fluxo após criar um plano novo).
   */
  allowSkip: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'save', 'skip']);

const { t } = useI18n();

const blankItem = () => ({
  id: null,
  agenda_service_id: null,
  procedure_name: '',
  region: '',
  sessions_planned: 1,
  unit_price: 0,
  discount_type: '',
  discount_value: 0,
  notes: '',
});

const item = ref(blankItem());

// PR #6b da auditoria 2026-05-13: ao abrir o modal, resolve qual serviço
// pré-selecionar. Prioridade:
// 1. `agenda_service_id` do item (FK persistida) — imune a rename.
// 2. Match legado por nome — backfill ao salvar via callback do backend.
watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      const base = props.initialItem ? { ...props.initialItem } : blankItem();
      base.unit_price = Number(base.unit_price) || 0;
      base.discount_value = Number(base.discount_value) || 0;
      base.discount_type = base.discount_type || '';
      base.notes = base.notes || '';

      if (base.agenda_service_id == null && base.procedure_name) {
        const matched = (props.agendaServices || []).find(
          s => s.name === base.procedure_name
        );
        if (matched) base.agenda_service_id = matched.id;
      }

      item.value = base;
    }
  }
);

// PR #6b: dropdown carrega o ID do serviço como `value`. Imune a rename:
// editar um item antigo após rename do serviço continua selecionando a
// opção correta (porque `agenda_service_id` é estável).
// PR ID visível (2026-05-14):
// - `badge` discreto à direita exibe o ID (visual padronizado do FormSelect).
// - `hint`: preço SAIU em 2026-05-22 — agora vive em Financial::ServicePricing
//   (1-to-1 com AgendaService). Pra mostrar preço aqui no select de tratamento,
//   um endpoint futuro pode hidratar AgendaService com pricing inline. Hoje,
//   `hint` fica vazio — operador edita `unit_price` direto no item após selecionar.
const serviceOptions = computed(() =>
  (props.agendaServices || []).map(svc => ({
    value: svc.id,
    label: svc.name,
    badge: svc.id,
    hint: '',
  }))
);

const isEdit = computed(() => Boolean(item.value.id));

// Chamado quando o usuário seleciona um serviço na dropdown (recebe o ID).
// Sincroniza `procedure_name` com o nome ATUAL do serviço (snapshot a ser
// persistido como audit trail histórico). Sincroniza `unit_price` com o
// preço atual do serviço — operador pode editar depois.
const onProcedureSelect = () => {
  const selected = (props.agendaServices || []).find(
    s => s.id === item.value.agenda_service_id
  );
  if (selected) {
    item.value.procedure_name = selected.name;
    item.value.unit_price = Number(selected.price) || 0;
  } else {
    item.value.procedure_name = '';
    item.value.unit_price = 0;
  }
};

// ── Cálculos de subtotal / desconto (espelham o backend) ─────────────
const grossSubtotal = computed(() => {
  const price = Number(item.value.unit_price) || 0;
  const sessions = Number(item.value.sessions_planned) || 0;
  return price * sessions;
});

const discountAmount = computed(() => {
  const value = Number(item.value.discount_value) || 0;
  if (value <= 0 || !item.value.discount_type) return 0;
  if (item.value.discount_type === 'percentual') {
    return grossSubtotal.value * (value / 100);
  }
  return Math.min(value, grossSubtotal.value);
});

const netSubtotal = computed(() =>
  Math.max(grossSubtotal.value - discountAmount.value, 0)
);

const hasDiscount = computed(
  () => Number(item.value.discount_value) > 0 && !!item.value.discount_type
);

const isUnitPricePositive = computed(
  () => Number(item.value.unit_price) > 0
);

const canSubmit = computed(
  () =>
    (Boolean(item.value.agenda_service_id) || Boolean(item.value.procedure_name)) &&
    isUnitPricePositive.value
);

// Toggle entre "sem desconto" / "fixo" / "percentual"
const setDiscountType = type => {
  if (item.value.discount_type === type) {
    item.value.discount_type = '';
    item.value.discount_value = 0;
  } else {
    item.value.discount_type = type;
    if (!item.value.discount_value) item.value.discount_value = 0;
  }
};

const handleSave = () => {
  // Garante que discount_value seja zero se nenhum tipo selecionado.
  const payload = { ...item.value };
  if (!payload.discount_type) payload.discount_value = 0;
  emit('save', payload);
};

const handleClose = () => {
  if (props.allowSkip) emit('skip');
  else emit('close');
};
</script>

<template>
  <div
    v-if="open"
    class="tp-modal-overlay"
  >
    <div class="tp-modal-card">
      <div class="tp-modal-header">
        <div>
          <h3 class="tp-modal-title">
            {{
              isEdit
                ? t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.TITLE_EDIT')
                : t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.TITLE_NEW')
            }}
          </h3>
          <p class="tp-modal-subtitle">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.SUBTITLE') }}
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="handleClose"
        />
      </div>

      <div class="tp-modal-body">
        <div class="tp-field">
          <label class="tp-label">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.PROCEDURE_LABEL') }}
            <span class="tp-required">*</span>
          </label>
          <FormSelect
            v-model="item.agenda_service_id"
            :options="serviceOptions"
            :placeholder="
              t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.PROCEDURE_PLACEHOLDER')
            "
            auto-searchable
            @update:model-value="onProcedureSelect"
          />
        </div>

        <div class="tp-row-2">
          <div class="tp-field">
            <label class="tp-label">
              {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.REGION_LABEL') }}
            </label>
            <input
              v-model="item.region"
              class="tp-input"
              :placeholder="
                t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.REGION_PLACEHOLDER')
              "
            />
          </div>
          <div class="tp-field">
            <label class="tp-label">
              {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.SESSIONS_LABEL') }}
            </label>
            <input
              v-model.number="item.sessions_planned"
              type="number"
              min="1"
              class="tp-input"
            />
          </div>
        </div>

        <div class="tp-field">
          <label class="tp-label">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.UNIT_PRICE_LABEL') }}
            <span class="tp-required">*</span>
          </label>
          <input
            v-model.number="item.unit_price"
            type="number"
            step="0.01"
            min="0"
            class="tp-input"
            :class="{ 'is-invalid': !isUnitPricePositive }"
          />
          <p
            v-if="!isUnitPricePositive"
            class="tp-hint tp-hint--error"
          >
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.UNIT_PRICE_REQUIRED') }}
          </p>
          <p v-else class="tp-hint">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.UNIT_PRICE_HINT') }}
          </p>
        </div>

        <div class="tp-field">
          <label class="tp-label">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.DISCOUNT_LABEL') }}
          </label>
          <div class="tp-discount-row">
            <div class="tp-discount-toggle">
              <button
                type="button"
                class="tp-discount-toggle-btn"
                :class="{ 'is-active': item.discount_type === 'fixo' }"
                @click="setDiscountType('fixo')"
              >
                {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.DISCOUNT_TYPE_FIXO') }}
              </button>
              <button
                type="button"
                class="tp-discount-toggle-btn"
                :class="{ 'is-active': item.discount_type === 'percentual' }"
                @click="setDiscountType('percentual')"
              >
                {{
                  t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.DISCOUNT_TYPE_PERCENTUAL')
                }}
              </button>
            </div>
            <input
              v-model.number="item.discount_value"
              type="number"
              step="0.01"
              min="0"
              :max="item.discount_type === 'percentual' ? 100 : null"
              class="tp-input tp-discount-input"
              :placeholder="
                t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.DISCOUNT_VALUE_PLACEHOLDER')
              "
              :disabled="!item.discount_type"
            />
          </div>
          <p v-if="!item.discount_type" class="tp-hint">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.DISCOUNT_NONE') }}
          </p>
        </div>

        <div class="tp-field">
          <label class="tp-label">
            {{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.NOTES_LABEL') }}
          </label>
          <textarea
            v-model="item.notes"
            class="tp-input tp-textarea"
            rows="3"
            :placeholder="
              t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.NOTES_PLACEHOLDER')
            "
          />
        </div>

        <!-- Resumo de valores -->
        <div class="tp-summary">
          <div class="tp-summary-row">
            <span>{{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.SUMMARY_GROSS') }}</span>
            <span>{{ formatCurrency(grossSubtotal) }}</span>
          </div>
          <div v-if="hasDiscount" class="tp-summary-row tp-summary-row--discount">
            <span>{{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.SUMMARY_DISCOUNT') }}</span>
            <span>− {{ formatCurrency(discountAmount) }}</span>
          </div>
          <div class="tp-summary-row tp-summary-row--total">
            <span>{{ t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.SUMMARY_NET') }}</span>
            <span>{{ formatCurrency(netSubtotal) }}</span>
          </div>
        </div>
      </div>

      <div class="tp-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="
            allowSkip
              ? t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.SKIP')
              : t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.CANCEL')
          "
          @click="handleClose"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-check"
          :label="t('PATIENT_TREATMENT_PLAN.ITEM_MODAL.CONFIRM')"
          :is-loading="loading"
          :disabled="loading || !canSubmit"
          @click="handleSave"
        />
      </div>
    </div>
  </div>
</template>
