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
import PaymentMethodBadge, {
  kindLabel,
} from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
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

// Refactor 2026-05-24: lista de métodos vem do backend (não mais hardcoded).
// Reflete o que a clínica configurou em Settings → Formas de Pagamento,
// inclusive provedor (Cielo, Stone) e nome custom. Operador escolhe um
// PaymentMethod específico (com id), backend recebe payment_method_id +
// derivado payment_method (kind canon) pra compat.
const paymentMethods = ref([]); // payload bruto do backend
const paymentMethodsLoading = ref(false);

// Kinds que aceitam baixa parcial (canon — boleto/dinheiro/pix podem ter
// valor < saldo da parcela; cartão/cheque exigem valor exato).
const PARTIAL_OK_KINDS = new Set(['dinheiro', 'pix', 'boleto']);

const paymentMethodId = ref(null);

// Modo override da conta destino — só ativa quando operador clica em "Alterar"
// pra escolher uma conta diferente da default da forma. Reset quando troca de
// forma (volta pro fluxo padrão "usa o default da nova forma").
const overrideBankAccount = ref(false);
const receivedAt = ref(new Date().toISOString().slice(0, 10));
const bankAccountId = ref(null);
const bankAccounts = ref([]);
const interestStr = ref('');
const fineStr = ref('');
const discountStr = ref('');

// Modo de entrada (R$ fixo vs % do bruto) por campo. UX comum em ERPs.
// Quando PCT, o valor digitado é a porcentagem (ex: "2,5" = 2,5%) aplicada
// sobre `grossCents` no momento de cálculo. Backend continua recebendo apenas
// `cents` (final) — toggle é puro frontend.
const MODE_BRL = 'BRL';
const MODE_PCT = 'PCT';
const interestMode = ref(MODE_BRL);
const fineMode = ref(MODE_BRL);
const discountMode = ref(MODE_BRL);

// Parse "2,5" → 250 basis points (ou "2.5" tolerado).
function parsePercentToBasisPoints(str) {
  if (!str) return 0;
  const clean = String(str).replace(',', '.').replace(/[^\d.]/g, '');
  const v = parseFloat(clean);
  if (Number.isNaN(v) || v <= 0) return 0;
  return Math.round(v * 100); // 2,5% → 250 bp
}
function bpsToCentsOfGross(bps, gross) {
  if (!bps || !gross) return 0;
  return Math.round((gross * bps) / 10000); // 250 bp de 100000c = 2500c (R$ 25)
}
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

// Cents finais derivam do modo: BRL = parse direto; PCT = % do gross.
// Ordem dos modificadores no PCT: juros e multa são % do bruto (antes do desconto);
// desconto é % do bruto também (não acumula sobre juros/multa). Convenção comum.
const interestCents = computed(() => {
  if (interestMode.value === MODE_PCT) {
    return bpsToCentsOfGross(parsePercentToBasisPoints(interestStr.value), grossCents.value);
  }
  return brlInputToCents(interestStr.value);
});
const fineCents = computed(() => {
  if (fineMode.value === MODE_PCT) {
    return bpsToCentsOfGross(parsePercentToBasisPoints(fineStr.value), grossCents.value);
  }
  return brlInputToCents(fineStr.value);
});
const discountCents = computed(() => {
  if (discountMode.value === MODE_PCT) {
    return bpsToCentsOfGross(parsePercentToBasisPoints(discountStr.value), grossCents.value);
  }
  return brlInputToCents(discountStr.value);
});

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

// Resolve o PaymentMethod selecionado pelo id (objeto completo do backend).
// Usado pra: validações por kind, auto-fill de conta padrão, label/badge.
const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find(m => m.id === paymentMethodId.value) || null,
);
const selectedKind = computed(() => selectedPaymentMethod.value?.kind || null);

const partialAllowed = computed(() => PARTIAL_OK_KINDS.has(selectedKind.value));

