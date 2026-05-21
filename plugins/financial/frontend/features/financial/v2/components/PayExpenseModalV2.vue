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
import FinancialV2 from '../api/financialV2';
import { brlInputToCents, formatCurrencyInput, centsToBRL, bankKindLabel } from '../composables/useMoney';

const props = defineProps({
  show: { type: Boolean, default: false },
  expense: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Métodos com tom de cor pra chips coloridos.
// Valores alinhados ao enum v2 `Installment::PAYMENT_METHODS` (compartilhado
// por Expense/PaymentReceipt). Antes usava `cartao_credito`/`cartao_debito`
// (legacy v1) — rejeitado pelo backend com "Payment method não está incluso
// na lista". Enum v2 usa `credito`/`debito` (sem prefixo "cartao_").
const PAYMENT_METHODS = [
  { key: 'pix',           label: 'PIX',       icon: 'i-lucide-qr-code',          tone: 'pix' },
  { key: 'dinheiro',      label: 'Dinheiro',  icon: 'i-lucide-banknote',         tone: 'emerald' },
  { key: 'credito',       label: 'Crédito',   icon: 'i-lucide-credit-card',      tone: 'violet' },
  { key: 'debito',        label: 'Débito',    icon: 'i-lucide-credit-card',      tone: 'blue' },
  { key: 'boleto',        label: 'Boleto',    icon: 'i-lucide-file-text',        tone: 'amber' },
  { key: 'transferencia', label: 'Transf.',   icon: 'i-lucide-arrow-right-left', tone: 'blue' },
];

const paymentMethod = ref('pix');
const paidAt = ref(new Date().toISOString().slice(0, 10));
const bankAccountId = ref(null);
const interestStr = ref('');
const fineStr = ref('');
const discountStr = ref('');
const notes = ref('');
const submitting = ref(false);
const bankAccounts = ref([]);

const bankAccountOptions = computed(() =>
  bankAccounts.value.map(b => ({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` })),
);

const baseCents = computed(() => Number(props.expense?.amount_cents) || 0);
const interestCents = computed(() => brlInputToCents(interestStr.value));
const fineCents = computed(() => brlInputToCents(fineStr.value));
const discountCents = computed(() => brlInputToCents(discountStr.value));
const totalCents = computed(
  () => baseCents.value + interestCents.value + fineCents.value - discountCents.value,
);

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!props.expense?.id) return false;
  if (!bankAccountId.value) return false;
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

function reset() {
  paymentMethod.value = props.expense?.payment_method || 'pix';
  paidAt.value = new Date().toISOString().slice(0, 10);
  interestStr.value = '';
  fineStr.value = '';
  discountStr.value = '';
  notes.value = '';
  submitting.value = false;
  if (bankAccounts.value.length === 1) bankAccountId.value = bankAccounts.value[0].id;
}

watch(
  () => props.show,
  (val) => {
    if (val) {
      reset();
      loadBankAccounts();
    }
  },
);

onMounted(() => {
  if (props.show) {
    reset();
    loadBankAccounts();
  }
});

const onInterestInput = (e) => applyMask(e, interestStr);
const onFineInput     = (e) => applyMask(e, fineStr);
const onDiscountInput = (e) => applyMask(e, discountStr);
function applyMask(event, refToUpdate) {
  const formatted = formatCurrencyInput(event.target.value);
  refToUpdate.value = formatted;
  event.target.value = formatted;
}

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      bank_account_id: bankAccountId.value,
      paid_at: paidAt.value,
      payment_method: paymentMethod.value,
      interest_cents: interestCents.value,
      fine_cents: fineCents.value,
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
    <div v-if="show" class="pem-v2__backdrop" @click.self="close">
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
          <!-- Forma de pagamento -->
          <section class="pem-v2__section">
            <label class="pem-v2__field-label">Forma de pagamento</label>
            <div class="pem-v2__chips">
              <button
                v-for="m in PAYMENT_METHODS"
                :key="m.key"
                type="button"
                class="pem-v2__chip"
                :class="[
                  `pem-v2__chip--tone-${m.tone}`,
                  { 'pem-v2__chip--active': paymentMethod === m.key },
                ]"
                @click="paymentMethod = m.key"
              >
                <!-- PIX = SVG oficial do BC; demais = lucide. -->
                <svg
                  v-if="m.key === 'pix'"
                  class="pem-v2__chip-icon"
                  viewBox="0 0 297 297"
                  fill="currentColor"
                  aria-hidden="true"
                >
                  <path d="M231.433 227.02C219.791 227.02 208.84 222.487 200.607 214.257L156.096 169.745C152.971 166.612 147.524 166.621 144.4 169.745L99.7266 214.42C91.4932 222.649 80.5425 227.183 68.8998 227.183H60.1281L116.503 283.556C134.108 301.161 162.653 301.161 180.26 283.556L236.795 227.02H231.433Z" />
                  <path d="M68.8992 69.5768C80.5419 69.5768 91.4927 74.1101 99.726 82.3395L144.399 127.021C147.617 130.239 152.87 130.251 156.095 127.017L200.606 82.5023C208.839 74.273 219.79 69.7397 231.433 69.7397H236.794L180.261 13.205C162.653 -4.40167 134.107 -4.40167 116.502 13.205L60.13 69.577L68.8992 69.5768Z" />
                  <path d="M283.557 116.501L249.393 82.3373C248.641 82.6386 247.826 82.8266 246.966 82.8266H231.433C223.402 82.8266 215.541 86.084 209.866 91.7626L165.357 136.273C161.192 140.439 155.718 142.523 150.25 142.523C144.777 142.523 139.308 140.439 135.144 136.277L90.4662 91.6C84.7915 85.92 76.9302 82.664 68.8995 82.664H49.7996C48.9849 82.664 48.2236 82.472 47.5049 82.2013L13.205 116.501C-4.40167 134.108 -4.40167 162.652 13.205 180.259L47.5036 214.557C48.2236 214.287 48.9849 214.095 49.7996 214.095H68.8995C76.9302 214.095 84.7915 210.839 90.4662 205.16L135.14 160.487C143.214 152.419 157.29 152.416 165.357 160.49L209.866 204.997C215.541 210.676 223.402 213.933 231.433 213.933H246.966C247.826 213.933 248.641 214.121 249.393 214.422L283.557 180.258C301.162 162.652 301.162 134.108 283.557 116.501Z" />
                </svg>
                <i v-else :class="m.icon" class="w-3.5 h-3.5" />
                <span>{{ m.label }}</span>
              </button>
            </div>
          </section>

          <!-- Conta + data + ajustes -->
          <section class="pem-v2__section">
            <div class="pem-v2__grid">
              <label class="pem-v2__field">
                <span class="pem-v2__field-label">Conta de origem *</span>
                <FormSelect
                  v-model="bankAccountId"
                  :options="bankAccountOptions"
                  placeholder="Selecione a conta"
                  searchable
                  auto-searchable
                />
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">Data do pagamento *</span>
                <DatePickerBR v-model="paidAt" />
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">Juros (opcional)</span>
                <div class="pem-v2__currency-wrap">
                  <span class="pem-v2__currency-prefix">R$</span>
                  <input
                    :value="interestStr"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="finv2-input pem-v2__currency-input"
                    @input="onInterestInput"
                  />
                </div>
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">Multa (opcional)</span>
                <div class="pem-v2__currency-wrap">
                  <span class="pem-v2__currency-prefix">R$</span>
                  <input
                    :value="fineStr"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="finv2-input pem-v2__currency-input"
                    @input="onFineInput"
                  />
                </div>
              </label>

              <label class="pem-v2__field">
                <span class="pem-v2__field-label">Desconto (opcional)</span>
                <div class="pem-v2__currency-wrap">
                  <span class="pem-v2__currency-prefix">R$</span>
                  <input
                    :value="discountStr"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="finv2-input pem-v2__currency-input"
                    @input="onDiscountInput"
                  />
                </div>
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
}

/* Chips de método */
.pem-v2__chips { display: flex; flex-wrap: wrap; gap: 6px; }
.pem-v2__chip {
  display: inline-flex; align-items: center; gap: 5px;
  padding: 8px 14px;
  border-radius: 999px;
  font-size: 12.5px; font-weight: 500;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background 0.12s ease, color 0.12s ease, border-color 0.12s ease;
}
.pem-v2__chip--tone-emerald { background: rgba(16, 185, 129, 0.10); color: #047857; border-color: rgba(16, 185, 129, 0.28); &:hover { background: rgba(16, 185, 129, 0.18); } }
.pem-v2__chip--tone-pix     { background: rgba(46, 189, 175, 0.12); color: #1f8a7e; border-color: rgba(46, 189, 175, 0.32); &:hover { background: rgba(46, 189, 175, 0.20); } }
.pem-v2__chip--tone-violet  { background: rgba(124, 58, 237, 0.10); color: #6d28d9; border-color: rgba(124, 58, 237, 0.28); &:hover { background: rgba(124, 58, 237, 0.18); } }
.pem-v2__chip--tone-blue    { background: rgba(37, 99, 235, 0.10);  color: #1d4ed8; border-color: rgba(37, 99, 235, 0.28);  &:hover { background: rgba(37, 99, 235, 0.18); } }
.pem-v2__chip--tone-amber   { background: rgba(245, 158, 11, 0.12); color: #b45309; border-color: rgba(245, 158, 11, 0.32); &:hover { background: rgba(245, 158, 11, 0.20); } }
:root.dark .pem-v2__chip--tone-emerald { background: rgba(16, 185, 129, 0.18); color: #6ee7b7; border-color: rgba(16, 185, 129, 0.4); &:hover { background: rgba(16, 185, 129, 0.28); } }
:root.dark .pem-v2__chip--tone-pix     { background: rgba(46, 189, 175, 0.20); color: #5dd9c8; border-color: rgba(46, 189, 175, 0.45); &:hover { background: rgba(46, 189, 175, 0.30); } }
:root.dark .pem-v2__chip--tone-violet  { background: rgba(124, 58, 237, 0.20); color: #c4b5fd; border-color: rgba(124, 58, 237, 0.4); &:hover { background: rgba(124, 58, 237, 0.30); } }
:root.dark .pem-v2__chip--tone-blue    { background: rgba(59, 130, 246, 0.18); color: #93c5fd; border-color: rgba(59, 130, 246, 0.4); &:hover { background: rgba(59, 130, 246, 0.28); } }
:root.dark .pem-v2__chip--tone-amber   { background: rgba(245, 158, 11, 0.18); color: #fcd34d; border-color: rgba(245, 158, 11, 0.4); &:hover { background: rgba(245, 158, 11, 0.28); } }
/* Tamanho do SVG inline (PIX) — bate com w-3.5 h-3.5 do lucide. */
.pem-v2__chip-icon { width: 14px; height: 14px; flex-shrink: 0; }

/* Active = solid + sombra de anel pra reforçar seleção (PIX especialmente). */
.pem-v2__chip--active {
  color: #ffffff;
  border-color: transparent;
  font-weight: 600;
  box-shadow: 0 0 0 2px rgba(0, 0, 0, 0.04), 0 1px 3px rgba(0, 0, 0, 0.08);
}
.pem-v2__chip--tone-emerald.pem-v2__chip--active { background: #059669; &:hover { background: #047857; } }
.pem-v2__chip--tone-pix.pem-v2__chip--active     { background: rgb(46, 189, 175); &:hover { background: #1f8a7e; } }
.pem-v2__chip--tone-violet.pem-v2__chip--active  { background: #7c3aed; &:hover { background: #6d28d9; } }
.pem-v2__chip--tone-blue.pem-v2__chip--active    { background: #2563eb; &:hover { background: #1d4ed8; } }
.pem-v2__chip--tone-amber.pem-v2__chip--active   { background: #d97706; &:hover { background: #b45309; } }
:root.dark .pem-v2__chip--active { color: #ffffff; }

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
