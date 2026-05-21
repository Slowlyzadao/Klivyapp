<script setup>
/**
 * RefundTransactionModal — modal de confirmação de estorno com campos
 * editáveis (substitui o `ConfirmDangerModal` simples + `window.confirm`
 * legado em [1.5.4.3]).
 *
 * Permite:
 *   - **Valor a estornar** — default = valor original. Editável pra
 *     reembolso parcial (backend já aceita via param `amount`).
 *   - **Motivo do estorno** — vai pro campo `notes` da nova Transaction
 *     (rastreabilidade pra auditoria, exigência LGPD/CFO).
 *   - **Método de devolução** — default = método original. Permite
 *     "Pago no PIX, devolvido em dinheiro" etc.
 *
 * Confirma → emite `confirm({ amount, notes, payment_method })` que o pai
 * (`FinancialTab`) repassa pro composable `useFinancialActions.refund`.
 */
import { ref, watch, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import { PAYMENT_METHOD_OPTIONS } from '@plugins/patients/frontend/constants/financial';

const props = defineProps({
  open: { type: Boolean, default: false },
  transaction: { type: Object, default: null },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['close', 'confirm']);
const { t } = useI18n();

const amountStr = ref('');
const notes = ref('');
// `paymentMethod` aceita os métodos normais (pix/cartao/etc.) OU o valor
// especial 'credit' que sinaliza "lançar como crédito do paciente". Quando
// 'credit' é selecionado, o backend NÃO lança saída de caixa — apenas cria
// PatientCredit positivo (origin: 'estorno'). Útil quando paciente concordou
// em deixar saldo a favor em vez de receber devolução real.
const paymentMethod = ref('');
const errorMsg = ref('');

// Opções com "Crédito do paciente" em destaque no topo. Distingue refund
// por método (saída real) vs estorno-como-crédito (saldo a favor).
const refundMethodOptions = computed(() => [
  { value: 'credit', label: '★ Lançar como crédito do paciente (sem saída de caixa)' },
  ...PAYMENT_METHOD_OPTIONS,
]);

const isCreditRefund = computed(() => paymentMethod.value === 'credit');

const originalAmount = computed(() =>
  Number(props.transaction?.amount || 0)
);

watch(
  () => props.open,
  isOpen => {
    if (!isOpen) return;
    // Pré-preenche com valor e método originais. User pode editar.
    amountStr.value = originalAmount.value.toFixed(2).replace('.', ',');
    notes.value = '';
    paymentMethod.value = props.transaction?.payment_method || 'pix';
    errorMsg.value = '';
  },
  { immediate: true }
);

const parsedAmount = computed(() => {
  const cleaned = String(amountStr.value).replace(/\./g, '').replace(',', '.');
  const n = Number.parseFloat(cleaned);
  return Number.isFinite(n) ? n : 0;
});

const isPartial = computed(
  () => parsedAmount.value > 0 && parsedAmount.value < originalAmount.value
);

const handleConfirm = () => {
  errorMsg.value = '';
  if (parsedAmount.value <= 0) {
    errorMsg.value = t('PATIENT_FINANCIAL.REFUND_MODAL.ERROR_AMOUNT_REQUIRED');
    return;
  }
  if (parsedAmount.value > originalAmount.value) {
    errorMsg.value = t('PATIENT_FINANCIAL.REFUND_MODAL.ERROR_AMOUNT_EXCEEDS');
    return;
  }
  // Backend espera `amount_cents` (BIGINT). Converte do BRL parseado.
  const amountCents = Math.round(parsedAmount.value * 100);
  emit('confirm', {
    amount_cents: amountCents,
    notes: notes.value.trim() || null,
    // Em estorno-como-crédito não envia método (não há saída pelo método).
    payment_method: isCreditRefund.value ? null : (paymentMethod.value || null),
    generate_patient_credit: isCreditRefund.value,
  });
};
</script>

<template>
  <!-- Padrão de modal responsivo do Klivy: full-screen no mobile, centralizado
       e limitado no desktop. Mesma régua usada no PlanDetailsModal e no
       EditInstallmentModal. -->
  <div
    v-if="open"
    class="fixed inset-0 z-50 flex items-stretch sm:items-center justify-center sm:p-4 bg-black/80 backdrop-blur-md"
  >
    <div
      class="evo-erratum-modal w-full sm:max-w-lg
             h-full sm:h-auto sm:max-h-[calc(100vh-2rem)]
             rounded-none sm:rounded-2xl
             border-0 sm:border
             flex flex-col"
    >
      <div class="evo-modal-header">
        <h4 class="text-base font-semibold text-slate-100">
          {{ t('PATIENT_FINANCIAL.REFUND_MODAL.TITLE') }}
        </h4>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          :disabled="loading"
          @click="emit('close')"
        />
      </div>

      <div class="evo-modal-body flex-1 overflow-y-auto">
        <!-- Contexto da transação original (read-only) -->
        <div class="fin-refund-context">
          <div>
            <span class="fin-refund-context-label">
              {{ t('PATIENT_FINANCIAL.REFUND_MODAL.ORIGINAL_AMOUNT') }}
            </span>
            <span class="fin-refund-context-value">
              {{ formatCurrency(originalAmount) }}
            </span>
          </div>
          <div v-if="transaction?.description">
            <span class="fin-refund-context-label">
              {{ t('PATIENT_FINANCIAL.REFUND_MODAL.DESCRIPTION') }}
            </span>
            <span class="fin-refund-context-value">
              {{ transaction.description }}
            </span>
          </div>
        </div>

        <!-- Valor a estornar -->
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_FINANCIAL.REFUND_MODAL.AMOUNT_LABEL') }}
          </label>
          <input
            v-model="amountStr"
            type="text"
            class="form-input"
            inputmode="decimal"
            placeholder="0,00"
            :disabled="loading"
          />
          <p v-if="isPartial" class="form-hint fin-refund-hint--partial">
            <i class="i-lucide-info w-3 h-3" />
            {{
              t('PATIENT_FINANCIAL.REFUND_MODAL.PARTIAL_HINT', {
                remaining: formatCurrency(originalAmount - parsedAmount),
              })
            }}
          </p>
        </div>

        <!-- Método de devolução: aceita método normal (saída de caixa) ou
             "Crédito do paciente" (sem saída — vira saldo a favor).
             Usa FormSelect (padrão Klivy) em vez de <select> nativo. -->
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_FINANCIAL.REFUND_MODAL.METHOD_LABEL') }}
          </label>
          <FormSelect
            v-model="paymentMethod"
            :options="refundMethodOptions"
            :disabled="loading"
            placeholder="Selecione o método"
          />
          <p
            v-if="isCreditRefund"
            class="form-hint fin-refund-hint--credit"
          >
            <i class="i-lucide-wallet w-3 h-3" />
            O dinheiro <strong>não sai do caixa</strong>. Vira saldo do paciente
            ({{ formatCurrency(parsedAmount) }}) para abater em parcela futura.
          </p>
        </div>

        <!-- Motivo (vai pra notes) -->
        <div class="form-group">
          <label class="form-label">
            {{ t('PATIENT_FINANCIAL.REFUND_MODAL.REASON_LABEL') }}
            <span class="form-label-optional">
              ({{ t('PATIENT_FINANCIAL.REFUND_MODAL.OPTIONAL') }})
            </span>
          </label>
          <textarea
            v-model="notes"
            rows="3"
            class="form-input"
            :placeholder="t('PATIENT_FINANCIAL.REFUND_MODAL.REASON_PLACEHOLDER')"
            :disabled="loading"
          />
          <p class="form-hint">
            {{ t('PATIENT_FINANCIAL.REFUND_MODAL.REASON_HINT') }}
          </p>
        </div>

        <p v-if="errorMsg" class="fin-refund-error">{{ errorMsg }}</p>

        <p class="fin-refund-warning">
          <i class="i-lucide-alert-triangle w-3.5 h-3.5" />
          {{ t('PATIENT_FINANCIAL.REFUND_MODAL.IRREVERSIBLE_WARNING') }}
        </p>
      </div>

      <div class="evo-modal-footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_FINANCIAL.REFUND_MODAL.CANCEL')"
          :disabled="loading"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="ruby"
          icon="i-lucide-undo"
          :label="t('PATIENT_FINANCIAL.REFUND_MODAL.CONFIRM')"
          :is-loading="loading"
          :disabled="loading"
          @click="handleConfirm"
        />
      </div>
    </div>
  </div>
</template>
