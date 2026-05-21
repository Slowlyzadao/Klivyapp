<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  formatCurrency,
  parseCurrencyInput,
  onSubtotalInput,
} from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import {
  DISCOUNT_TYPE_OPTIONS,
  PAYMENT_METHOD_OPTIONS,
} from '@plugins/patients/frontend/constants/financial';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();

const blankForm = () => ({
  // PR 3 do refactor 2026-05-06: discriminador semântico que separa
  // `avulso` (1 parcela), `parcelamento` (N parcelas com fim) e
  // `mensalidade` (recorrência — UX premium hoje, motor automático
  // em versão futura). Default `avulso` mantém comportamento de modal
  // legado pra qualquer caller que não conheça o campo.
  recurrence_type: 'avulso',
  discount_type: 'fixo',
  discount_value: 0,
  installments_count: 1,
  payment_method: 'pix',
  notes: '',
  valid_until: new Date(Date.now() + 30 * 864e5).toISOString().split('T')[0],
});

const subtotalRaw = ref('');
const form = ref(blankForm());

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      subtotalRaw.value = '';
      form.value = blankForm();
    }
  }
);

const localizedDiscountOptions = computed(() =>
  DISCOUNT_TYPE_OPTIONS.map(o => ({
    value: o.value,
    label: o.labelKey ? t(o.labelKey) : o.label,
  }))
);

const localizedMethodOptions = computed(() =>
  PAYMENT_METHOD_OPTIONS.map(o => ({ value: o.value, label: o.label }))
);

// Seletor de tipo de recorrência. Quando muda, ajusta `installments_count`
// pra dar uma UX inteligente (avulso = 1, mensalidade default = 12).
const recurrenceTypeOptions = computed(() => [
  {
    value: 'avulso',
    label: t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.AVULSO'),
  },
  {
    value: 'parcelamento',
    label: t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.PARCELAMENTO'),
  },
  {
    value: 'mensalidade',
    label: t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.MENSALIDADE'),
  },
]);

watch(
  () => form.value.recurrence_type,
  newType => {
    if (newType === 'avulso') {
      form.value.installments_count = 1;
    } else if (newType === 'mensalidade' && form.value.installments_count <= 1) {
      form.value.installments_count = 12;
    } else if (newType === 'parcelamento' && form.value.installments_count <= 1) {
      form.value.installments_count = 4;
    }
  }
);

const handleSubtotalInput = e => onSubtotalInput(e, subtotalRaw);

const previewInstallment = computed(() => {
  const subtotal = parseCurrencyInput(subtotalRaw.value);
  const count = parseInt(form.value.installments_count, 10) || 1;
  return formatCurrency(subtotal / count);
});

