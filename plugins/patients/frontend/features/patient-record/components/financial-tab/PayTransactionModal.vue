<script setup>
/**
 * PayTransactionModal — modal "Registrar Pagamento" da aba Financeiro.
 *
 * Refatorado em [1.5.4.6]:
 *   - Tailwind dark-only hardcoded (`bg-slate-900`, `text-slate-300`, etc.)
 *     trocado por classes SCSS com tokens dual-theme (`rgb(var(--slate-N))`)
 *     pra funcionar em light + dark mode.
 *   - Status badge custom (`txStatusConfig().cls`) trocado por componente
 *     `Badge` do beclinic_core (padrão do projeto).
 *   - Botões de método de pagamento ganham cor semântica via
 *     `PAYMENT_METHOD_VISUAL` (PIX=cyan, Crédito=violet, Dinheiro=emerald,
 *     Boleto=amber, etc.) — facilita reconhecimento rápido.
 */
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import { formatCurrency } from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import {
  txStatusConfig,
} from '@plugins/patients/frontend/constants/financial';

// Refactor 2026-05-24: PaymentMethodBadge + lista REAL de payment_methods.
// Substitui PAYMENT_METHODS hardcoded — agora vem do backend (Settings →
// Formas de Pagamento). Mesma UX do ReceivePaymentModalV2 global pra
// consistência total entre telas.
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import {
  parseCurrencyInput,
} from '@plugins/patients/frontend/features/patient-record/utils/financialFormatters';
import {
  brlInputToCents,
  centsToBRL,
  formatCurrencyInput,
} from '@plugins/financial/frontend/features/financial/v2/composables/useMoney';
import FinancialV2 from '@plugins/financial/frontend/features/financial/v2/api/financialV2';

// Mapa visual do tipo de recorrência (mesma paleta usada na timeline:
// avulso=slate, parcelamento=blue, mensalidade=violet, plano=teal) para que
// o usuário reconheça de cara qual lançamento é qual sem precisar ler o título.
const RECURRENCE_VISUAL = {
  avulso: { color: 'slate', icon: 'i-lucide-circle-dot' },
  parcelamento: { color: 'blue', icon: 'i-lucide-layers-2' },
  mensalidade: { color: 'violet', icon: 'i-lucide-repeat' },
  plano_tratamento: { color: 'teal', icon: 'i-lucide-stethoscope' },
};