// Opções flat pro FormSelect, ordenadas por provedor → nome. Cada option
// carrega o objeto `method` completo em `raw` pra o slot custom renderizar
// com PaymentMethodBadge. `hint` mostra o provedor à direita em cinza.
const paymentMethodOptions = computed(() => {
  const list = [...paymentMethods.value];
  // Sem provedor primeiro (operação direta), depois alfabético por provider
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
  if (!paymentMethodId.value) return false;
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

// Label do método selecionado pra mensagens (ex: "PIX Cielo não aceita...").
// Usa nome custom se for diferente do kind label (alias real do método);
// fallback pro label canon ("PIX", "Boleto", etc.).
const currentMethodLabel = computed(() => {
  if (!selectedPaymentMethod.value) return '—';
  const name = (selectedPaymentMethod.value.name || '').trim();
  return name || kindLabel(selectedKind.value);
});

async function loadPaymentMethods() {
  paymentMethodsLoading.value = true;
  try {
    const { data } = await FinancialV2.paymentMethods.index({ status: 'active' });
    paymentMethods.value = (data?.data || []).filter(m => m.status === 'active');
    // Pré-seleciona PIX (sem provider) por default. Fallback: primeiro da lista.
    const pixDirect = paymentMethods.value.find(m => m.kind === 'pix' && !m.provider);
    paymentMethodId.value = pixDirect?.id || paymentMethods.value[0]?.id || null;
  } catch (e) {
    paymentMethods.value = [];
    paymentMethodId.value = null;
  } finally {
    paymentMethodsLoading.value = false;
  }
}

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
  // paymentMethodId é setado por loadPaymentMethods() (pré-seleciona PIX direto).
  // Não zerar aqui pra não invalidar o submit antes do load completar.
  receivedAt.value = new Date().toISOString().slice(0, 10);
  interestStr.value = '';
  fineStr.value = '';
  discountStr.value = '';
  interestMode.value = MODE_BRL;
  fineMode.value = MODE_BRL;
  discountMode.value = MODE_BRL;
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
      loadPaymentMethods();
      loadBankAccounts();
      loadPatientCredit();
    }
  },
);

watch(
  () => props.installments.map((i) => i.id).join(','),
  () => resetInputs(),
);

// Auto-fill ao escolher forma:
//  - Sempre sai do modo override (forma nova = fluxo limpo)
//  - Se a nova forma tem default_bank_account_id, usa ele
//  - Se NÃO tem default e bankAccount está vazio, deixa pro operador escolher
//  - Se NÃO tem default e bankAccount já tinha valor (selecionado antes), preserva
//  - Se a forma NÃO aceita parcial, força cada input pro saldo total
//    (corrige bug onde operador trocava forma e o valor parcial anterior ficava
//    "preso" gerando confusão — agora reset visível pro saldo real).
watch(selectedPaymentMethod, (method) => {
  if (!method) return;
  overrideBankAccount.value = false;
  if (method.default_bank_account_id) {
    bankAccountId.value = method.default_bank_account_id;
  }
  if (!PARTIAL_OK_KINDS.has(method.kind)) {
    for (const inst of props.installments) {
      const remaining = inst.remaining_cents ?? inst.amount_cents - (inst.received_amount_cents || 0);
      installmentInputs.value[inst.id] = centsToInputString(remaining);
    }
  }
});

const selectedBankAccount = computed(
  () => bankAccounts.value.find(b => b.id === bankAccountId.value) || null,
);

// Tem default na forma E operador NÃO está em modo override → mostra info-card.
// Caso contrário (sem default OU override ativado) → FormSelect editável.
const showBankAccountInfo = computed(
  () => !!selectedPaymentMethod.value?.default_bank_account_id && !overrideBankAccount.value,
);

