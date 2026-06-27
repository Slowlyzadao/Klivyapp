<script setup>
/**
 * Modal de pagamento de despesa — canon F-21.
 *
 * Substitui o `confirm()` nativo na tela A Pagar. Permite escolher conta,
 * data efetiva, método e ajustar valor (juros/multa/desconto opcionais).
 *
 * Backend: POST /financial/v2/expenses/:id/pay
 * Service: Financial::PayExpense (lança Entry de saída + atualiza expense.status)
 *
 * Props:
 *   - show: Boolean
 *   - expense: Object (Financial::Expense serializada)
 *
 * Eventos:
 *   - close
 *   - confirm: { result } — backend retorna o expense atualizado
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import FinancialV2 from '../api/financialV2';
import { brlInputToCents, formatCurrencyInput, centsToBRL, bankKindLabel } from '../composables/useMoney';

const props = defineProps({
  show: { type: Boolean, default: false },
  expense: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Refactor 2026-05-24: lista de métodos vem do backend (não mais hardcoded).
// Reflete o que a clínica configurou em Settings → Formas de Pagamento.
// Mesmo padrão do ReceivePaymentModalV2.
const paymentMethods = ref([]);
const paymentMethodsLoading = ref(false);
const paymentMethodId = ref(null);

const paidAt = ref(new Date().toISOString().slice(0, 10));
const bankAccountId = ref(null);
const overrideBankAccount = ref(false);
const interestStr = ref('');
const fineStr = ref('');
const discountStr = ref('');

// Modo de entrada R$/% por modificador (padrão de mercado).
const MODE_BRL = 'BRL';
const MODE_PCT = 'PCT';
const interestMode = ref(MODE_BRL);
const fineMode = ref(MODE_BRL);
const discountMode = ref(MODE_BRL);

const notes = ref('');
const submitting = ref(false);
const bankAccounts = ref([]);

function parsePercentToBasisPoints(str) {
  if (!str) return 0;
  const clean = String(str).replace(',', '.').replace(/[^\d.]/g, '');
  const v = parseFloat(clean);
  if (Number.isNaN(v) || v <= 0) return 0;
  return Math.round(v * 100);
}
function bpsToCentsOfGross(bps, gross) {
  if (!bps || !gross) return 0;
  return Math.round((gross * bps) / 10000);
}
function valueAsDecimal(str, mode) {
  if (!str) return 0;
  const clean = String(str).replace(',', '.').replace(/[^\d.]/g, '');
  const v = parseFloat(clean);
  if (Number.isNaN(v) || v <= 0) return 0;
  if (mode === MODE_PCT) return v;
  return Math.round(v * 100) / 100;
}

const bankAccountOptions = computed(() =>
  bankAccounts.value.map(b => ({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` })),
);

const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find(m => m.id === paymentMethodId.value) || null,
);
const selectedKind = computed(() => selectedPaymentMethod.value?.kind || null);

const selectedBankAccount = computed(
  () => bankAccounts.value.find(b => b.id === bankAccountId.value) || null,
);
const showBankAccountInfo = computed(
  () => !!selectedPaymentMethod.value?.default_bank_account_id && !overrideBankAccount.value,
);

// Opções flat pro FormSelect ordenadas por provedor.
const paymentMethodOptions = computed(() => {
  const list = [...paymentMethods.value];
  list.sort((a, b) => {
    const pa = (a.provider || '').trim();
    const pb = (b.provider || '').trim();
    if (!pa && pb) return -1;
    if (pa && !pb) return 1;
    if (pa !== pb) return pa.localeCompare(pb, 'pt-BR');
    return (a.name || '').localeCompare(b.name || '', 'pt-BR');
  });
  return list.map(m => ({
    value: m.id,
    label: m.name,
    hint: (m.provider_alias || m.provider || '').trim() || null,
    raw: m,
  }));
});

const baseCents = computed(() => Number(props.expense?.amount_cents) || 0);

const interestCents = computed(() => {
  if (interestMode.value === MODE_PCT) {
    return bpsToCentsOfGross(parsePercentToBasisPoints(interestStr.value), baseCents.value);
  }
  return brlInputToCents(interestStr.value);
});
const fineCents = computed(() => {
  if (fineMode.value === MODE_PCT) {
    return bpsToCentsOfGross(parsePercentToBasisPoints(fineStr.value), baseCents.value);
  }
  return brlInputToCents(fineStr.value);
});
const discountCents = computed(() => {
  if (discountMode.value === MODE_PCT) {
    return bpsToCentsOfGross(parsePercentToBasisPoints(discountStr.value), baseCents.value);
  }
  return brlInputToCents(discountStr.value);
});

const totalCents = computed(
  () => baseCents.value + interestCents.value + fineCents.value - discountCents.value,
);

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!props.expense?.id) return false;
  if (!bankAccountId.value) return false;
  if (!paymentMethodId.value) return false;
  if (totalCents.value <= 0) return false;
  return true;
});

async function loadBankAccounts() {
  try {
    const { data } = await FinancialV2.bankAccounts.index({ active: 'true' });
    bankAccounts.value = data?.data || [];
    if (bankAccounts.value.length === 1) bankAccountId.value = bankAccounts.value[0].id;
  } catch {
    bankAccounts.value = [];
  }
}

async function loadPaymentMethods() {
  paymentMethodsLoading.value = true;
  try {
    const { data } = await FinancialV2.paymentMethods.index({ status: 'active' });
    paymentMethods.value = (data?.data || []).filter(m => m.status === 'active');
    // Pré-seleciona o método sugerido pela expense (se houver kind compatível)
    // ou PIX direto, ou primeiro da lista.
    const expenseKind = props.expense?.payment_method;
    let preferred = null;
    if (expenseKind) {
      preferred = paymentMethods.value.find(m => m.kind === expenseKind && !m.provider);
      if (!preferred) preferred = paymentMethods.value.find(m => m.kind === expenseKind);
    }
    if (!preferred) preferred = paymentMethods.value.find(m => m.kind === 'pix' && !m.provider);
    paymentMethodId.value = preferred?.id || paymentMethods.value[0]?.id || null;
  } catch {
    paymentMethods.value = [];
    paymentMethodId.value = null;
  } finally {
    paymentMethodsLoading.value = false;
  }
}

function reset() {
  paidAt.value = new Date().toISOString().slice(0, 10);
  interestStr.value = '';
  fineStr.value = '';
  discountStr.value = '';
  interestMode.value = MODE_BRL;
  fineMode.value = MODE_BRL;
  discountMode.value = MODE_BRL;
  notes.value = '';
  submitting.value = false;
  overrideBankAccount.value = false;
  if (bankAccounts.value.length === 1) bankAccountId.value = bankAccounts.value[0].id;
}

watch(
  () => props.show,
  (val) => {
    if (val) {
      reset();
      loadPaymentMethods();
      loadBankAccounts();
    }
  },
);

// Auto-fill conta + saída do override quando troca forma. Mesmo padrão do
// Receber Pagamento — quando forma tem default_bank_account_id usa ele.
watch(selectedPaymentMethod, (method) => {
  if (!method) return;
  overrideBankAccount.value = false;
  if (method.default_bank_account_id) {
    bankAccountId.value = method.default_bank_account_id;
  }
});

onMounted(() => {
  if (props.show) {
    reset();
    loadPaymentMethods();
    loadBankAccounts();
  }
});

function applyMask(event, refToUpdate) {
  const formatted = formatCurrencyInput(event.target.value);
  refToUpdate.value = formatted;
  event.target.value = formatted;
}
function applyPercentMask(event, refToUpdate) {
  let v = String(event.target.value).replace(/[^\d.,]/g, '').replace('.', ',');
  const parts = v.split(',');
  if (parts.length > 2) v = parts[0] + ',' + parts.slice(1).join('');
  const m = v.match(/^(\d+)(?:,(\d{0,2}))?/);
  v = m ? (m[2] !== undefined ? `${m[1]},${m[2]}` : m[1]) : '';
  const num = parseFloat(v.replace(',', '.'));
  if (!Number.isNaN(num) && num >= 100) v = '99,99';
  refToUpdate.value = v;
  event.target.value = v;
}
const onInterestInput = (e) => (interestMode.value === MODE_PCT
  ? applyPercentMask(e, interestStr) : applyMask(e, interestStr));
const onFineInput = (e) => (fineMode.value === MODE_PCT
  ? applyPercentMask(e, fineStr) : applyMask(e, fineStr));
const onDiscountInput = (e) => (discountMode.value === MODE_PCT
  ? applyPercentMask(e, discountStr) : applyMask(e, discountStr));

function setInterestMode(target) {
  if (interestMode.value === target) return;
  interestMode.value = target;
  interestStr.value = '';
}
function setFineMode(target) {
  if (fineMode.value === target) return;
  fineMode.value = target;
  fineStr.value = '';
}
function setDiscountMode(target) {
  if (discountMode.value === target) return;
  discountMode.value = target;
  discountStr.value = '';
}

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      bank_account_id: bankAccountId.value,
      paid_at: paidAt.value,
      // payment_method_id: novo (referência ao método configurado).
      // payment_method: legacy kind. Backend usa _id quando vier, senão fallback.
      payment_method_id: paymentMethodId.value,
      payment_method: selectedKind.value,
      // Modificadores: tipo+value (intenção) + cents (compat). Backend é
      // source of truth — recalcula cents do gross × pct quando type=percent.
      interest_type:  interestMode.value === MODE_PCT ? 'percent' : 'fixed',
      interest_value: valueAsDecimal(interestStr.value, interestMode.value),
      interest_cents: interestCents.value,
      fine_type:      fineMode.value === MODE_PCT ? 'percent' : 'fixed',
      fine_value:     valueAsDecimal(fineStr.value, fineMode.value),
      fine_cents:     fineCents.value,
      discount_type:  discountMode.value === MODE_PCT ? 'percent' : 'fixed',
      discount_value: valueAsDecimal(discountStr.value, discountMode.value),
      discount_cents: discountCents.value,
      notes: notes.value.trim() || null,
    };
    const { data } = await FinancialV2.expenses.pay(props.expense.id, payload);
    notifySuccess('Despesa paga com sucesso.');
    emit('confirm', data);
    emit('close');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao pagar despesa');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="pem-v2__backdrop">
      <div class="pem-v2__modal" role="dialog" aria-modal="true">
        <header class="pem-v2__header">
          <div class="pem-v2__header-text">
            <h2 class="pem-v2__title">
              <i class="i-lucide-receipt pem-v2__title-icon" />
              Pagar despesa
            </h2>
            <p v-if="expense" class="pem-v2__expense-line">
              <strong>{{ expense.description || `Despesa #${expense.id}` }}</strong>
              <span v-if="expense.due_date" class="pem-v2__expense-meta">
                · venc.
                <template v-if="typeof expense.due_date === 'string'">
                  {{ expense.due_date.split('-').reverse().join('/') }}
                </template>
              </span>
            </p>
          </div>
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :disabled="submitting"
            @click="close"
          />
        </header>

        <div class="pem-v2__body">
          <!-- Forma de pagamento — dropdown moderno + PaymentMethodBadge.
               Lista REAL configurada em Settings (não hardcoded). -->
          <section class="pem-v2__section">
            <label class="pem-v2__field-label">Forma de pagamento</label>

            <div v-if="paymentMethodsLoading" class="pem-v2__pm-loading">
              <i class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin" />
              <span>Carregando formas de pagamento…</span>
            </div>

            <div v-else-if="paymentMethods.length === 0" class="pem-v2__hint pem-v2__hint--warn">
              <i class="i-lucide-info w-3.5 h-3.5" />
              Nenhuma forma de pagamento configurada. Vá em Settings → Formas de Pagamento.
            </div>

            <FormSelect
              v-else
              v-model="paymentMethodId"
              :options="paymentMethodOptions"
              placeholder="Selecione a forma"
              auto-searchable
              search-placeholder="Buscar (PIX, Cielo, Stone...)"
            >
              <template #selected="{ option }">
                <PaymentMethodBadge
                  v-if="option?.raw"
                  :kind="option.raw.kind"
                  :method="option.raw"
                  size="md"
                  hide-installments
                />
              </template>
              <template #option="{ option }">
                <PaymentMethodBadge
                  :kind="option.raw.kind"
                  :method="option.raw"
                  size="md"
                  hide-installments
                />
                <span v-if="option.hint" class="pem-v2__pm-provider-hint">
                  <i class="i-lucide-building-2 w-3 h-3" />
                  {{ option.hint }}
                </span>
              </template>
            </FormSelect>
          </section>

          <!-- Conta + data + ajustes -->
          <section class="pem-v2__section">
            <div class="pem-v2__grid">
              <!-- Conta de origem — info-card quando forma tem default,
                   FormSelect quando sem default OU operador clica "Alterar". -->
              <div class="pem-v2__field">
                <span class="pem-v2__field-label">Conta de origem *</span>
                <div
                  v-if="showBankAccountInfo && selectedBankAccount"
                  class="pem-v2__bank-info"
                >
                  <i class="i-lucide-landmark w-3.5 h-3.5" />
                  <span class="pem-v2__bank-info-name">{{ selectedBankAccount.name }}</span>
                  <span class="pem-v2__bank-info-tag">da forma</span>
                  <button
                    type="button"
                    class="pem-v2__bank-info-edit"
                    @click="overrideBankAccount = true"
                  >
                    <i class="i-lucide-pencil w-3 h-3" />
                    Alterar
                  </button>
                </div>
                <FormSelect
                  v-else
                  v-model="bankAccountId"
                  :options="bankAccountOptions"
                  placeholder="Selecione a conta"
                  searchable
                  auto-searchable
                />
              </div>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">Data do pagamento *</span>
                <DatePickerBR v-model="paidAt" />
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">
                  Juros (opcional)
                  <span class="pem-v2__mode-toggle">
                    <button type="button" class="pem-v2__mode-btn" :class="{ 'pem-v2__mode-btn--active': interestMode === MODE_BRL }" @click="setInterestMode(MODE_BRL)">R$</button>
                    <button type="button" class="pem-v2__mode-btn" :class="{ 'pem-v2__mode-btn--active': interestMode === MODE_PCT }" @click="setInterestMode(MODE_PCT)">%</button>
                  </span>
                </span>
                <div class="pem-v2__currency-wrap">
                  <span class="pem-v2__currency-prefix">{{ interestMode === MODE_PCT ? '%' : 'R$' }}</span>
                  <input
                    :value="interestStr"
                    type="text"
                    inputmode="decimal"
                    placeholder="0,00"
                    class="finv2-input pem-v2__currency-input"
                    @input="onInterestInput"
                  />
                </div>
                <span v-if="interestMode === MODE_PCT && interestCents > 0" class="pem-v2__mode-hint">
                  = {{ centsToBRL(interestCents) }}
                </span>
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">
                  Multa (opcional)
                  <span class="pem-v2__mode-toggle">
                    <button type="button" class="pem-v2__mode-btn" :class="{ 'pem-v2__mode-btn--active': fineMode === MODE_BRL }" @click="setFineMode(MODE_BRL)">R$</button>
                    <button type="button" class="pem-v2__mode-btn" :class="{ 'pem-v2__mode-btn--active': fineMode === MODE_PCT }" @click="setFineMode(MODE_PCT)">%</button>
                  </span>
                </span>
                <div class="pem-v2__currency-wrap">
                  <span class="pem-v2__currency-prefix">{{ fineMode === MODE_PCT ? '%' : 'R$' }}</span>
                  <input
                    :value="fineStr"
                    type="text"
                    inputmode="decimal"
                    placeholder="0,00"
                    class="finv2-input pem-v2__currency-input"
                    @input="onFineInput"
                  />
                </div>
                <span v-if="fineMode === MODE_PCT && fineCents > 0" class="pem-v2__mode-hint">
                  = {{ centsToBRL(fineCents) }}
                </span>
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">
                  Desconto (opcional)
                  <span class="pem-v2__mode-toggle">
                    <button type="button" class="pem-v2__mode-btn" :class="{ 'pem-v2__mode-btn--active': discountMode === MODE_BRL }" @click="setDiscountMode(MODE_BRL)">R$</button>
                    <button type="button" class="pem-v2__mode-btn" :class="{ 'pem-v2__mode-btn--active': discountMode === MODE_PCT }" @click="setDiscountMode(MODE_PCT)">%</button>
                  </span>
                </span>
                <div class="pem-v2__currency-wrap">
                  <span class="pem-v2__currency-prefix">{{ discountMode === MODE_PCT ? '%' : 'R$' }}</span>
                  <input
                    :value="discountStr"
                    type="text"
                    inputmode="decimal"
                    placeholder="0,00"
                    class="finv2-input pem-v2__currency-input"
                    @input="onDiscountInput"
                  />
                </div>
                <span v-if="discountMode === MODE_PCT && discountCents > 0" class="pem-v2__mode-hint">
                  = {{ centsToBRL(discountCents) }}
                </span>
              </label>

              <label class="pem-v2__field pem-v2__field--full">
                <span class="pem-v2__field-label">Observações</span>
                <textarea
                  v-model="notes"
                  rows="2"
                  class="finv2-input pem-v2__textarea"
                  placeholder="Notas internas (opcional)"
                />
              </label>
            </div>
          </section>

          <!-- Resumo -->
          <section class="pem-v2__summary">
            <div class="pem-v2__summary-row">
              <span>Valor da despesa</span>
              <strong>{{ centsToBRL(baseCents) }}</strong>
            </div>
            <div v-if="interestCents > 0" class="pem-v2__summary-row">
              <span>+ Juros</span>
              <strong>{{ centsToBRL(interestCents) }}</strong>
            </div>
            <div v-if="fineCents > 0" class="pem-v2__summary-row">
              <span>+ Multa</span>
              <strong>{{ centsToBRL(fineCents) }}</strong>
            </div>
            <div v-if="discountCents > 0" class="pem-v2__summary-row pem-v2__summary-row--negative">
              <span>− Desconto</span>
              <strong>{{ centsToBRL(discountCents) }}</strong>
            </div>
            <div class="pem-v2__summary-row pem-v2__summary-row--total">
              <span>Total a debitar</span>
              <strong>{{ centsToBRL(totalCents) }}</strong>
            </div>
          </section>
        </div>

        <footer class="pem-v2__footer">
          <BeclinicButton
            variant="ghost"
            color="slate"
            label="Cancelar"
            :disabled="submitting"
            @click="close"
          />
          <BeclinicButton
            variant="solid"
            color="ruby"
            icon="i-lucide-check"
            label="Confirmar pagamento"
            :is-loading="submitting"
            :disabled="!validForSubmit"
            @click="submit"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
/* Backdrop + modal — mesma régua dos outros modais v2. */
.pem-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999; padding: 0;
}
@media (min-width: 640px) {
  .pem-v2__backdrop { align-items: center; padding: 16px; }
}

