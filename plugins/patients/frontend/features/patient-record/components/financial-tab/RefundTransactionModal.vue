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
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import FinancialV2 from '@plugins/financial/frontend/features/financial/v2/api/financialV2';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
// PAYMENT_METHOD_OPTIONS removido 2026-05-24 — substituído por lista real
// do backend (Settings → Formas de Pagamento) via PaymentMethodBadge.

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
// Refactor 2026-05-24: paymentMethod agora é o ID do PaymentMethod (number)
// OU 'credit' (string especial pra estorno-como-crédito). Compat preservada
// no emit('confirm') que deriva o kind do método selecionado.
const paymentMethod = ref('');
const errorMsg = ref('');

// Lista REAL de payment_methods + opção especial "credit" no topo.
const paymentMethods = ref([]);
async function loadPaymentMethods() {
  try {
    const { data } = await FinancialV2.paymentMethods.index({ status: 'active' });
    paymentMethods.value = (data?.data || []).filter(m => m.status === 'active');
  } catch {
    paymentMethods.value = [];
  }
}

// Opções com "Crédito do paciente" em destaque no topo (`raw: null` distingue
// no slot — quando raw é null, renderiza label especial em vez de PaymentMethodBadge).
const refundMethodOptions = computed(() => {
  const real = [...paymentMethods.value].sort((a, b) => {
    const pa = (a.provider || '').trim();
    const pb = (b.provider || '').trim();
    if (!pa && pb) return -1;
    if (pa && !pb) return 1;
    if (pa !== pb) return pa.localeCompare(pb, 'pt-BR');
    return (a.name || '').localeCompare(b.name || '', 'pt-BR');
  }).map(m => ({
    value: m.id,
    label: m.name,
    hint: (m.provider_alias || m.provider || '').trim() || null,
    raw: m,
  }));
  return [
    { value: 'credit', label: '★ Lançar como crédito do paciente (sem saída de caixa)', raw: null },
    ...real,
  ];
});

const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find(m => m.id === paymentMethod.value) || null,
);

const isCreditRefund = computed(() => paymentMethod.value === 'credit');

const originalAmount = computed(() =>
  Number(props.transaction?.amount || 0)
);

watch(
  () => props.open,
  async isOpen => {
    if (!isOpen) return;
    // Pré-preenche com valor original. Carrega payment_methods reais e
    // resolve método pelo `payment_method_id` (se vier) ou `payment_method`
    // string (fallback — best effort por kind).
    amountStr.value = originalAmount.value.toFixed(2).replace('.', ',');
    notes.value = '';
    errorMsg.value = '';
    await loadPaymentMethods();
    const tx = props.transaction;
    if (tx?.payment_method_id) {
      paymentMethod.value = tx.payment_method_id;
    } else if (tx?.payment_method) {
      const match = paymentMethods.value.find(m => m.kind === tx.payment_method && !m.provider)
                  || paymentMethods.value.find(m => m.kind === tx.payment_method);
      paymentMethod.value = match?.id || '';
    } else {
      paymentMethod.value = '';
    }
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
    // Caso contrário, envia kind canon derivado do PaymentMethod selecionado +
    // payment_method_id pra rastreabilidade (refactor 2026-05-24).
    payment_method: isCreditRefund.value ? null : (selectedPaymentMethod.value?.kind || null),
    payment_method_id: isCreditRefund.value ? null : (selectedPaymentMethod.value?.id || null),
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
            auto-searchable
          >
            <template #selected="{ option }">
              <!-- Opção "credit" especial (raw=null) renderiza label cru.
                   Demais usam PaymentMethodBadge canon. -->
              <span v-if="option && !option.raw" class="fin-refund-credit-label">
                <i class="i-lucide-wallet w-3.5 h-3.5" />
                Crédito do paciente
              </span>
              <PaymentMethodBadge
                v-else-if="option?.raw"
                :kind="option.raw.kind"
                :method="option.raw"
                size="sm"
                hide-installments
              />
            </template>
            <template #option="{ option }">
              <span v-if="!option.raw" class="fin-refund-credit-label">
                <i class="i-lucide-wallet w-3.5 h-3.5" />
                <strong>Crédito do paciente</strong>
                <span class="fin-refund-credit-hint">sem saída de caixa</span>
              </span>
              <template v-else>
                <PaymentMethodBadge
                  :kind="option.raw.kind"
                  :method="option.raw"
                  size="sm"
                  hide-installments
                />
                <span v-if="option.hint" class="fin-refund-pm-hint">
                  <i class="i-lucide-building-2 w-3 h-3" /> {{ option.hint }}
                </span>
              </template>
            </template>
          </FormSelect>
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

<style scoped lang="scss">
/* Refactor 2026-05-24 — estilos pra opção especial "Crédito do paciente"
 * no dropdown de método de estorno + hint do provedor nos métodos reais. */
.fin-refund-credit-label {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  color: rgb(var(--emerald-11));
  font-weight: 500;

  i { color: rgb(var(--emerald-10)); }
  strong { font-weight: 600; }
}
.fin-refund-credit-hint {
  font-size: 10.5px;
  font-weight: 400;
  color: rgb(var(--slate-9));
  font-style: italic;
  margin-left: 4px;
}
.fin-refund-pm-hint {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-weight: 500;
  white-space: nowrap;
  i { opacity: 0.7; }
}
</style>