onMounted(() => {
  if (props.show) {
    resetInputs();
    loadPaymentMethods();
    loadBankAccounts();
    loadPatientCredit();
  }
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  errorMessage.value = '';

  // Helper pra converter o input em decimal (R$ ou %) — backend recebe
  // tipo + value (intenção) e recalcula cents como source of truth.
  const valueAsDecimal = (str, mode) => {
    if (!str) return 0;
    const clean = String(str).replace(',', '.').replace(/[^\d.]/g, '');
    const v = parseFloat(clean);
    if (Number.isNaN(v) || v <= 0) return 0;
    if (mode === MODE_PCT) return v;          // % vai cru (ex: 2.5)
    return Math.round(v * 100) / 100;         // R$ com 2 decimais
  };

  const payload = {
    bank_account_id: bankAccountId.value,
    // payment_method_id: novo (referência ao PaymentMethod configurado).
    // payment_method: legacy (kind canon — backend deriva do _id se vier,
    // mas mandamos os 2 pra dar transição suave).
    payment_method_id: paymentMethodId.value,
    payment_method: selectedKind.value,
    received_at: receivedAt.value,
    // Modificadores enviados como tipo + value (padrão de mercado).
    // Backend é source of truth — recalcula cents do tipo+value (impede
    // adulteração de cents). `_cents` mantido pra compat legacy.
    interest_type:  interestMode.value === MODE_PCT ? 'percent' : 'fixed',
    interest_value: valueAsDecimal(interestStr.value, interestMode.value),
    interest_cents: interestCents.value,
    fine_type:      fineMode.value === MODE_PCT ? 'percent' : 'fixed',
    fine_value:     valueAsDecimal(fineStr.value, fineMode.value),
    fine_cents:     fineCents.value,
    discount_type:  discountMode.value === MODE_PCT ? 'percent' : 'fixed',
    discount_value: valueAsDecimal(discountStr.value, discountMode.value),
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

// Máscara de % — aceita até 2 decimais, vírgula ou ponto. Bloqueia 100+ pra
// não permitir desconto absurdo (acidentalmente "100" zerando o recebimento).
function applyPercentMask(event, refToUpdate) {
  let v = String(event.target.value).replace(/[^\d.,]/g, '').replace('.', ',');
  // Apenas 1 vírgula
  const parts = v.split(',');
  if (parts.length > 2) v = parts[0] + ',' + parts.slice(1).join('');
  // Limita 2 casas decimais
  const m = v.match(/^(\d+)(?:,(\d{0,2}))?/);
  v = m ? (m[2] !== undefined ? `${m[1]},${m[2]}` : m[1]) : '';
  // Cap 99,99 (proteção contra "100%" zerar tudo)
  const num = parseFloat(v.replace(',', '.'));
  if (!Number.isNaN(num) && num >= 100) v = '99,99';
  refToUpdate.value = v;
  event.target.value = v;
}

const onInterestInput = (e) => (interestMode.value === MODE_PCT
  ? applyPercentMask(e, interestStr)
  : applyMoneyMask(e, interestStr));
const onFineInput = (e) => (fineMode.value === MODE_PCT
  ? applyPercentMask(e, fineStr)
  : applyMoneyMask(e, fineStr));
const onDiscountInput = (e) => (discountMode.value === MODE_PCT
  ? applyPercentMask(e, discountStr)
  : applyMoneyMask(e, discountStr));

// Ao trocar modo, limpa o valor pra evitar "2,50" virar "R$ 2,50" (semântica
// muito diferente — 2,5% de R$1000 = R$25 vs R$2,50 valor fixo).
//
// Funções DEDICADAS por campo (não genérica que recebe ref como arg) porque
// Vue 3 auto-unwrappa refs em template handlers — `@click="setMode(modeRef)"`
// passaria a STRING do valor, não o ref, e `modeRef.value = X` quebraria com
// "Cannot create property 'value' on string 'BRL'".
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
                  <!-- `readonly` quando a forma não aceita parcial — operador
                       não pode editar pra valor menor que o saldo. Evita
                       a confusão de "digitei R$ 500 mas o sistema bloqueia"
                       depois. Junto com o auto-reset no watch acima, garante
                       que o input sempre reflete um valor válido. -->
                  <input
                    :value="installmentInputs[inst.id]"
                    type="text"
                    inputmode="numeric"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    :class="{ 'rpm-v2__currency-input--readonly': !partialAllowed }"
                    :readonly="!partialAllowed"
                    :title="partialAllowed ? null : currentMethodLabel + ' exige valor exato do saldo'"
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

          <!-- Forma de pagamento — dropdown moderno (FormSelect com slots).
               Trigger mostra PaymentMethodBadge + provider hint. Dropdown
               aberto lista cada método com mesmo badge + provedor à direita.
               Refactor 2026-05-24: substituiu cards (quebravam quando nome
               custom era diferente do kindLabel — ex: "Crédito" vs "Cartão
               de Crédito"). Dropdown lida com qualquer comprimento sem
               quebrar layout. -->
          <section class="rpm-v2__section">
            <label class="rpm-v2__field-label">Forma de pagamento</label>
            <div v-if="creditCoversAll" class="rpm-v2__credit-only">
              <i class="i-lucide-wallet w-3.5 h-3.5" />
              <span>Pagamento integral via <strong>crédito do paciente</strong> — método selecionado será ignorado.</span>
            </div>

            <div v-if="paymentMethodsLoading" class="rpm-v2__pm-loading">
              <i class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin" />
              <span>Carregando formas de pagamento…</span>
            </div>

            <div v-else-if="paymentMethods.length === 0" class="rpm-v2__hint rpm-v2__hint--warn">
              <i class="i-lucide-info w-3.5 h-3.5" />
              Nenhuma forma de pagamento configurada. Vá em Settings → Formas de Pagamento.
            </div>

            <FormSelect
              v-else
              v-model="paymentMethodId"
              :options="paymentMethodOptions"
              :disabled="creditCoversAll"
              placeholder="Selecione a forma"
              auto-searchable
              search-placeholder="Buscar (PIX, Cielo, Stone...)"
            >
              <!-- Trigger: badge da forma selecionada (sem chip "até Nx" —
                   redundante no contexto: já estamos pagando UMA parcela específica).
                   size=md pra ter mais presença visual no campo principal. -->
              <template #selected="{ option }">
                <PaymentMethodBadge
                  v-if="option?.raw"
                  :kind="option.raw.kind"
                  :method="option.raw"
                  size="md"
                  hide-installments
                />
              </template>
              <!-- Cada option no dropdown: badge à esquerda + provedor (cinza) à direita -->
              <template #option="{ option }">
                <PaymentMethodBadge
                  :kind="option.raw.kind"
                  :method="option.raw"
                  size="md"
                  hide-installments
                />
                <span v-if="option.hint" class="rpm-v2__pm-provider-hint">
                  <i class="i-lucide-building-2 w-3 h-3" />
                  {{ option.hint }}
                </span>
              </template>
            </FormSelect>
          </section>

          <!-- Grid de campos -->
          <section class="rpm-v2__section">
            <div class="rpm-v2__grid">
              <!-- Conta destino — info-card quando a forma tem default
                   (caso comum, 95%); FormSelect quando sem default OU
                   operador clica "Alterar" pra override pontual. -->
              <div class="rpm-v2__field">
                <span class="rpm-v2__field-label">Conta destino</span>
                <div
                  v-if="showBankAccountInfo && selectedBankAccount"
                  class="rpm-v2__bank-info"
                >
                  <i class="i-lucide-landmark w-3.5 h-3.5" />
                  <span class="rpm-v2__bank-info-name">{{ selectedBankAccount.name }}</span>
                  <span class="rpm-v2__bank-info-tag">da forma</span>
                  <button
                    type="button"
                    class="rpm-v2__bank-info-edit"
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

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">Data do recebimento</span>
                <DatePickerBR v-model="receivedAt" />
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">
                  Juros
                  <span class="rpm-v2__mode-toggle">
                    <button type="button" class="rpm-v2__mode-btn" :class="{ 'rpm-v2__mode-btn--active': interestMode === MODE_BRL }" @click="setInterestMode(MODE_BRL)">R$</button>
                    <button type="button" class="rpm-v2__mode-btn" :class="{ 'rpm-v2__mode-btn--active': interestMode === MODE_PCT }" @click="setInterestMode(MODE_PCT)">%</button>
                  </span>
                </span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">{{ interestMode === MODE_PCT ? '%' : 'R$' }}</span>
                  <input
                    :value="interestStr"
                    type="text"
                    inputmode="decimal"
                    :placeholder="interestMode === MODE_PCT ? '0,00' : '0,00'"
                    class="rpm-v2__currency-input"
                    @input="onInterestInput"
                  />
                </div>
                <span v-if="interestMode === MODE_PCT && interestCents > 0" class="rpm-v2__mode-hint">
                  = {{ fmt(interestCents) }}
                </span>
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">
                  Multa
                  <span class="rpm-v2__mode-toggle">
                    <button type="button" class="rpm-v2__mode-btn" :class="{ 'rpm-v2__mode-btn--active': fineMode === MODE_BRL }" @click="setFineMode(MODE_BRL)">R$</button>
                    <button type="button" class="rpm-v2__mode-btn" :class="{ 'rpm-v2__mode-btn--active': fineMode === MODE_PCT }" @click="setFineMode(MODE_PCT)">%</button>
                  </span>
                </span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">{{ fineMode === MODE_PCT ? '%' : 'R$' }}</span>
                  <input
                    :value="fineStr"
                    type="text"
                    inputmode="decimal"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    @input="onFineInput"
                  />
                </div>
                <span v-if="fineMode === MODE_PCT && fineCents > 0" class="rpm-v2__mode-hint">
                  = {{ fmt(fineCents) }}
                </span>
              </label>

              <label class="rpm-v2__field">
                <span class="rpm-v2__field-label">
                  Desconto
                  <span class="rpm-v2__mode-toggle">
                    <button type="button" class="rpm-v2__mode-btn" :class="{ 'rpm-v2__mode-btn--active': discountMode === MODE_BRL }" @click="setDiscountMode(MODE_BRL)">R$</button>
                    <button type="button" class="rpm-v2__mode-btn" :class="{ 'rpm-v2__mode-btn--active': discountMode === MODE_PCT }" @click="setDiscountMode(MODE_PCT)">%</button>
                  </span>
                </span>
                <div class="rpm-v2__currency-wrap">
                  <span class="rpm-v2__currency-prefix">{{ discountMode === MODE_PCT ? '%' : 'R$' }}</span>
                  <input
                    :value="discountStr"
                    type="text"
                    inputmode="decimal"
                    placeholder="0,00"
                    class="rpm-v2__currency-input"
                    @input="onDiscountInput"
                  />
                </div>
                <span v-if="discountMode === MODE_PCT && discountCents > 0" class="rpm-v2__mode-hint">
                  = {{ fmt(discountCents) }}
                </span>
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
            color="blue"
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

/* ── Forma de pagamento (dropdown FormSelect com slots) ───────── */
/* Refactor 2026-05-24: cards substituídos por dropdown moderno.
 * Visual do trigger/option vem do PaymentMethodBadge — single source
 * of truth no beclinic_core. */
.rpm-v2__pm-loading {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: rgb(var(--slate-9));
  padding: 8px 0;
}
/* Hint do provedor que aparece à direita de cada option do dropdown */
.rpm-v2__pm-provider-hint {
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

/* Info-card da conta destino — quando forma tem default_bank_account_id
 * mostra a conta selecionada como read-only + botão pequeno "Alterar".
 * Reduz fricção no fluxo comum (95% dos casos a conta é a default da forma).
 * Fix 2026-05-24: `display: flex` (não inline-flex) + box-sizing: border-box
 * + min-height pra alinhar com DatePickerBR/FormSelect na mesma linha do grid. */
.rpm-v2__bank-info {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 12px;
  min-height: 38px;
  box-sizing: border-box;
  background: rgb(var(--blue-2));
  border: 1px solid rgb(var(--blue-5));
  border-radius: 8px;
  font-size: 13px;
  color: rgb(var(--slate-12));
  width: 100%;
  min-width: 0;

  i { color: rgb(var(--blue-10)); flex-shrink: 0; }
}
.rpm-v2__bank-info-name {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
}
.rpm-v2__bank-info-tag {
  font-size: 10.5px;
  font-weight: 500;
  padding: 1px 6px;
  border-radius: 999px;
  background: rgb(var(--blue-4));
  color: rgb(var(--blue-11));
  text-transform: lowercase;
  letter-spacing: 0.01em;
  white-space: nowrap;
}
.rpm-v2__bank-info-edit {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 3px 8px;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: rgb(var(--blue-11));
  font-size: 11.5px;
  font-weight: 500;
  cursor: pointer;
  transition: background 0.12s, border-color 0.12s;
  white-space: nowrap;

  &:hover {
    background: rgb(var(--blue-3));
    border-color: rgb(var(--blue-7));
  }
}

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
  /* line-height explícito 2026-05-24: sem isso o label herdava ~1.5 do parent,
   * empurrando o input embaixo (Data do recebimento ficava 3px abaixo do
   * info-card da Conta destino). 16px iguala em todos os campos do grid. */
  line-height: 16px;
}

/* Toggle R$/% inline no label (Juros, Multa, Desconto). Pill segmentado
 * compacto à direita do nome do campo — preserva line-height de 16px.
 * Quando %, o input passa a interpretar o valor como porcentagem do bruto. */
.rpm-v2__mode-toggle {
  margin-left: auto;
  display: inline-flex;
  align-items: center;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 999px;
  padding: 1px;
  overflow: hidden;
}
.rpm-v2__mode-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 24px;
  height: 16px;
  padding: 0 6px;
  background: transparent;
  border: 0;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 600;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
  line-height: 1;

  &:hover:not(.rpm-v2__mode-btn--active) {
    color: rgb(var(--slate-12));
  }

  &--active {
    background: rgb(var(--blue-9));
    color: #ffffff;
  }
}
.rpm-v2__mode-hint {
  margin-top: 4px;
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
  font-style: italic;
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

  /* Estado readonly — sinaliza visualmente que o campo está bloqueado
   * (forma de pagamento não aceita baixa parcial). Sem essa cue, operador
   * tenta digitar e fica confuso porque "nada acontece". */
  &--readonly {
    background: rgb(var(--slate-3));
    color: rgb(var(--slate-10));
    cursor: not-allowed;
    border-style: dashed;
  }
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

// `.rpm-v2__chips--disabled` removido — substituído por `.rpm-v2__pm-groups--disabled`.

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
