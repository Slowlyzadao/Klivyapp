<script setup>
/**
 * Modal de baixa de pagamento — v2 (canon Financial::*).
 *
 * Implementa BUG-01 fix: aceita "Valor recebido" editável diferente do total
 * da parcela. Se < total, gera saldo restante em nova parcela; se > total e
 * houver apenas uma parcela, o excedente vira Crédito do paciente.
 *
 * Suporte multi-parcela: pode quitar várias parcelas em um único PIX/dinheiro
 * (canon — PaymentReceipt agrupa N parcelas).
 *
 * UI:
 *   - Componentes globais: BeclinicButton, FormSelect, Checkbox, DatePickerBR, Badge.
 *   - Forma de pagamento como chips com paleta de cores (faded resting + solid active),
 *     mesma estética dos chips da página A Receber.
 *   - Mobile: 100% width/height (padrão Klivy).
 *
 * Props:
 *   - show: boolean
 *   - installments: array — parcelas a quitar (pré-selecionadas pelo caller)
 *   - patient: { id, name }
 *
 * Eventos:
 *   - close
 *   - confirm: { receipt, new_installments }
 */

import { ref, computed, watch, onMounted } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../api/financialV2';
import {
  centsToBRL,
  brlInputToCents,
  centsToInputString,
  formatCurrencyInput,
  bankKindLabel,
} from '../composables/useMoney';

const props = defineProps({
  show: { type: Boolean, default: false },
  installments: { type: Array, default: () => [] },
  patient: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

// Cada método tem `tone` = cor da paleta Badge global (mesmo padrão do
// chip de status na página A Receber). Backend continua recebendo os
// keys curtos (pix/dinheiro/credito/debito/boleto/transferencia).
const PAYMENT_METHODS = [
  { key: 'pix',           label: 'PIX',       icon: 'i-lucide-qr-code',           tone: 'pix' },
  { key: 'dinheiro',      label: 'Dinheiro',  icon: 'i-lucide-banknote',          tone: 'emerald' },
  { key: 'credito',       label: 'Crédito',   icon: 'i-lucide-credit-card',       tone: 'violet' },
  { key: 'debito',        label: 'Débito',    icon: 'i-lucide-credit-card',       tone: 'blue' },
  { key: 'boleto',        label: 'Boleto',    icon: 'i-lucide-file-text',         tone: 'amber' },
  { key: 'transferencia', label: 'Transf.',   icon: 'i-lucide-arrow-right-left',  tone: 'blue' },
];

const PARTIAL_OK_METHODS = new Set(['dinheiro', 'pix', 'boleto']);

const paymentMethod = ref('pix');
const receivedAt = ref(new Date().toISOString().slice(0, 10));
const bankAccountId = ref(null);
const bankAccounts = ref([]);
const interestStr = ref('');
const fineStr = ref('');
const discountStr = ref('');
// Abater crédito: UX clique-pra-aplicar (não input livre). Aplica TODO o
// crédito disponível, limitado pelo total a receber (evita virar saldo a
// favor de novo). Decisão 2026-05-12 — mais intuitivo que digitar valor.
const applyCreditEnabled = ref(false);
const patientCreditBalance = ref(0);
const keepInstallmentOpen = ref(true);
const notes = ref('');
const submitting = ref(false);
const errorMessage = ref('');
const installmentInputs = ref({});

const totalInstallmentsRemaining = computed(() =>
  props.installments.reduce(
    (sum, i) => sum + (i.remaining_cents ?? i.amount_cents - (i.received_amount_cents || 0)),
    0
  ),
);

const grossCents = computed(() =>
  Object.values(installmentInputs.value).reduce((acc, str) => acc + brlInputToCents(str), 0),
);

const interestCents = computed(() => brlInputToCents(interestStr.value));
const fineCents = computed(() => brlInputToCents(fineStr.value));
const discountCents = computed(() => brlInputToCents(discountStr.value));

// Crédito a abater quando o toggle ON: aplica todo o saldo, limitado ao
// bruto + acréscimos − desconto (evita virar saldo a favor novamente).
const maxCreditApplicable = computed(() => {
  const cap = grossCents.value + interestCents.value + fineCents.value - discountCents.value;
  return Math.max(0, Math.min(patientCreditBalance.value, cap));
});
const applyCreditCents = computed(() => applyCreditEnabled.value ? maxCreditApplicable.value : 0);

const netCents = computed(
  () =>
    grossCents.value +
    interestCents.value +
    fineCents.value -
    discountCents.value -
    applyCreditCents.value,
);

const partialAllowed = computed(() => PARTIAL_OK_METHODS.has(paymentMethod.value));

// Baixa parcial = pelo menos uma parcela tem valor digitado MENOR que o saldo
// dela. Quando todas estão com valor cheio (ou zero), não há saldo restante
// pra "gerar nova parcela" — checkbox `keepInstallmentOpen` fica oculto.
const isPartialPayment = computed(() => {
  return props.installments.some((inst) => {
    const remaining = inst.remaining_cents ?? inst.amount_cents - (inst.received_amount_cents || 0);
    const applied = brlInputToCents(installmentInputs.value[inst.id] || '0');
    return applied > 0 && applied < remaining;
  });
});

const willCreateRemainder = computed(() => {
  if (!partialAllowed.value || !keepInstallmentOpen.value) return false;
  return props.installments.some((inst) => {
    const remaining = inst.remaining_cents ?? inst.amount_cents - (inst.received_amount_cents || 0);
    const applied = brlInputToCents(installmentInputs.value[inst.id] || '0');
    return applied > 0 && applied < remaining;
  });
});

const willCreateExcessCredit = computed(() => {
  if (props.installments.length !== 1) return false;
  return grossCents.value > totalInstallmentsRemaining.value;
});

// Crédito cobre 100% do total devido — desabilitar seletor de método
// (forma de pagamento real será `credito_paciente`, gravada pelo backend).
const creditCoversAll = computed(() => {
  if (!applyCreditEnabled.value) return false;
  if (applyCreditCents.value <= 0) return false;
  const totalDue = grossCents.value + interestCents.value + fineCents.value - discountCents.value;
  return applyCreditCents.value >= totalDue;
});

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!bankAccountId.value) return false;
  if (props.installments.length === 0) return false;
  if (grossCents.value <= 0) return false;
  if (!partialAllowed.value) {
    return props.installments.every((inst) => {
      const remaining = inst.remaining_cents ?? inst.amount_cents - (inst.received_amount_cents || 0);
      const applied = brlInputToCents(installmentInputs.value[inst.id] || '0');
      return applied === remaining || applied === 0;
    });
  }
  return true;
});