const props = defineProps({
  open: { type: Boolean, default: false },
  initialTxId: { type: [Number, String, null], default: null },
  transactions: { type: Array, default: () => [] },
  bankAccounts: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  // Paciente atual — usado para buscar saldo de crédito disponível
  // (`Financial::PatientCredit`) e oferecer "Abater crédito" no pagamento.
  patient: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const { t } = useI18n();

// Métodos que aceitam baixa parcial (canon BUG-01). Cartão/débito/transf
// não permitem porque tipicamente o valor já vem fechado da maquininha/banco.
const PARTIAL_OK_KINDS = new Set(['dinheiro', 'pix', 'boleto']);

const blankForm = () => ({
  paid_at: new Date().toISOString().split('T')[0],
  bank_account_id: '',
  // Valor recebido — opcional. Vazio = paga o saldo restante completo.
  // Se preenchido com valor menor, ativa baixa parcial (canon BUG-01):
  //   - parcela vira 'parcial' com received_amount = valor_digitado
  //   - nova parcela é gerada com saldo restante (se keepInstallmentOpen)
  // Se maior que o saldo, excedente vira PatientCredit (saldo a favor).
  received_amount_raw: '',
});

const selectedTxId = ref(props.initialTxId);
const payForm = ref(blankForm());

// Lista real de Payment Methods (canon Settings → Formas de Pagamento).
// Backend retorna kind/name/provider/provider_alias/default_bank_account_id.
const paymentMethods = ref([]);
const paymentMethodsLoading = ref(false);
const paymentMethodId = ref(null);
const overrideBankAccount = ref(false);

// Modo de entrada R$/% por modificador (intenção do operador).
const MODE_BRL = 'BRL';
const MODE_PCT = 'PCT';
const interestMode = ref(MODE_BRL);
const fineMode = ref(MODE_BRL);
const discountMode = ref(MODE_BRL);

// Campos avançados (paridade com modal de A Receber global) — todos opcionais.
const interestStr = ref('');             // Juros adicionados (R$ ou %)
const fineStr = ref('');                 // Multa adicionada (R$ ou %)
const discountStr = ref('');             // Desconto concedido (R$ ou %)
// Abater crédito agora é um toggle "tudo ou nada" pra UX mais intuitiva:
// recepção clica num botão e o crédito é aplicado automaticamente (limitado
// pelo saldo disponível e pelo total a receber). Pra customização fina
// (abater valor parcial específico), seria caso edge — recepção pode pedir
// pra abrir o componente expandido depois.
const applyCreditEnabled = ref(false);   // Boolean: usar crédito ou não
const keepInstallmentOpen = ref(true);   // Em baixa parcial, gerar nova parcela com saldo
const notes = ref('');                   // Observações internas
const patientCreditBalance = ref(0);     // Saldo de crédito disponível (centavos)

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

async function loadPaymentMethods() {
  paymentMethodsLoading.value = true;
  try {
    const { data } = await FinancialV2.paymentMethods.index({ status: 'active' });
    paymentMethods.value = (data?.data || []).filter(m => m.status === 'active');
    // Pré-seleciona PIX direto (sem provider) — fallback pro primeiro da lista.
    const pixDirect = paymentMethods.value.find(m => m.kind === 'pix' && !m.provider);
    paymentMethodId.value = pixDirect?.id || paymentMethods.value[0]?.id || null;
  } catch {
    paymentMethods.value = [];
    paymentMethodId.value = null;
  } finally {
    paymentMethodsLoading.value = false;
  }
}

// Helpers % (mesma lógica do ReceivePaymentModalV2)
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

watch(
  () => props.open,
  isOpen => {
    if (isOpen) {
      selectedTxId.value = props.initialTxId;
      payForm.value = {
        ...blankForm(),
        bank_account_id:
          props.bankAccounts.length === 1 ? props.bankAccounts[0].id : '',
      };
      interestStr.value = '';
      fineStr.value = '';
      discountStr.value = '';
      interestMode.value = MODE_BRL;
      fineMode.value = MODE_BRL;
      discountMode.value = MODE_BRL;
      overrideBankAccount.value = false;
      applyCreditEnabled.value = false;
      keepInstallmentOpen.value = true;
      notes.value = '';
      loadPatientCredit();
      loadPaymentMethods();
    }
  }
);

// Watch reativo nas bankAccounts — pré-seleciona automaticamente quando vira
// uma única conta disponível. Cobre o caso onde bankAccounts chega async no
// FinancialTab depois de o modal já estar aberto (estado inicial vazio).
watch(
  () => props.bankAccounts,
  newAccounts => {
    if (newAccounts.length === 1 && !payForm.value.bank_account_id) {
      payForm.value.bank_account_id = newAccounts[0].id;
    }
  },
  { immediate: true }
);

// Atualiza o input de valor recebido sempre que troca a parcela selecionada.
// Default = saldo restante da parcela (ou amount se não houver remaining).
watch(selectedTxId, () => {
  payForm.value.received_amount_raw = '';
});

// Mask handler reutilizável pros inputs de dinheiro (juros, multa, desconto, abater).
function applyMoneyMask(event, refToUpdate) {
  const formatted = formatCurrencyInput(event.target.value);
  refToUpdate.value = formatted;
  // eslint-disable-next-line no-param-reassign
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
  // eslint-disable-next-line no-param-reassign
  event.target.value = v;
}
const onInterestInput = e => (interestMode.value === MODE_PCT
  ? applyPercentMask(e, interestStr) : applyMoneyMask(e, interestStr));
const onFineInput = e => (fineMode.value === MODE_PCT
  ? applyPercentMask(e, fineStr) : applyMoneyMask(e, fineStr));
const onDiscountInput = e => (discountMode.value === MODE_PCT
  ? applyPercentMask(e, discountStr) : applyMoneyMask(e, discountStr));

// Setters dedicados por campo (Vue auto-unwrap refs em template handlers).
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

// Resolve o PaymentMethod selecionado pelo id (objeto completo do backend).
const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find(m => m.id === paymentMethodId.value) || null,
);
const selectedKind = computed(() => selectedPaymentMethod.value?.kind || null);

// Auto-fill de conta destino quando troca a forma + saída do modo override.
watch(selectedPaymentMethod, (method) => {
  if (!method) return;
  overrideBankAccount.value = false;
  if (method.default_bank_account_id) {
    payForm.value.bank_account_id = method.default_bank_account_id;
  }
});

const selectedBankAccount = computed(
  () => props.bankAccounts.find(b => b.id === payForm.value.bank_account_id) || null,
);
const showBankAccountInfo = computed(
  () => !!selectedPaymentMethod.value?.default_bank_account_id && !overrideBankAccount.value,
);

// Opções flat pro FormSelect ordenadas por provedor → nome.
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

const formatDate = dateStr => formatDateBR(dateStr) || '—';

const pendingTransactions = computed(() =>
  (props.transactions || []).filter(
    tx => tx.status === 'pendente' || tx.status === 'vencido'
  )
);

const selectedTransaction = computed(() =>
  props.transactions.find(tx => tx.id === selectedTxId.value)
);

const bankAccountOptions = computed(() =>
  props.bankAccounts.map(ba => {
    const prefix = ba.bank_code ? `${ba.bank_code} · ` : '';
    const suffix = ba.bank_name ? ` (${ba.bank_name})` : '';
    return { value: ba.id, label: `${prefix}${ba.name}${suffix}` };
  })
);

const statusLabel = status => {
  const cfg = txStatusConfig(status);
  return cfg.labelKey ? t(cfg.labelKey) : cfg.label;
};

// Map status → intent semântico do Badge (sem hex hardcoded)
const statusIntent = status => {
  switch (status) {
    case 'pago':
      return 'success';
    case 'pendente':
      return 'warning';
    case 'vencido':
      return 'danger';
    case 'reembolsado':
      return 'info';
    default:
      return 'neutral';
  }
};

// Helpers de contexto da parcela (vem enriquecido pelo FinancialTab.vue).
const parentVisual = tx => RECURRENCE_VISUAL[tx?.parent_recurrence] || RECURRENCE_VISUAL.avulso;

const recurrenceLabel = recurrence => {
  if (!recurrence) return null;
  return t(`PATIENT_FINANCIAL.TIMELINE.RECURRENCE.${recurrence.toUpperCase()}`);
};

// Cálculo do que será aplicado a cada parcela. Quando o usuário NÃO
// preenche `received_amount_raw`, omitimos `amount_cents` no payload
// (backend usa o saldo restante da parcela como default).
const partialAmountCents = computed(() => {
  const raw = payForm.value.received_amount_raw;
  if (!raw) return null;
  const value = parseCurrencyInput(raw);
  return value > 0 ? Math.round(value * 100) : null;
});

const tx = selectedTransaction;
const remainingCents = computed(() => {
  const t = tx.value;
  if (!t) return 0;
  if (t.remaining_cents != null) return t.remaining_cents;
  if (t.remaining != null) return Math.round(Number(t.remaining) * 100);
  if (t.amount_cents != null) return t.amount_cents - (t.received_amount_cents || 0);
  return Math.round(Number(t.amount || 0) * 100);
});

// Hint visual mostrando o efeito do valor digitado.
const partialAmountHint = computed(() => {
  const cents = partialAmountCents.value;
  if (cents == null) return '';
  const remaining = remainingCents.value;
  if (cents < remaining) {
    const restCents = remaining - cents;
    if (!keepInstallmentOpen.value) {
      return `Baixa parcial — saldo de ${formatCurrency(restCents / 100)} ficará pendente nesta parcela (não será gerada nova).`;
    }
    return `Baixa parcial — saldo de ${formatCurrency(restCents / 100)} será gerado em uma nova parcela.`;
  }
  if (cents > remaining) {
    const extraCents = cents - remaining;
    return `Excedente de ${formatCurrency(extraCents / 100)} será creditado como saldo a favor do paciente.`;
  }
  return '';
});

// Cents derivam do modo: BRL = parse direto; PCT = % do gross (que = saldo a aplicar).
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

// Valor bruto = o que de fato será aplicado na parcela (vazio = saldo total).
const grossCents = computed(() => partialAmountCents.value ?? remainingCents.value);

// Crédito a abater quando o toggle está ON: aplica TUDO que estiver disponível,
// limitado ao bruto + acréscimos (juros + multa) − desconto. Evita abater
// valor maior que o devido (que viraria saldo a favor de novo — sem sentido).
const maxCreditApplicable = computed(() => {
  const cap = grossCents.value + interestCents.value + fineCents.value - discountCents.value;
  return Math.max(0, Math.min(patientCreditBalance.value, cap));
});
const applyCreditCents = computed(() => applyCreditEnabled.value ? maxCreditApplicable.value : 0);

// Total a creditar na conta destino = bruto + juros + multa − desconto − crédito abatido.
const netCents = computed(() =>
  grossCents.value +
  interestCents.value +
  fineCents.value -
  discountCents.value -
  applyCreditCents.value
);

// Cartão/débito/transf não aceitam baixa parcial (canon BUG-01).
// Se o usuário escolher esses, escondemos o toggle de "gerar nova parcela".
// Agora usa o kind do PaymentMethod selecionado (não mais string hardcoded).
const partialAllowed = computed(() => PARTIAL_OK_KINDS.has(selectedKind.value));

// Baixa parcial = usuário digitou valor menor que o saldo da parcela.
// Quando isso acontece, faz sentido perguntar "gerar nova parcela com o
// restante?". Quando NÃO acontece (paga tudo ou nem digitou nada), não tem
// saldo restante pra gerar — o checkbox vira ruído.
const isPartialPayment = computed(() => {
  if (partialAmountCents.value == null) return false;
  return partialAmountCents.value > 0 && partialAmountCents.value < remainingCents.value;
});

const willCreateRemainder = computed(() => {
  return partialAllowed.value && keepInstallmentOpen.value && isPartialPayment.value;
});

// Validação de submit — conta destino é obrigatória quando há contas
// cadastradas (mesma regra do A Receber). Evita submit silenciosamente
// pra uma conta indefinida, que entraria como NULL no banco.
// `paymentMethodId` também obrigatório (refactor 2026-05-24).
const canSubmit = computed(() => {
  if (!selectedTxId.value) return false;
  if (props.loading) return false;
  if (!paymentMethodId.value) return false;
  if (props.bankAccounts.length > 0 && !payForm.value.bank_account_id) return false;
  return true;
});

// Crédito cobre 100% do total devido = não há entrada de dinheiro novo,
// só consumo de saldo a favor. UX: desabilitar seletor de método (não faz
// sentido escolher PIX se nada vai entrar via PIX) e indicar visualmente
// que o método efetivo é "credito_paciente".
const creditCoversAll = computed(() => {
  if (!applyCreditEnabled.value) return false;
  if (applyCreditCents.value <= 0) return false;
  const totalDue = grossCents.value + interestCents.value + fineCents.value - discountCents.value;
  return applyCreditCents.value >= totalDue;
});

const handleConfirm = () => {
  if (!selectedTxId.value) return;
  const payload = {
    // Refactor 2026-05-24: envia payment_method_id (canon) + payment_method
    // (kind legacy pra compat). Backend deriva tipo do _id quando vier.
    payment_method_id: paymentMethodId.value,
    payment_method: selectedKind.value,
    paid_at: payForm.value.paid_at,
    bank_account_id: payForm.value.bank_account_id || null,
  };
  // Só envia amount_cents se o usuário preencheu valor diferente do total.
  // Mantém o comportamento default (paga o saldo restante completo).
  if (partialAmountCents.value != null) {
    payload.amount_cents = partialAmountCents.value;
  }
  // Modificadores: tipo + value (intenção) + cents (compat). Backend é
  // source of truth — recalcula cents do gross × pct quando type=percent.
  if (interestCents.value > 0 || interestMode.value === MODE_PCT) {
    payload.interest_type = interestMode.value === MODE_PCT ? 'percent' : 'fixed';
    payload.interest_value = valueAsDecimal(interestStr.value, interestMode.value);
    payload.interest_cents = interestCents.value;
  }
  if (fineCents.value > 0 || fineMode.value === MODE_PCT) {
    payload.fine_type = fineMode.value === MODE_PCT ? 'percent' : 'fixed';
    payload.fine_value = valueAsDecimal(fineStr.value, fineMode.value);
    payload.fine_cents = fineCents.value;
  }
  if (discountCents.value > 0 || discountMode.value === MODE_PCT) {
    payload.discount_type = discountMode.value === MODE_PCT ? 'percent' : 'fixed';
    payload.discount_value = valueAsDecimal(discountStr.value, discountMode.value);
    payload.discount_cents = discountCents.value;
  }
  if (applyCreditCents.value > 0) payload.apply_patient_credit_cents = applyCreditCents.value;
  if (notes.value?.trim()) payload.notes = notes.value.trim();
  // keep_installment_open só faz sentido pra métodos parciais. Default backend
  // é `true`, então só enviamos `false` explicitamente quando desligado.
  if (partialAllowed.value && keepInstallmentOpen.value === false) {
    payload.keep_installment_open = false;
  }
  emit('confirm', {
    txId: selectedTxId.value,
    payload,
  });
};
</script>

<template>
  <div
    v-if="open"
    class="pay-modal__backdrop"
  >
    <div class="pay-modal">
      <header class="pay-modal__header">
        <div>
          <h3 class="pay-modal__title">
            <i class="i-lucide-receipt pay-modal__title-icon" />
            Receber pagamento
          </h3>
          <p class="pay-modal__subtitle">
            {{ patient?.name || 'Confirme o método e data do pagamento' }}
          </p>
        </div>
        <BeclinicButton
          size="sm"
          variant="ghost"
          color="slate"
          icon="i-lucide-x"
          @click="emit('close')"
        />
      </header>

      <div class="pay-modal__body">
        <!-- Seletor de parcela (quando aberto pelo botão do header) -->
        <section v-if="selectedTxId === null" class="pay-modal__section">
          <label class="pay-modal__label">
            {{ t('PATIENT_FINANCIAL.MODALS.PAY.SELECT_INSTALLMENT') }}
            <span class="pay-modal__required">*</span>
          </label>
          <div
            v-if="pendingTransactions.length === 0"
            class="pay-modal__empty"
          >
            <i class="i-lucide-check-circle-2 pay-modal__empty-icon" />
            {{ t('PATIENT_FINANCIAL.MODALS.PAY.NO_PENDING') }}
          </div>
          <div v-else class="pay-modal__list">
            <button
              v-for="pt in pendingTransactions"
              :key="pt.id"
              type="button"
              class="pay-modal__list-item"
              :class="{ 'is-selected': selectedTxId === pt.id }"
              @click="selectedTxId = pt.id"
            >
              <!-- Ícone do tipo (avulso/parcelamento/mensalidade) — reconhecimento
                   visual rápido sem precisar ler o badge. -->
              <span
                class="pay-modal__list-item-icon"
                :class="`pay-modal__list-item-icon--${parentVisual(pt).color}`"
              >
                <i :class="parentVisual(pt).icon" class="w-4 h-4" />
              </span>

              <div class="pay-modal__list-item-info">
                <div class="pay-modal__list-item-title-row">
                  <!-- Origem do lançamento (ex: "Plano de Tratamento #25",
                       "Orçamento #29") + badge de tipo. Identifica DE QUAL
                       lançamento a parcela é, sem ambiguidade. -->
                  <p class="pay-modal__list-item-title">
                    {{ pt.parent_label || pt.description || t('PATIENT_FINANCIAL.MODALS.PAY.DEFAULT_INSTALLMENT') }}
                  </p>
                  <Badge
                    v-if="pt.parent_recurrence && recurrenceLabel(pt.parent_recurrence)"
                    :label="recurrenceLabel(pt.parent_recurrence)"
                    :color="parentVisual(pt).color"
                    :icon="parentVisual(pt).icon"
                  />
                </div>
                <p class="pay-modal__list-item-meta">
                  <span class="pay-modal__list-item-installment">
                    {{
                      t('PATIENT_FINANCIAL.MODALS.PAY.INSTALLMENT_OF', {
                        current: pt.installment_number || 1,
                        total: pt.total_installments || 1,
                      })
                    }}
                  </span>
                  <span class="pay-modal__list-item-sep">·</span>
                  <span>
                    {{
                      t('PATIENT_FINANCIAL.MODALS.PAY.DUE_AT', {
                        date: pt.due_date ? formatDate(pt.due_date) : '—',
                      })
                    }}
                  </span>
                </p>
              </div>
              <div class="pay-modal__list-item-right">
                <p class="pay-modal__list-item-amount">
                  {{ formatCurrency(pt.amount) }}
                </p>
                <Badge
                  :label="statusLabel(pt.status)"
                  :intent="statusIntent(pt.status)"
                />
              </div>
            </button>
          </div>
        </section>

        <!-- Info da parcela já selecionada — mesma estrutura do item da
             lista (com origem + badge de tipo), pra manter consistência. -->
        <section
          v-else
          class="pay-modal__selected"
        >
          <span
            v-if="selectedTransaction"
            class="pay-modal__list-item-icon"
            :class="`pay-modal__list-item-icon--${parentVisual(selectedTransaction).color}`"
          >
            <i :class="parentVisual(selectedTransaction).icon" class="w-4 h-4" />
          </span>
          <div class="pay-modal__selected-info">
            <p class="pay-modal__selected-label">
              <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
              {{ t('PATIENT_FINANCIAL.MODALS.PAY.SELECTED') }}
            </p>
            <div class="pay-modal__list-item-title-row">
              <p class="pay-modal__selected-title">
                {{
                  selectedTransaction?.parent_label ||
                  selectedTransaction?.description ||
                  t('PATIENT_FINANCIAL.MODALS.PAY.DEFAULT_INSTALLMENT')
                }}
              </p>
              <Badge
                v-if="selectedTransaction?.parent_recurrence && recurrenceLabel(selectedTransaction.parent_recurrence)"
                :label="recurrenceLabel(selectedTransaction.parent_recurrence)"
                :color="parentVisual(selectedTransaction).color"
                :icon="parentVisual(selectedTransaction).icon"
              />
            </div>
            <p v-if="selectedTransaction" class="pay-modal__selected-meta">
              {{
                t('PATIENT_FINANCIAL.MODALS.PAY.INSTALLMENT_OF', {
                  current: selectedTransaction.installment_number || 1,
                  total: selectedTransaction.total_installments || 1,
                })
              }}
              <span class="pay-modal__list-item-sep">·</span>
              {{ formatCurrency(selectedTransaction.amount) }}
            </p>
          </div>
          <!-- Trocar só faz sentido quando há mais de 1 parcela pendente
               pra escolher. Com 1 só (ou modal aberto direto numa parcela),
               o botão vira ruído cognitivo. -->
          <BeclinicButton
            v-if="pendingTransactions.length > 1"
            size="xs"
            variant="link"
            color="ruby"
            :label="t('PATIENT_FINANCIAL.MODALS.PAY.CHANGE')"
            @click="selectedTxId = null"
          />
        </section>

        <!-- Forma de pagamento — dropdown moderno com PaymentMethodBadge.
             Refactor 2026-05-24: lista REAL configurada em Settings (não mais
             hardcoded). Mesma UX do ReceivePaymentModalV2 global.
             Quando crédito cobre 100% do valor, o seletor é desabilitado
             e exibido um aviso — o método efetivo será "credito_paciente". -->
        <section class="pay-modal__section">
          <label class="pay-modal__label">
            Forma de pagamento
            <span class="pay-modal__required">*</span>
          </label>
          <div
            v-if="creditCoversAll"
            class="pay-modal__credit-only"
          >
            <i class="i-lucide-wallet w-3.5 h-3.5" />
            <span>Pagamento integral via <strong>crédito do paciente</strong> — método selecionado abaixo será ignorado.</span>
          </div>

          <div v-if="paymentMethodsLoading" class="pay-modal__pm-loading">
            <i class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin" />
            <span>Carregando formas de pagamento…</span>
          </div>
          <div v-else-if="paymentMethods.length === 0" class="pay-modal__credit-only">
            <i class="i-lucide-info w-3.5 h-3.5" />
            <span>Nenhuma forma de pagamento configurada. Vá em Settings → Formas de Pagamento.</span>
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
              <span v-if="option.hint" class="pay-modal__pm-provider-hint">
                <i class="i-lucide-building-2 w-3 h-3" />
                {{ option.hint }}
              </span>
            </template>
          </FormSelect>
        </section>

        <!-- Valor recebido (canon BUG-01: baixa parcial em Dinheiro/PIX/Boleto).
             Opcional — vazio paga o saldo restante completo. Preenchido com valor
             menor: parcela vira parcial e checkbox "gerar nova" aparece abaixo. -->
        <section v-if="selectedTransaction" class="pay-modal__section">
          <label class="pay-modal__label">
            Valor recebido (R$)
            <small class="pay-modal__hint-inline">opcional — saldo: {{ formatCurrency(remainingCents / 100) }}</small>
          </label>
          <input
            v-model="payForm.received_amount_raw"
            type="text"
            inputmode="decimal"
            :placeholder="formatCurrency(remainingCents / 100)"
            class="pay-modal__input"
          />
          <p v-if="partialAmountHint" class="pay-modal__hint">{{ partialAmountHint }}</p>

          <!-- Toggle "gerar nova parcela com saldo restante" — aparece
               contextual ao valor digitado: só quando o método aceita
               parcial (dinheiro/pix/boleto) E o valor digitado é MENOR
               que o saldo. Pagando o total ou sem digitar → oculto. -->
          <div
            v-if="partialAllowed && isPartialPayment"
            class="pay-modal__check-inline"
          >
            <Checkbox
              v-model="keepInstallmentOpen"
              label="Em baixa parcial, gerar nova parcela com o saldo restante"
            />
          </div>
        </section>

        <!-- Crédito do paciente — full width, posicionado logo após Valor
             recebido pra ser visualmente próximo da decisão de "quanto pagar".
             Quando NÃO há crédito: campo não aparece.
             Quando há e ainda não foi aplicado: botão "Usar crédito (R$ X)".
             Quando aplicado: pílula verde + botão "Remover" pra desfazer. -->
        <section v-if="selectedTransaction && patientCreditBalance > 0" class="pay-modal__section">
          <label class="pay-modal__label">Crédito do paciente</label>
          <button
            v-if="!applyCreditEnabled"
            type="button"
            class="pay-modal__credit-btn"
            @click="applyCreditEnabled = true"
          >
            <i class="i-lucide-wallet w-3.5 h-3.5" />
            <span>Usar crédito disponível</span>
            <strong>{{ centsToBRL(patientCreditBalance) }}</strong>
          </button>
          <div v-else class="pay-modal__credit-applied">
            <div class="pay-modal__credit-applied-info">
              <i class="i-lucide-check-circle-2 w-3.5 h-3.5" />
              <span>Crédito aplicado:</span>
              <strong>{{ centsToBRL(applyCreditCents) }}</strong>
            </div>
            <button
              type="button"
              class="pay-modal__credit-remove"
              @click="applyCreditEnabled = false"
            >
              Remover
            </button>
          </div>
        </section>

        <!-- Conta destino + Data do recebimento em 2 colunas — mesmo layout
             do ReceivePaymentModalV2 (A Receber global) pra UX consistente.
             Info-card quando forma tem default_bank_account_id; FormSelect
             quando sem default OU operador clica "Alterar". -->
        <section class="pay-modal__section pay-modal__grid-2">
          <div v-if="bankAccounts.length">
            <label class="pay-modal__label">
              Conta destino
              <span class="pay-modal__required">*</span>
            </label>
            <div
              v-if="showBankAccountInfo && selectedBankAccount"
              class="pay-modal__bank-info"
            >
              <i class="i-lucide-landmark w-3.5 h-3.5" />
              <span class="pay-modal__bank-info-name">{{ selectedBankAccount.name }}</span>
              <span class="pay-modal__bank-info-tag">da forma</span>
              <button
                type="button"
                class="pay-modal__bank-info-edit"
                @click="overrideBankAccount = true"
              >
                <i class="i-lucide-pencil w-3 h-3" />
                Alterar
              </button>
            </div>
            <FormSelect
              v-else
              v-model="payForm.bank_account_id"
              :options="bankAccountOptions"
              placeholder="Selecione a conta"
              auto-searchable
            />
          </div>
          <div>
            <label class="pay-modal__label">
              Data do recebimento
              <span class="pay-modal__required">*</span>
            </label>
            <DatePickerBR
              v-model="payForm.paid_at"
              :placeholder="t('PATIENT_FINANCIAL.MODALS.PAY.DATE_PLACEHOLDER')"
            />
          </div>
        </section>

        <!-- Campos avançados — paridade com modal de A Receber global.
             Todos opcionais. Backend (`installments/:id/pay`) aceita tipo+value
             (intenção) + cents legacy. Toggle R$/% por campo (padrão mercado). -->
        <section v-if="selectedTransaction" class="pay-modal__section pay-modal__grid-2">
          <div>
            <label class="pay-modal__label">
              Juros
              <span class="pay-modal__mode-toggle">
                <button type="button" class="pay-modal__mode-btn" :class="{ 'pay-modal__mode-btn--active': interestMode === MODE_BRL }" @click="setInterestMode(MODE_BRL)">R$</button>
                <button type="button" class="pay-modal__mode-btn" :class="{ 'pay-modal__mode-btn--active': interestMode === MODE_PCT }" @click="setInterestMode(MODE_PCT)">%</button>
              </span>
            </label>
            <input
              :value="interestStr"
              type="text"
              inputmode="decimal"
              :placeholder="interestMode === MODE_PCT ? '0,00 %' : 'R$ 0,00'"
              class="pay-modal__input"
              @input="onInterestInput"
            />
            <p v-if="interestMode === MODE_PCT && interestCents > 0" class="pay-modal__mode-hint">
              = {{ centsToBRL(interestCents) }}
            </p>
          </div>
          <div>
            <label class="pay-modal__label">
              Multa
              <span class="pay-modal__mode-toggle">
                <button type="button" class="pay-modal__mode-btn" :class="{ 'pay-modal__mode-btn--active': fineMode === MODE_BRL }" @click="setFineMode(MODE_BRL)">R$</button>
                <button type="button" class="pay-modal__mode-btn" :class="{ 'pay-modal__mode-btn--active': fineMode === MODE_PCT }" @click="setFineMode(MODE_PCT)">%</button>
              </span>
            </label>
            <input
              :value="fineStr"
              type="text"
              inputmode="decimal"
              :placeholder="fineMode === MODE_PCT ? '0,00 %' : 'R$ 0,00'"
              class="pay-modal__input"
              @input="onFineInput"
            />
            <p v-if="fineMode === MODE_PCT && fineCents > 0" class="pay-modal__mode-hint">
              = {{ centsToBRL(fineCents) }}
            </p>
          </div>
        </section>

        <!-- Desconto sozinho na linha — quando crédito ocupa linha cheia
             acima, manter desconto também em row própria fica mais legível
             que apertar 2 inputs lado a lado sem necessidade. -->
        <section v-if="selectedTransaction" class="pay-modal__section">
          <label class="pay-modal__label">
            Desconto
            <span class="pay-modal__mode-toggle">
              <button type="button" class="pay-modal__mode-btn" :class="{ 'pay-modal__mode-btn--active': discountMode === MODE_BRL }" @click="setDiscountMode(MODE_BRL)">R$</button>
              <button type="button" class="pay-modal__mode-btn" :class="{ 'pay-modal__mode-btn--active': discountMode === MODE_PCT }" @click="setDiscountMode(MODE_PCT)">%</button>
            </span>
          </label>
          <input
            :value="discountStr"
            type="text"
            inputmode="decimal"
            :placeholder="discountMode === MODE_PCT ? '0,00 %' : 'R$ 0,00'"
            class="pay-modal__input"
            @input="onDiscountInput"
          />
          <p v-if="discountMode === MODE_PCT && discountCents > 0" class="pay-modal__mode-hint">
            = {{ centsToBRL(discountCents) }}
          </p>
        </section>

        <section v-if="selectedTransaction" class="pay-modal__section">
          <label class="pay-modal__label">Observações</label>
          <textarea
            v-model="notes"
            rows="2"
            placeholder="Notas internas (opcional)"
            class="pay-modal__input pay-modal__textarea"
          />
        </section>

        <!-- Resumo (espelha o modal de A Receber): linhas detalhadas com
             ajustes (+ juros, + multa, − desconto, − crédito) e total final. -->
        <section v-if="selectedTransaction" class="pay-modal__summary">
          <div class="pay-modal__summary-row">
            <span>Valor bruto</span>
            <strong>{{ centsToBRL(grossCents) }}</strong>
          </div>
          <div v-if="interestCents > 0" class="pay-modal__summary-row">
            <span>+ Juros</span>
            <strong>{{ centsToBRL(interestCents) }}</strong>
          </div>
          <div v-if="fineCents > 0" class="pay-modal__summary-row">
            <span>+ Multa</span>
            <strong>{{ centsToBRL(fineCents) }}</strong>
          </div>
          <div v-if="discountCents > 0" class="pay-modal__summary-row pay-modal__summary-row--negative">
            <span>− Desconto</span>
            <strong>{{ centsToBRL(discountCents) }}</strong>
          </div>
          <div v-if="applyCreditCents > 0" class="pay-modal__summary-row pay-modal__summary-row--negative">
            <span>− Crédito aplicado</span>
            <strong>{{ centsToBRL(applyCreditCents) }}</strong>
          </div>
          <div class="pay-modal__summary-row pay-modal__summary-row--total">
            <span>Total a creditar na conta</span>
            <strong>{{ centsToBRL(netCents) }}</strong>
          </div>

          <p v-if="willCreateRemainder" class="pay-modal__summary-info">
            <i class="i-lucide-info w-3.5 h-3.5" />
            Saldo restante gerará nova parcela em "A Receber".
          </p>
        </section>
      </div>

      <footer class="pay-modal__footer">
        <BeclinicButton
          variant="ghost"
          color="slate"
          :label="t('PATIENT_FINANCIAL.MODALS.PAY.CANCEL')"
          @click="emit('close')"
        />
        <BeclinicButton
          variant="solid"
          color="teal"
          icon="i-lucide-check"
          label="Confirmar recebimento"
          :is-loading="loading"
          :disabled="!canSubmit"
          @click="handleConfirm"
        />
      </footer>
    </div>
  </div>
</template>

<style scoped lang="scss">
.pay-modal__input {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid rgb(var(--slate-300));
  border-radius: 8px;
  font-size: 14px;
  color: rgb(var(--slate-700));
  background: white;
  &:focus { outline: none; border-color: rgb(var(--teal-9)); box-shadow: 0 0 0 3px rgb(var(--teal-9) / 0.15); }
}
.pay-modal__hint-inline {
  margin-left: 8px;
  font-size: 11px;
  font-weight: 400;
  color: rgb(var(--slate-500));
}

// Botão "Usar crédito disponível" — único toque pra aplicar todo o crédito.
// Visual teal (tom verde do design system) porque é ação positiva. Os tokens
// `--emerald-*` NÃO existem (vide [[project-emerald-token-inexistente]]); a
// versão anterior rendia border preto e fundo transparente. `--teal-N` é a
// escala Radix 1-12 que auto-adapta light/dark (decisão 2026-05-28).
.pay-modal__credit-btn {
  display: flex;
  align-items: center;
  gap: 6px;
  width: 100%;
  padding: 10px 12px;
  background: rgb(var(--teal-3));
  color: rgb(var(--teal-11));
  border: 1px dashed rgb(var(--teal-7));
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  font-family: inherit;
  transition: background 0.12s, border-color 0.12s;
  strong {
    margin-left: auto;
    font-variant-numeric: tabular-nums;
    font-weight: 700;
    color: rgb(var(--teal-12));
  }
  &:hover {
    background: rgb(var(--teal-4));
    border-color: rgb(var(--teal-9));
    border-style: solid;
  }
}

// Estado "crédito aplicado" — confirmação visual + ação rápida pra desfazer.
.pay-modal__credit-applied {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  background: rgb(var(--teal-4));
  color: rgb(var(--teal-12));
  border: 1px solid rgb(var(--teal-9));
  border-radius: 8px;
  font-size: 13px;
}
.pay-modal__credit-applied-info {
  display: flex;
  align-items: center;
  gap: 6px;
  flex: 1;
  strong {
    font-variant-numeric: tabular-nums;
    font-weight: 700;
  }
}
.pay-modal__credit-remove {
  padding: 2px 8px;
  background: transparent;
  color: rgb(var(--teal-11));
  border: none;
  font-size: 12px;
  font-weight: 600;
  cursor: pointer;
  text-decoration: underline;
  text-underline-offset: 2px;
  &:hover {
    color: rgb(var(--ruby-11));
    text-decoration-color: rgb(var(--ruby-9));
  }
}

// Aviso "Pagamento integral via crédito do paciente" — aparece quando o
// crédito cobre 100% do valor devido. Sinaliza que o método de pagamento
// abaixo será ignorado (substituído por `credito_paciente` no backend).
.pay-modal__credit-only {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  margin-bottom: 8px;
  background: rgb(var(--teal-3));
  color: rgb(var(--teal-12));
  border: 1px solid rgb(var(--teal-7));
  border-radius: 8px;
  font-size: 12px;
  line-height: 1.4;
  strong {
    font-weight: 700;
  }
}

// `.pay-modal__chips--disabled` removido 2026-05-24 — dropdown nativo do
// FormSelect cuida do disabled state via prop `:disabled`.
.pay-modal__hint {
  margin-top: 6px;
  padding: 8px 10px;
  border-radius: 6px;
  background: rgb(var(--amber-50));
  border-left: 3px solid rgb(var(--amber-400));
  font-size: 12px;
  color: rgb(var(--amber-800));
  line-height: 1.4;
}

// Grid 2 colunas para pares de inputs (Juros/Multa, Desconto/Crédito).
// Em telas pequenas (< 480px) empilha em coluna única.
.pay-modal__grid-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  @media (max-width: 480px) {
    grid-template-columns: 1fr;
  }
}