const handleConfirm = () => {
  emit('confirm', {
    recurrence_type: form.value.recurrence_type,
    subtotal: parseCurrencyInput(subtotalRaw.value),
    discount_type: form.value.discount_type,
    discount_value: parseCurrencyInput(form.value.discount_value) || 0,
    installments_count: parseInt(form.value.installments_count, 10) || 1,
    payment_method: form.value.payment_method,
    notes: form.value.notes,
    valid_until: form.value.valid_until,
  });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm"
  >
    <div
      class="bg-slate-900 border border-slate-700 rounded-2xl shadow-2xl w-full max-w-lg"
    >
      <div
        class="flex items-center justify-between p-6 border-b border-slate-700/50"
      >
        <div>
          <h3
            class="text-lg font-semibold text-slate-100 flex items-center gap-2"
          >
            <i class="i-lucide-file-plus text-blue-400" />
            {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.TITLE') }}
          </h3>
          <p class="text-xs text-slate-400 mt-0.5">
            {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.SUBTITLE') }}
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </div>

      <div class="p-6 space-y-4">
        <!-- Tipo de lançamento (PR 3 do refactor 2026-05-06) -->
        <div>
          <label class="block text-sm font-medium text-slate-300 mb-1.5">
            {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.RECURRENCE_TYPE_LABEL') }}
            <Tooltip
              v-if="form.recurrence_type === 'mensalidade'"
              :label="t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.MENSALIDADE_TOOLTIP')"
              position="right"
            >
              <i class="i-lucide-info w-3 h-3 text-slate-400 ml-1" />
            </Tooltip>
          </label>
          <FormSelect
            v-model="form.recurrence_type"
            :options="recurrenceTypeOptions"
          />
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.SUBTOTAL') }}
            </label>
            <div class="relative">
              <span
                class="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400 text-sm font-medium z-10 pointer-events-none"
              >R$</span>
              <input
                :value="subtotalRaw"
                type="text"
                inputmode="numeric"
                placeholder="0,00"
                style="padding-left: 2.25rem !important"
                class="form-input w-full font-mono"
                @input="handleSubtotalInput"
              />
            </div>
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.INSTALLMENTS') }}
            </label>
            <input
              v-model="form.installments_count"
              type="number"
              min="1"
              max="60"
              class="form-input w-full"
              :disabled="form.recurrence_type === 'avulso'"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.DISCOUNT_TYPE') }}
            </label>
            <FormSelect
              v-model="form.discount_type"
              :options="localizedDiscountOptions"
              :placeholder="
                t('PATIENT_FINANCIAL.MODALS.ESTIMATE.DISCOUNT_PLACEHOLDER')
              "
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.DISCOUNT_VALUE') }}
            </label>
            <input
              v-model="form.discount_value"
              type="number"
              step="0.01"
              min="0"
              class="form-input w-full"
            />
          </div>
        </div>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.DEFAULT_METHOD') }}
            </label>
            <FormSelect
              v-model="form.payment_method"
              :options="localizedMethodOptions"
              :placeholder="
                t('PATIENT_FINANCIAL.MODALS.ESTIMATE.METHOD_PLACEHOLDER')
              "
            />
          </div>
          <div>
            <label class="block text-sm font-medium text-slate-300 mb-1.5">
              {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.FIRST_DUE') }}
            </label>
            <DatePickerBR
              v-model="form.valid_until"
              :placeholder="
                t('PATIENT_FINANCIAL.MODALS.ESTIMATE.DATE_PLACEHOLDER')
              "
            />
          </div>
        </div>

        <div>
          <label class="block text-sm font-medium text-slate-300 mb-1.5">
            {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.NOTES') }}
          </label>
          <textarea
            v-model="form.notes"
            rows="2"
            :placeholder="
              t('PATIENT_FINANCIAL.MODALS.ESTIMATE.NOTES_PLACEHOLDER')
            "
            class="form-input w-full resize-none"
          />
        </div>

        <div
          v-if="subtotalRaw"
          class="bg-slate-800/50 border border-slate-700/50 rounded-xl p-3 flex items-center justify-between"
        >
          <div class="text-xs text-slate-400">
            <span>
              {{ t('PATIENT_FINANCIAL.ESTIMATES.SUBTOTAL') }}:
              <strong class="text-slate-200">R$ {{ subtotalRaw }}</strong>
            </span>
            <span v-if="form.discount_value > 0" class="ml-3 text-red-400">
              - {{ t('PATIENT_FINANCIAL.ESTIMATES.DISCOUNT') }}:
              {{
                form.discount_type === 'percentual'
                  ? form.discount_value + '%'
                  : 'R$ ' + form.discount_value
              }}
            </span>
          </div>
          <div class="text-right">
            <p class="text-xs text-slate-400">
              {{
                t('PATIENT_FINANCIAL.MODALS.ESTIMATE.PREVIEW_INSTALLMENTS', {
                  count: form.installments_count,
                })
              }}
            </p>
            <p class="text-sm font-bold text-emerald-400 font-mono">
              {{ previewInstallment }}
            </p>
          </div>
        </div>
      </div>

      <div class="p-6 border-t border-slate-700/50 flex justify-end gap-3">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_FINANCIAL.MODALS.ESTIMATE.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-file-check"
          :label="t('PATIENT_FINANCIAL.MODALS.ESTIMATE.CONFIRM')"
          :is-loading="loading"
          :disabled="loading || !subtotalRaw"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
