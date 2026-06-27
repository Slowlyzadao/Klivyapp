<script setup>
/**
 * CreateEstimateModal — modal de "Novo Lançamento" (enxuto, decisão 2026-05-28).
 *
 * Antes pedia 7 campos (tipo, subtotal, parcelas, desconto, método, vencimento,
 * observações). Wizard PaymentPlanWizardV2 já pergunta 4 deles de novo
 * (parcelas, desconto, método, vencimento) com controle por-parcela mais fino.
 *
 * Modal enxuto: TIPO + SUBTOTAL + OBSERVAÇÕES. Resto é resolvido depois:
 *   - À vista → cria Budget + aprova direto (1 parcela) → fica em A Receber
 *   - Parcelado → cria Budget (rascunho) + abre o wizard pra customizar tudo
 *
 * O tipo "Mensalidade" SAIU daqui — virou contrato recorrente real em
 * `Financial::RecurringBilling` (tela própria "Mensalidades fixas").
 */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import {
  parseCurrencyInput,
  onSubtotalInput,
} from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';

const props = defineProps({
  open: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();

const blankForm = () => ({
  // Apenas 2 tipos agora — mensalidade virou contrato recorrente em tela
  // separada (Financial::RecurringBilling).
  recurrence_type: 'avulso',
  notes: '',
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

const recurrenceTypeOptions = computed(() => [
  {
    value: 'avulso',
    label: t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.AVULSO'),
  },
  {
    value: 'parcelamento',
    label: t('PATIENT_FINANCIAL.TIMELINE.RECURRENCE.PARCELAMENTO'),
  },
]);

// Hint contextual abaixo do select de tipo — diz o que vai acontecer ao
// confirmar (transparência de ação).
const typeHint = computed(() => {
  if (form.value.recurrence_type === 'avulso') {
    return 'Lançamento único de 1 parcela. Já cria e aprova — fica disponível em A Receber pra você receber quando for pago.';
  }
  return 'No próximo passo você define parcelas, formas de pagamento, vencimentos e descontos por linha (wizard Configurar pagamento).';
});

const handleSubtotalInput = e => onSubtotalInput(e, subtotalRaw);

const confirmLabel = computed(() =>
  form.value.recurrence_type === 'avulso'
    ? 'Criar e aprovar'
    : 'Configurar pagamento',
);
const confirmIcon = computed(() =>
  form.value.recurrence_type === 'avulso'
    ? 'i-lucide-check-circle-2'
    : 'i-lucide-chevron-right',
);

const handleConfirm = () => {
  emit('confirm', {
    recurrence_type: form.value.recurrence_type,
    subtotal: parseCurrencyInput(subtotalRaw.value),
    notes: form.value.notes,
    // Campos antigos zerados/default — wizard cuida deles (decisão 2026-05-28).
    discount_type: 'fixo',
    discount_value: 0,
    installments_count: form.value.recurrence_type === 'avulso' ? 1 : 2,
    payment_method_id: null,
    payment_method: null,
    valid_until: new Date(Date.now() + 30 * 864e5).toISOString().split('T')[0],
  });
};
</script>

<template>
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-stretch justify-center bg-black/70 backdrop-blur-sm sm:items-center sm:p-4"
  >
    <div
      class="bg-slate-900 border-0 border-slate-700 shadow-2xl w-full h-full flex flex-col overflow-hidden sm:max-w-md sm:h-auto sm:max-h-[calc(100vh-32px)] sm:rounded-2xl sm:border"
    >
      <div
        class="flex-shrink-0 flex items-center justify-between p-6 border-b border-slate-700/50"
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

      <!-- Body com scroll interno -->
      <div class="flex-1 overflow-y-auto p-6 space-y-4">
        <!-- Tipo de lançamento -->
        <div>
          <label class="block text-sm font-medium text-slate-300 mb-1.5">
            {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.RECURRENCE_TYPE_LABEL') }}
          </label>
          <FormSelect
            v-model="form.recurrence_type"
            :options="recurrenceTypeOptions"
          />
          <p class="text-xs text-slate-400 mt-2 leading-relaxed">
            <i class="i-lucide-info w-3 h-3 inline-block mr-1 align-text-bottom" />
            {{ typeHint }}
          </p>
        </div>

        <!-- Subtotal -->
        <div>
          <label class="block text-sm font-medium text-slate-300 mb-1.5">
            {{ t('PATIENT_FINANCIAL.MODALS.ESTIMATE.SUBTOTAL') }}*
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

        <!-- Observações -->
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

        <!-- Preview discreto do subtotal -->
        <div
          v-if="subtotalRaw"
          class="bg-slate-800/50 border border-slate-700/50 rounded-xl p-3 flex items-center justify-between"
        >
          <span class="text-xs text-slate-400">
            {{ t('PATIENT_FINANCIAL.ESTIMATES.SUBTOTAL') }}
          </span>
          <strong class="text-sm font-bold text-slate-100 font-mono">
            R$ {{ subtotalRaw }}
          </strong>
        </div>
      </div>

      <div class="flex-shrink-0 p-6 border-t border-slate-700/50 flex justify-end gap-3">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_FINANCIAL.MODALS.ESTIMATE.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="blue"
          :icon="confirmIcon"
          :label="confirmLabel"
          :is-loading="loading"
          :disabled="loading || !subtotalRaw"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