const bankAccountOptions = computed(() =>
  bankAccounts.value.map((b) => ({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` })),
);

const currentMethodLabel = computed(() => {
  const m = PAYMENT_METHODS.find((x) => x.key === paymentMethod.value);
  return m?.label || paymentMethod.value;
});

async function loadBankAccounts() {
  try {
    const { data } = await FinancialV2.bankAccounts.index({ active: 'true' });
    bankAccounts.value = data?.data || [];
    if (bankAccounts.value.length === 1) {
      bankAccountId.value = bankAccounts.value[0].id;
    }
  } catch (e) {
    bankAccounts.value = [];
  }
}

async function loadPatientCredit() {
  if (!props.patient?.id) {
    patientCreditBalance.value = 0;
    return;
  }
  try {
    const { data } = await FinancialV2.patientCredits.index({ patient_id: props.patient.id });
    patientCreditBalance.value = data?.balance_cents || 0;
  } catch {
    patientCreditBalance.value = 0;
  }
}

function resetInputs() {
  paymentMethod.value = 'pix';
  receivedAt.value = new Date().toISOString().slice(0, 10);
  interestStr.value = '';
  fineStr.value = '';
  discountStr.value = '';
  applyCreditEnabled.value = false;
  keepInstallmentOpen.value = true;
  notes.value = '';
  errorMessage.value = '';
  submitting.value = false;
  installmentInputs.value = {};
  for (const inst of props.installments) {
    const remaining = inst.remaining_cents ?? inst.amount_cents - (inst.received_amount_cents || 0);
    installmentInputs.value[inst.id] = centsToInputString(remaining);
  }
}

watch(
  () => props.show,
  (val) => {
    if (val) {
      resetInputs();
      loadBankAccounts();
      loadPatientCredit();
    }
  },
);

watch(
  () => props.installments.map((i) => i.id).join(','),
  () => resetInputs(),
);

onMounted(() => {
  if (props.show) {
    resetInputs();
    loadBankAccounts();
    loadPatientCredit();
  }
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  errorMessage.value = '';

  const payload = {
    bank_account_id: bankAccountId.value,
    payment_method: paymentMethod.value,
    received_at: receivedAt.value,
    interest_cents: interestCents.value,
    fine_cents: fineCents.value,
    discount_cents: discountCents.value,
    apply_patient_credit_cents: applyCreditCents.value,
    keep_installment_open: keepInstallmentOpen.value,
    notes: notes.value,
    installment_amounts: props.installments
      .filter((inst) => brlInputToCents(installmentInputs.value[inst.id] || '0') > 0)
      .map((inst) => ({
        installment_id: inst.id,
        amount_cents: brlInputToCents(installmentInputs.value[inst.id]),
      })),
  };

  try {
    const { data } = await FinancialV2.paymentReceipts.create(payload);
    emit('confirm', data);
    emit('close');
  } catch (err) {
    const errors = err?.response?.data?.errors;
    errorMessage.value = Array.isArray(errors)
      ? errors.join('; ')
      : err?.message || 'Erro ao registrar pagamento';
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

function fmt(cents) {
  return centsToBRL(cents);
}

/**
 * Live-format dos inputs de dinheiro: cada tecla reformata o valor + atualiza
 * o ref reativo. Importante: NÃO podemos passar o `ref` como argumento numa
 * expressão de template (Vue auto-unwrap pra string e perdemos a reatividade).
 * Por isso cada input tem seu próprio handler — todos passam pelo helper
 * `applyMoneyMask` que faz o formatting e atualização atomicamente.
 */
function applyMoneyMask(event, refToUpdate) {
  const formatted = formatCurrencyInput(event.target.value);
  refToUpdate.value = formatted;
  event.target.value = formatted;
}

const onInterestInput     = (e) => applyMoneyMask(e, interestStr);
const onFineInput         = (e) => applyMoneyMask(e, fineStr);
const onDiscountInput     = (e) => applyMoneyMask(e, discountStr);

function onInstallmentMoneyInput(event, instId) {
  const formatted = formatCurrencyInput(event.target.value);
  installmentInputs.value[instId] = formatted;
  event.target.value = formatted;
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="rpm-v2__backdrop"
      @click.self="close"
    >
      <div
        class="rpm-v2__modal"
        role="dialog"
        aria-modal="true"
      >
        <!-- Header sticky -->
        <header class="rpm-v2__header">
          <div class="rpm-v2__header-text">
            <h2 class="rpm-v2__title">
              <i class="i-lucide-circle-dollar-sign rpm-v2__title-icon" />
              Receber pagamento
            </h2>
            <p v-if="patient?.name" class="rpm-v2__patient">
              {{ patient.name }}
            </p>
          </div>
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-x"
            :disabled="submitting"
            aria-label="Fechar"
            @click="close"
          />
        </header>

        <!-- Body com scroll interno -->
        <div class="rpm-v2__body">
          <!-- Parcelas selecionadas -->
          <section class="rpm-v2__section">
            <h3 class="rpm-v2__section-title">
              Parcelas selecionadas
              <span class="rpm-v2__pill">{{ installments.length }}</span>
            </h3>

            <div
              v-for="inst in installments"
              :key="inst.id"
              class="rpm-v2__installment"
            >
              <div class="rpm-v2__installment-info">
                <span class="rpm-v2__installment-number">
                  Parcela {{ inst.number }}/{{ inst.total_in_series }}
                </span>
                <span class="rpm-v2__installment-meta">
                  Venc. {{ inst.due_date }}
                </span>
                <span class="rpm-v2__installment-saldo">
                  Saldo
                  <strong>
                    {{ fmt(inst.remaining_cents ?? inst.amount_cents - (inst.received_amount_cents || 0)) }}
                  </strong>
                </span>
              </div>
              <label class="rpm-v2__amount-input">
                <span class="rpm-v2__amount-label">Valor recebido</span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">R$</span>
                  <input
                    :value="installmentInputs[inst.id]"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    @input="(e) => onInstallmentMoneyInput(e, inst.id)"
                  />
                </div>
              </label>
            </div>
            <p v-if="!partialAllowed" class="rpm-v2__hint rpm-v2__hint--warn">
              <i class="i-lucide-info w-3.5 h-3.5" />
              "{{ currentMethodLabel }}" não aceita baixa parcial. O valor de cada
              parcela deve ser igual ao saldo restante.
            </p>
          </section>

          <!-- Forma de pagamento (chips coloridos).
               Quando crédito cobre 100% do valor, o método real será
               `credito_paciente` (gravado pelo backend), independente do
               que está selecionado aqui — desabilitamos visualmente. -->
          <section class="rpm-v2__section">
            <label class="rpm-v2__field-label">Forma de pagamento</label>
            <div v-if="creditCoversAll" class="rpm-v2__credit-only">
              <i class="i-lucide-wallet w-3.5 h-3.5" />
              <span>Pagamento integral via <strong>crédito do paciente</strong> — método selecionado será ignorado.</span>
            </div>
            <div
              class="rpm-v2__chips"
              :class="{ 'rpm-v2__chips--disabled': creditCoversAll }"
            >
              <button
                v-for="m in PAYMENT_METHODS"
                :key="m.key"
                type="button"
                class="rpm-v2__chip"
                :class="[
                  `rpm-v2__chip--tone-${m.tone}`,
                  { 'rpm-v2__chip--active': paymentMethod === m.key },
                ]"
                :disabled="creditCoversAll"
                @click="paymentMethod = m.key"
              >
                <!-- PIX = SVG oficial do BC; demais = lucide. -->
                <svg
                  v-if="m.key === 'pix'"
                  class="rpm-v2__chip-icon"
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

          <!-- Grid de campos -->
          <section class="rpm-v2__section">
            <div class="rpm-v2__grid">
              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">Conta destino</span>
                <FormSelect
                  v-model="bankAccountId"
                  :options="bankAccountOptions"
                  placeholder="Selecione a conta"
                  searchable
                  auto-searchable
                />
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">Data do recebimento</span>
                <DatePickerBR v-model="receivedAt" />
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">Juros</span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">R$</span>
                  <input
                    :value="interestStr"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    @input="onInterestInput"
                  />
                </div>
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">Multa</span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">R$</span>
                  <input
                    :value="fineStr"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    @input="onFineInput"
                  />
                </div>
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">Desconto</span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">R$</span>
                  <input
                    :value="discountStr"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    @input="onDiscountInput"
                  />
                </div>
              </label>

              <!-- Crédito do paciente — UX clique-pra-aplicar (botão único),
                   full-width pra evitar comprimir o botão "Usar crédito
                   disponível" quando o saldo tem muitos dígitos. -->
              <div v-if="patientCreditBalance > 0" class="rpm-v2__field rpm-v2__field--full">
                <span class="rpm-v2__field-label">Crédito do paciente</span>
                <button
                  v-if="!applyCreditEnabled"
                  type="button"
                  class="rpm-v2__credit-btn"
                  @click="applyCreditEnabled = true"
                >
                  <i class="i-lucide-wallet w-3.5 h-3.5" />
                  <span>Usar crédito disponível</span>
                  <strong>{{ fmt(patientCreditBalance) }}</strong>
                </button>
                <div v-else class="rpm-v2__credit-applied">
                  <div class="rpm-v2__credit-applied-info">
                    <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
                    <span>Crédito aplicado:</span>
                    <strong>{{ fmt(applyCreditCents) }}</strong>
                  </div>
                  <button
                    type="button"
                    class="rpm-v2__credit-remove"
                    @click="applyCreditEnabled = false"
                  >
                    Remover
                  </button>
                </div>
              </div>

              <label class="rpm-v2__field rpm-v2__field--full">
                <span class="rpm-v2__field-label">Observações</span>
                <textarea
                  v-model="notes"
                  rows="2"
                  class="rpm-v2__textarea"
                  placeholder="Notas internas (opcional)"
                />
              </label>

              <!-- Checkbox "gerar nova parcela" só aparece quando há baixa
                   parcial real (alguma parcela com valor digitado < saldo)
                   E o método aceita parcial. Pagando o total → oculto. -->
              <div v-if="partialAllowed && isPartialPayment" class="rpm-v2__field rpm-v2__field--full">
                <Checkbox
                  v-model="keepInstallmentOpen"
                  label="Em baixa parcial, gerar nova parcela com o saldo restante"
                />
              </div>
            </div>
          </section>

          <!-- Resumo -->
          <section class="rpm-v2__summary">
            <div class="rpm-v2__summary-row">
              <span>Valor bruto</span>
              <strong>{{ fmt(grossCents) }}</strong>
            </div>
            <div v-if="interestCents > 0" class="rpm-v2__summary-row">
              <span>+ Juros</span>
              <strong>{{ fmt(interestCents) }}</strong>
            </div>
            <div v-if="fineCents > 0" class="rpm-v2__summary-row">
              <span>+ Multa</span>
              <strong>{{ fmt(fineCents) }}</strong>
            </div>
            <div v-if="discountCents > 0" class="rpm-v2__summary-row rpm-v2__summary-row--negative">
              <span>− Desconto</span>
              <strong>{{ fmt(discountCents) }}</strong>
            </div>
            <div v-if="applyCreditCents > 0" class="rpm-v2__summary-row rpm-v2__summary-row--negative">
              <span>− Crédito aplicado</span>
              <strong>{{ fmt(applyCreditCents) }}</strong>
            </div>
            <div class="rpm-v2__summary-row rpm-v2__summary-row--total">
              <span>Total a creditar na conta</span>
              <strong>{{ fmt(netCents) }}</strong>
            </div>

            <p v-if="willCreateRemainder" class="rpm-v2__info">
              <i class="i-lucide-info w-3.5 h-3.5" />
              Baixa parcial: serão geradas novas parcelas com o saldo restante.
            </p>
            <p v-if="willCreateExcessCredit" class="rpm-v2__info">
              <i class="i-lucide-wallet w-3.5 h-3.5" />
              Excedente
              <strong>{{ fmt(grossCents - totalInstallmentsRemaining) }}</strong>
              será lançado como crédito do paciente.
            </p>
          </section>

          <p v-if="errorMessage" class="rpm-v2__error" role="alert">
            <i class="i-lucide-alert-triangle w-3.5 h-3.5" />
            {{ errorMessage }}
          </p>
        </div>

        <!-- Footer sticky -->
        <footer class="rpm-v2__footer">
          <BeclinicButton
            variant="ghost"
            color="slate"
            label="Cancelar"
            :disabled="submitting"
            @click="close"
          />
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-check"
            label="Confirmar recebimento"
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
/* ── Backdrop + modal shell ────────────────────────────────────── */
.rpm-v2__backdrop {
  position: fixed;
  inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex;
  align-items: stretch;
  justify-content: center;
  z-index: 9999;
  padding: 0;
}
@media (min-width: 640px) {
  .rpm-v2__backdrop {
    align-items: center;
    padding: 16px;
  }
}

/* Modal: full-screen no mobile, centralizado e limitado no desktop. */
.rpm-v2__modal {
  width: 100%;
  height: 100%;
  background: rgb(var(--slate-1));
  border: 0;
  border-radius: 0;
  display: flex;
  flex-direction: column;
  box-shadow: none;
  overflow: hidden;
}
@media (min-width: 640px) {
  .rpm-v2__modal {
    width: min(760px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

/* ── Header ───────────────────────────────────────────────────── */
.rpm-v2__header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-1));
}
.rpm-v2__title {
  margin: 0;
  font-size: 17px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex;
  align-items: center;
  gap: 8px;
}
.rpm-v2__title-icon {
  width: 18px;
  height: 18px;
  color: #059669; /* emerald */
}
.rpm-v2__patient {
  margin: 4px 0 0;
  font-size: 13px;
  color: rgb(var(--slate-9));
}

/* ── Body com scroll interno ──────────────────────────────────── */
.rpm-v2__body {
  flex: 1;
  overflow-y: auto;
  padding: 18px 20px;
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* ── Sections ─────────────────────────────────────────────────── */
.rpm-v2__section {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.rpm-v2__section-title {
  margin: 0;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
  font-weight: 600;
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.rpm-v2__pill {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 22px;
  height: 22px;
  padding: 0 6px;
  border-radius: 999px;
  background: rgba(37, 99, 235, 0.10);
  color: #1d4ed8;
  font-size: 11px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}
:root.dark .rpm-v2__pill { background: rgba(59, 130, 246, 0.18); color: #93c5fd; }

/* ── Installment row ──────────────────────────────────────────── */
.rpm-v2__installment {
  display: grid;
  grid-template-columns: 1fr 220px;
  gap: 12px;
  align-items: center;
  padding: 12px 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
}
@media (max-width: 640px) {
  .rpm-v2__installment { grid-template-columns: 1fr; }
}
.rpm-v2__installment-info {
  display: flex;
  flex-direction: column;
  gap: 3px;
}
.rpm-v2__installment-number {
  font-size: 13px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.rpm-v2__installment-meta {
  font-size: 12px;
  color: rgb(var(--slate-9));
}
.rpm-v2__installment-saldo {
  font-size: 12px;
  color: rgb(var(--slate-9));
  strong { color: rgb(var(--slate-12)); font-weight: 600; font-variant-numeric: tabular-nums; }
}
.rpm-v2__amount-input {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.rpm-v2__amount-label {
  font-size: 11px;
  color: rgb(var(--slate-9));
  text-transform: uppercase;
  letter-spacing: 0.04em;
  font-weight: 500;
}

/* ── Hint ─────────────────────────────────────────────────────── */
.rpm-v2__hint {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  margin: 0;
  padding: 8px 12px;
  border-radius: 8px;
}
.rpm-v2__hint--warn {
  background: rgba(245, 158, 11, 0.10);
  color: #b45309;
  border-left: 3px solid #f59e0b;
}
:root.dark .rpm-v2__hint--warn { color: #fcd34d; background: rgba(245, 158, 11, 0.18); }

/* ── Chips de forma de pagamento ──────────────────────────────── */
.rpm-v2__chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.rpm-v2__chip {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 8px 14px;
  border-radius: 999px;
  font-size: 12.5px;
  font-weight: 500;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background 0.12s ease, color 0.12s ease, border-color 0.12s ease;
}
.rpm-v2__chip--tone-emerald {
  background: rgba(16, 185, 129, 0.10);
  color: #047857;
  border-color: rgba(16, 185, 129, 0.28);
  &:hover { background: rgba(16, 185, 129, 0.18); }
}
/* PIX — cor brand oficial do Banco Central rgb(46, 189, 175). */
.rpm-v2__chip--tone-pix {
  background: rgba(46, 189, 175, 0.12);
  color: #1f8a7e;
  border-color: rgba(46, 189, 175, 0.32);
  &:hover { background: rgba(46, 189, 175, 0.20); }
}
.rpm-v2__chip--tone-violet {
  background: rgba(124, 58, 237, 0.10);
  color: #6d28d9;
  border-color: rgba(124, 58, 237, 0.28);
  &:hover { background: rgba(124, 58, 237, 0.18); }
}
.rpm-v2__chip--tone-blue {
  background: rgba(37, 99, 235, 0.10);
  color: #1d4ed8;
  border-color: rgba(37, 99, 235, 0.28);
  &:hover { background: rgba(37, 99, 235, 0.18); }
}
.rpm-v2__chip--tone-amber {
  background: rgba(245, 158, 11, 0.12);
  color: #b45309;
  border-color: rgba(245, 158, 11, 0.32);
  &:hover { background: rgba(245, 158, 11, 0.20); }
}
:root.dark .rpm-v2__chip--tone-emerald { background: rgba(16, 185, 129, 0.18); color: #6ee7b7; border-color: rgba(16, 185, 129, 0.4);
  &:hover { background: rgba(16, 185, 129, 0.28); } }
:root.dark .rpm-v2__chip--tone-pix { background: rgba(46, 189, 175, 0.20); color: #5dd9c8; border-color: rgba(46, 189, 175, 0.45);
  &:hover { background: rgba(46, 189, 175, 0.30); } }
:root.dark .rpm-v2__chip--tone-violet  { background: rgba(124, 58, 237, 0.20); color: #c4b5fd; border-color: rgba(124, 58, 237, 0.4);
  &:hover { background: rgba(124, 58, 237, 0.30); } }
:root.dark .rpm-v2__chip--tone-blue    { background: rgba(59, 130, 246, 0.18); color: #93c5fd; border-color: rgba(59, 130, 246, 0.4);
  &:hover { background: rgba(59, 130, 246, 0.28); } }
:root.dark .rpm-v2__chip--tone-amber   { background: rgba(245, 158, 11, 0.18); color: #fcd34d; border-color: rgba(245, 158, 11, 0.4);
  &:hover { background: rgba(245, 158, 11, 0.28); } }

/* Tamanho do SVG inline (PIX) — bate com w-3.5 h-3.5 do lucide. */
.rpm-v2__chip-icon { width: 14px; height: 14px; flex-shrink: 0; }

/* Active = solid + sombra de anel pra reforçar seleção. PIX é o caso
   mais sensível: a cor brand (rgb(46, 189, 175)) é "leve" e em contraste
   com o faded de 12% opacidade ficava ambíguo — o anel resolve. */
.rpm-v2__chip--active {
  color: #ffffff;
  border-color: transparent;
  font-weight: 600;
  box-shadow: 0 0 0 2px rgba(0, 0, 0, 0.04), 0 1px 3px rgba(0, 0, 0, 0.08);
}
.rpm-v2__chip--tone-emerald.rpm-v2__chip--active { background: #059669; &:hover { background: #047857; } }
.rpm-v2__chip--tone-pix.rpm-v2__chip--active     { background: rgb(46, 189, 175); &:hover { background: #1f8a7e; } }
.rpm-v2__chip--tone-violet.rpm-v2__chip--active  { background: #7c3aed; &:hover { background: #6d28d9; } }
.rpm-v2__chip--tone-blue.rpm-v2__chip--active    { background: #2563eb; &:hover { background: #1d4ed8; } }
.rpm-v2__chip--tone-amber.rpm-v2__chip--active   { background: #d97706; &:hover { background: #b45309; } }
:root.dark .rpm-v2__chip--active { color: #ffffff; }

/* ── Grid de campos ───────────────────────────────────────────── */
.rpm-v2__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 14px;
}
@media (max-width: 640px) {
  .rpm-v2__grid { grid-template-columns: 1fr; }
}
.rpm-v2__field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  min-width: 0;
}
.rpm-v2__field--full { grid-column: 1 / -1; }
.rpm-v2__field-label {
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  display: inline-flex;
  align-items: center;
  gap: 6px;
}
.rpm-v2__field-hint {
  font-weight: 400;
  font-size: 11px;
  color: rgb(var(--slate-9));
}
.rpm-v2__textarea {
  padding: 9px 12px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-12));
  font-size: 13px;
  resize: vertical;
  min-height: 60px;
  &:focus {
    outline: none;
    border-color: rgb(var(--blue-8));
    box-shadow: 0 0 0 3px rgb(var(--blue-9) / 0.15);
  }
  &::placeholder { color: rgb(var(--slate-9)); }
}

/* ── Currency input com prefixo R$ ─────────────────────────────── */
.rpm-v2__currency-wrap {
  position: relative;
  display: flex;
  align-items: center;
}
.rpm-v2__currency-prefix {
  position: absolute;
  left: 12px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-9));
  pointer-events: none;
  z-index: 1;
}
.rpm-v2__currency-input {
  width: 100%;
  height: 38px;
  padding: 9px 12px 9px 32px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-12));
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  text-align: right;
  &:focus {
    outline: none;
    border-color: rgb(var(--blue-8));
    box-shadow: 0 0 0 3px rgb(var(--blue-9) / 0.15);
  }
  &::placeholder { color: rgb(var(--slate-9)); }
}

/* ── Botão "Usar crédito disponível" — UX clique-pra-aplicar ──── */
/* Ação positiva (cliente já pagou antes) — tom emerald. Border dashed
   no estado "não aplicado" sugere "ação disponível"; ao aplicar vira
   sólido + estado "feito" com botão Remover. */
.rpm-v2__credit-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
  padding: 10px 12px;
  background: rgba(16, 185, 129, 0.10);
  color: #047857;
  border: 1px dashed rgba(16, 185, 129, 0.40);
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  font-family: inherit;
  transition: background 0.12s, border-color 0.12s, border-style 0.12s;
  strong {
    margin-left: auto;
    font-variant-numeric: tabular-nums;
    font-weight: 700;
  }
  &:hover {
    background: rgba(16, 185, 129, 0.18);
    border-color: rgba(16, 185, 129, 0.65);
    border-style: solid;
  }
}
:root.dark .rpm-v2__credit-btn {
  background: rgba(16, 185, 129, 0.18);
  color: #6ee7b7;
  border-color: rgba(16, 185, 129, 0.45);
  &:hover { background: rgba(16, 185, 129, 0.28); border-color: rgba(16, 185, 129, 0.70); }
}

.rpm-v2__credit-applied {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  background: rgba(16, 185, 129, 0.18);
  color: #065f46;
  border: 1px solid rgb(16, 185, 129);
  border-radius: 8px;
  font-size: 13px;
}
:root.dark .rpm-v2__credit-applied {
  background: rgba(16, 185, 129, 0.25);
  color: #a7f3d0;
  border-color: rgba(16, 185, 129, 0.65);
}
.rpm-v2__credit-applied-info {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 1;
  strong {
    font-variant-numeric: tabular-nums;
    font-weight: 700;
  }
}
.rpm-v2__credit-remove {
  padding: 2px 8px;
  background: transparent;
  color: #047857;
  border: none;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  text-decoration: underline;
  text-underline-offset: 2px;
  &:hover { color: #b91c1c; }
}
:root.dark .rpm-v2__credit-remove {
  color: #6ee7b7;
  &:hover { color: #fca5a5; }
}

// Aviso "Pagamento integral via crédito" — exibido acima dos chips quando
// o crédito do paciente cobre 100% do total devido. Mesmo padrão visual
// do PayTransactionModal (aba paciente) pra UX consistente.
.rpm-v2__credit-only {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  margin-bottom: 8px;
  background: rgba(16, 185, 129, 0.10);
  color: #065f46;
  border: 1px solid rgba(16, 185, 129, 0.40);
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.4;
  strong { font-weight: 700; }
}
:root.dark .rpm-v2__credit-only {
  background: rgba(16, 185, 129, 0.18);
  color: #a7f3d0;
  border-color: rgba(16, 185, 129, 0.50);
}

// Chips desabilitados — mantém visíveis pra info mas com opacity reduzida
// e sem clique. CSS `pointer-events: none` é a forma compatível com `:disabled`
// no <button> (que já bloqueia o click semanticamente).
.rpm-v2__chips--disabled {
  opacity: 0.45;
  pointer-events: none;
}

/* ── Summary ──────────────────────────────────────────────────── */
.rpm-v2__summary {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 14px 16px;
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.rpm-v2__summary-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 13px;
  color: rgb(var(--slate-11));
  strong {
    color: rgb(var(--slate-12));
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
}
.rpm-v2__summary-row--negative strong { color: #b91c1c; }
:root.dark .rpm-v2__summary-row--negative strong { color: #fca5a5; }
.rpm-v2__summary-row--total {
  font-size: 14px;
  font-weight: 600;
  padding-top: 8px;
  margin-top: 4px;
  border-top: 1px dashed rgb(var(--slate-5));
  span { color: rgb(var(--slate-12)); }
  strong { font-size: 16px; color: #047857; }
}
:root.dark .rpm-v2__summary-row--total strong { color: #6ee7b7; }
.rpm-v2__info {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  margin: 6px 0 0;
  font-size: 12px;
  color: rgb(var(--slate-11));
  strong { color: rgb(var(--slate-12)); font-weight: 600; }
}

/* ── Erro ─────────────────────────────────────────────────────── */
.rpm-v2__error {
  display: flex;
  align-items: center;
  gap: 6px;
  margin: 0;
  padding: 9px 12px;
  border-radius: 8px;
  background: rgba(220, 38, 38, 0.10);
  border-left: 3px solid #dc2626;
  color: #b91c1c;
  font-size: 12.5px;
}
:root.dark .rpm-v2__error { color: #fca5a5; background: rgba(220, 38, 38, 0.18); }

/* ── Footer sticky ────────────────────────────────────────────── */
.rpm-v2__footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-1));
}
@media (max-width: 640px) {
  .rpm-v2__footer { flex-direction: column-reverse; }
  .rpm-v2__footer > * { width: 100%; }
}
</style>