.pem-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  border: 0; border-radius: 0;
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .pem-v2__modal {
    width: min(720px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.pem-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.pem-v2__title {
  margin: 0; font-size: 17px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.pem-v2__title-icon { width: 18px; height: 18px; color: #b91c1c; }
:root.dark .pem-v2__title-icon { color: #fca5a5; }
.pem-v2__expense-line {
  margin: 4px 0 0; font-size: 13px; color: rgb(var(--slate-9));
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}
.pem-v2__expense-meta { color: rgb(var(--slate-9)); }

.pem-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 18px;
}
.pem-v2__section { display: flex; flex-direction: column; gap: 10px; }
.pem-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: inline-flex; align-items: center; gap: 6px;
  line-height: 16px;
}

/* Refactor 2026-05-24: chips hardcoded substituídos pelo FormSelect com
 * slot custom + PaymentMethodBadge (single source of truth no beclinic_core).
 * 100+ linhas de CSS de paleta de tons removidas. */
.pem-v2__pm-loading {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 12px; color: rgb(var(--slate-9));
  padding: 8px 0;
}
.pem-v2__pm-provider-hint {
  margin-left: auto;
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11px; color: rgb(var(--slate-9));
  font-weight: 500; white-space: nowrap;
  i { opacity: 0.7; }
}
.pem-v2__hint {
  display: inline-flex; align-items: center; gap: 6px;
  font-size: 12px; margin: 0;
  padding: 8px 12px; border-radius: 8px;
  &--warn { background: rgba(245, 158, 11, 0.10); color: #b45309; border-left: 3px solid #f59e0b; }
}
:root.dark .pem-v2__hint--warn { color: #fcd34d; background: rgba(245, 158, 11, 0.18); }

/* Info-card da conta de origem (quando forma tem default_bank_account_id) */
.pem-v2__bank-info {
  display: flex; align-items: center; gap: 8px;
  padding: 0 12px;
  min-height: 38px;
  box-sizing: border-box;
  background: rgb(var(--blue-2));
  border: 1px solid rgb(var(--blue-5));
  border-radius: 8px;
  font-size: 13px; color: rgb(var(--slate-12));
  width: 100%; min-width: 0;
  i { color: rgb(var(--blue-10)); flex-shrink: 0; }
}
.pem-v2__bank-info-name {
  font-weight: 500;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  min-width: 0;
}
.pem-v2__bank-info-tag {
  font-size: 10.5px; font-weight: 500;
  padding: 1px 6px; border-radius: 999px;
  background: rgb(var(--blue-4)); color: rgb(var(--blue-11));
  text-transform: lowercase; letter-spacing: 0.01em;
  white-space: nowrap;
}
.pem-v2__bank-info-edit {
  margin-left: auto;
  display: inline-flex; align-items: center; gap: 4px;
  padding: 3px 8px;
  background: transparent;
  border: 1px solid transparent; border-radius: 6px;
  color: rgb(var(--blue-11));
  font-size: 11.5px; font-weight: 500;
  cursor: pointer; white-space: nowrap;
  transition: background 0.12s, border-color 0.12s;
  &:hover { background: rgb(var(--blue-3)); border-color: rgb(var(--blue-7)); }
}

/* Toggle R$/% inline no label (Juros, Multa, Desconto) */
.pem-v2__mode-toggle {
  margin-left: auto;
  display: inline-flex; align-items: center;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 999px;
  padding: 1px;
  overflow: hidden;
}
.pem-v2__mode-btn {
  display: inline-flex; align-items: center; justify-content: center;
  min-width: 24px; height: 16px;
  padding: 0 6px;
  background: transparent;
  border: 0; border-radius: 999px;
  font-size: 10px; font-weight: 600;
  color: rgb(var(--slate-10));
  cursor: pointer;
  line-height: 1;
  transition: background 0.12s, color 0.12s;
  &:hover:not(.pem-v2__mode-btn--active) { color: rgb(var(--slate-12)); }
  &--active { background: rgb(var(--blue-9)); color: #ffffff; }
}
.pem-v2__mode-hint {
  margin-top: 4px;
  font-size: 11px; color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
  font-style: italic;
}

/* Grid */
.pem-v2__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 640px) { .pem-v2__grid { grid-template-columns: 1fr; } }
.pem-v2__field { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.pem-v2__field--full { grid-column: 1 / -1; }
.pem-v2__textarea { resize: vertical; min-height: 60px; }

/* Currency input */
.pem-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.pem-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.pem-v2__currency-input {
  padding-left: 32px; text-align: right;
  font-variant-numeric: tabular-nums;
}

/* Summary */
.pem-v2__summary {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 12px 14px;
  display: flex; flex-direction: column; gap: 6px;
}
.pem-v2__summary-row {
  display: flex; justify-content: space-between; align-items: center;
  font-size: 13px; color: rgb(var(--slate-11));
  strong {
    color: rgb(var(--slate-12)); font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
}
.pem-v2__summary-row--negative strong { color: #047857; }
:root.dark .pem-v2__summary-row--negative strong { color: #6ee7b7; }
.pem-v2__summary-row--total {
  font-size: 14px; font-weight: 600;
  padding-top: 8px; margin-top: 4px;
  border-top: 1px dashed rgb(var(--slate-5));
  span { color: rgb(var(--slate-12)); }
  strong { font-size: 16px; color: #b91c1c; }
}
:root.dark .pem-v2__summary-row--total strong { color: #fca5a5; }

/* Footer */
.pem-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
@media (max-width: 640px) {
  .pem-v2__footer { flex-direction: column-reverse; }
  .pem-v2__footer > * { width: 100%; }
}
</style>