.pay-modal__textarea {
  resize: vertical;
  min-height: 60px;
  font-family: inherit;
  line-height: 1.4;
}

// Checkbox contextual — aparece logo abaixo do input "Valor recebido"
// quando há baixa parcial. Margem superior pequena pra criar afinidade
// visual com o input acima (sinaliza relacionamento).
.pay-modal__check-inline {
  margin-top: 8px;
  padding: 8px 10px;
  background: rgb(var(--slate-50));
  border: 1px solid rgb(var(--slate-200));
  border-radius: 6px;
}

// Resumo "Valor bruto / + ajustes / − descontos / Total a creditar".
// Espelha o `.rpm-v2__summary` do ReceivePaymentModalV2 (A Receber global)
// pra UX consistente entre as 2 telas que recebem pagamento.
.pay-modal__summary {
  margin-top: 4px;
  padding: 14px 16px;
  border-radius: 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.pay-modal__summary-row {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 13px;
  color: rgb(var(--slate-11));
  strong {
    font-variant-numeric: tabular-nums;
    font-weight: 600;
    color: rgb(var(--slate-12));
  }
  &--negative strong {
    color: #b91c1c;
  }
  &--total {
    border-top: 1px solid rgb(var(--slate-4));
    padding-top: 10px;
    margin-top: 4px;
    font-weight: 600;
    color: rgb(var(--slate-12));
    strong {
      color: #047857;
      font-size: 15px;
    }
  }
}
:root.dark .pay-modal__summary-row--negative strong { color: #fca5a5; }
:root.dark .pay-modal__summary-row--total strong { color: #6ee7b7; }

.pay-modal__summary-info {
  margin: 6px 0 0;
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  color: rgb(var(--slate-11));
  strong { font-weight: 600; }
}

/* ── Refactor 2026-05-24 — estilos novos ───────────────────────── */
/* Loading do dropdown de formas de pagamento */
.pay-modal__pm-loading {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 12px; color: rgb(var(--slate-9));
  padding: 8px 0;
}
/* Hint do provedor (à direita do option no dropdown) */
.pay-modal__pm-provider-hint {
  margin-left: auto;
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11px; color: rgb(var(--slate-9));
  font-weight: 500; white-space: nowrap;
  i { opacity: 0.7; }
}

/* Info-card da conta destino (quando forma tem default_bank_account_id) */
.pay-modal__bank-info {
  display: flex; align-items: center; gap: 8px;
  padding: 0 12px;
  min-height: 40px;
  box-sizing: border-box;
  background: rgb(var(--blue-2));
  border: 1px solid rgb(var(--blue-5));
  border-radius: 8px;
  font-size: 13px; color: rgb(var(--slate-12));
  width: 100%; min-width: 0;
  i { color: rgb(var(--blue-10)); flex-shrink: 0; }
}
.pay-modal__bank-info-name {
  font-weight: 500;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
  min-width: 0;
}
.pay-modal__bank-info-tag {
  font-size: 10.5px; font-weight: 500;
  padding: 1px 6px; border-radius: 999px;
  background: rgb(var(--blue-4)); color: rgb(var(--blue-11));
  text-transform: lowercase; letter-spacing: 0.01em;
  white-space: nowrap;
}
.pay-modal__bank-info-edit {
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
.pay-modal__mode-toggle {
  margin-left: auto;
  display: inline-flex; align-items: center;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 999px;
  padding: 1px;
  overflow: hidden;
  vertical-align: middle;
}
.pay-modal__mode-btn {
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
  &:hover:not(.pay-modal__mode-btn--active) { color: rgb(var(--slate-12)); }
  &--active { background: rgb(var(--blue-9)); color: #ffffff; }
}
.pay-modal__mode-hint {
  margin: 4px 0 0;
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
  font-style: italic;
}

/* Label do field precisa de inline-flex pro toggle ficar à direita */
.pay-modal__label {
  display: inline-flex !important;
  align-items: center;
  gap: 6px;
  width: 100%;
}
</style>
