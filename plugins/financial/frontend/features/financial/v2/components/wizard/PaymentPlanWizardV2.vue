<script setup>
/**
 * PaymentPlanWizardV2 — wizard de 5 steps para configurar e aprovar
 * orçamento financeiro com split heterogêneo (entrada + parcelas com
 * formas/valores/datas diferentes).
 *
 * Substitui o botão "Aprovar orçamento" simples do card "Precisa aprovação".
 * Consome:
 *   - POST /budgets/:id/simulate_plan (read-only, no step 4 e 5)
 *   - POST /budgets/:id/approve (canon, no step 5)
 *
 * F2 do plano em docs/03-engineering/financeiro-fluxo-aprovacao-parcelamento.md.
 * Vive isolado em rota oculta de preview ate F3 plugar nos entry points reais
 * atrás de feature flag `payment_plan_wizard_v2`.
 *
 * Decisão UX (memory `modal_no_backdrop_close`): NÃO fecha por click no
 * backdrop — só pelos botões. Evita perda de configuração em wizard longo.
 */
import { ref, computed, watch, onMounted } from 'vue';
import FinancialV2 from '../../api/financialV2';
import { centsToBRL, centsToInputString, brlInputToCents, splitCents } from '../../composables/useMoney';
import PaymentSplitBuilder from './PaymentSplitBuilder.vue';
import NetAmountCard from './NetAmountCard.vue';
import FeeSimulationCard from './FeeSimulationCard.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
// Avatar shared do Chatwoot — mesmo componente usado na listagem de pacientes
// (/app/accounts/:id/patients). Renderiza imagem se `src` presente, ou
// iniciais coloridas baseado em `name`. Garante consistência visual.
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  // Budget completo (com items[]) — vem do componente pai
  budget: { type: Object, default: null },
});
const emit = defineEmits(['close', 'approved']);

// ─── Estado central ──────────────────────────────────────────────────────
const currentStep = ref(1);
const STEPS = [
  { n: 1, label: 'Resumo' },
  { n: 2, label: 'Desconto' },
  { n: 3, label: 'Modo' },
  { n: 4, label: 'Parcelas' },
  { n: 5, label: 'Confirmar' },
];

// UUID v4 — usado como Idempotency-Key no submit + tag em payment_plan.wizard_session_id
const wizardSessionId = ref(uuidv4());

// Desconto (Step 2)
const discountKind = ref('none'); // 'none' | 'percentual' | 'fixo'
const discountValue = ref('');

// Modo (Step 3)
const planMode = ref('uniform'); // 'uniform' | 'entry_plus' | 'custom'

// Uniform/EntryPlus inputs
const uniformCount = ref(1);
const uniformPaymentMethodId = ref(null);
const uniformFirstDueDate = ref(today());
const uniformIntervalDays = ref(30);

const entryAmountStr = ref('');
const entryPaymentMethodId = ref(null);
const entryDueDate = ref(today());
const remainingCount = ref(2);
const remainingPaymentMethodId = ref(null);
const remainingFirstDueDate = ref(addDays(30));
const remainingIntervalDays = ref(30);

// Custom rows — populadas dinamicamente
const customRows = ref([]);

// Simulação backend
const simulationData = ref(null); // { plan: [...], totals: {...} }
const simulating = ref(false);
const simulateError = ref('');

// FeeSimulationCard standalone (chip de simulação ad-hoc no Step 4)
const adhocPmId = ref(null);
const adhocAmountStr = ref('');
const adhocInstallments = ref(1);
const adhocResult = ref(null);
const adhocLoading = ref(false);
let adhocTimer = null;

// Payment methods da conta
const paymentMethods = ref([]);
const paymentMethodsLoading = ref(false);

// Submit
const submitting = ref(false);
const submitError = ref('');

// ─── Helpers ─────────────────────────────────────────────────────────────
function uuidv4() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID();
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });
}

function today() {
  return new Date().toISOString().slice(0, 10);
}
function addDays(days) {
  const d = new Date(); d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

// Formata 'YYYY-MM-DD' (ISO) em 'DD/MM/YYYY' (pt-BR) sem timezone surprise.
// Parse manual evita o new Date(iso) que pode resultar em D-1 conforme TZ.
function formatDateBR(isoDate) {
  if (!isoDate) return '—';
  const s = String(isoDate).slice(0, 10);
  const parts = s.split('-');
  if (parts.length !== 3) return s;
  const [y, m, d] = parts;
  return `${d}/${m}/${y}`;
}

// Avatares agora usam o componente shared <Avatar> do Chatwoot (mesmo
// padrão visual da listagem de pacientes). Helpers locais de iniciais /
// cor foram removidos — o componente cuida disso sozinho via prop `name`.

const paymentMethodOptions = computed(() =>
  [...paymentMethods.value]
    .sort((a, b) => {
      const pa = (a.provider || '').trim();
      const pb = (b.provider || '').trim();
      if (!pa && pb) return -1;
      if (pa && !pb) return 1;
      if (pa !== pb) return pa.localeCompare(pb, 'pt-BR');
      return (a.name || '').localeCompare(b.name || '', 'pt-BR');
    })
    .map(m => ({
      value: m.id,
      label: m.name,
      hint: (m.provider_alias || m.provider || '').trim() || null,
      raw: m,
    }))
);

const findPaymentMethod = id => paymentMethods.value.find(m => m.id === id) || null;

// Helpers do Step 5 — lookup por índice na lista EXPANDIDA. Quando a simulação
// ainda não chegou (ou falhou), cai pro amount cru da expansão pra não quebrar
// o render. `isTenderHead` marca a primeira parcela de uma série Nx pra a UI
// poder dar um separador visual sutil entre séries.
function amountForPatientAt(idx) {
  const sim = simulationData.value?.plan?.[idx];
  return sim?.amount_cents ?? expandedPlan.value[idx]?.amount_cents ?? 0;
}
function netAt(idx) {
  const sim = simulationData.value?.plan?.[idx];
  return sim?.net_amount_cents ?? expandedPlan.value[idx]?.amount_cents ?? 0;
}
function isTenderHead(idx) {
  const entry = expandedPlanMap.value[idx];
  return !!entry && entry.seq === 1 && entry.seq_total > 1 && idx > 0;
}

// ─── Cálculos derivados ──────────────────────────────────────────────────
const subtotalCents = computed(() => props.budget?.subtotal_cents || props.budget?.total_cents || 0);

const discountCents = computed(() => {
  if (discountKind.value === 'none' || !discountValue.value) return 0;
  if (discountKind.value === 'percentual') {
    const pct = Number.parseFloat(String(discountValue.value).replace(',', '.')) || 0;
    return Math.round((subtotalCents.value * pct) / 100);
  }
  return brlInputToCents(discountValue.value);
});

const totalCents = computed(() => Math.max(0, subtotalCents.value - discountCents.value));

// ─── Plan builder por modo ───────────────────────────────────────────────
const installmentsPlan = computed(() => {
  if (planMode.value === 'uniform') {
    return buildUniformPlan();
  }
  if (planMode.value === 'entry_plus') {
    return buildEntryPlusPlan();
  }
  return customRows.value.map(r => ({
    amount_cents: r.amount_cents || 0,
    due_date: r.due_date,
    payment_method: kindFromId(r.payment_method_id),
    payment_method_id: r.payment_method_id,
    // Parcelamento da perna na maquininha (multi-cartão). Null fora de crédito.
    card_installments: r.card_installments || null,
  }));
});

// Helper: deriva `kind` (string canon: dinheiro|pix|credito|...) do id.
// ApproveBudget#generate_installments precisa AMBOS na row — sem o `kind`
// cai no default global do budget (geralmente 'pix'), perdendo o split.
function kindFromId(id) {
  return findPaymentMethod(id)?.kind || null;
}

function buildUniformPlan() {
  const n = Math.max(1, uniformCount.value || 1);
  const pieces = splitCents(totalCents.value, n);
  const kind = kindFromId(uniformPaymentMethodId.value);
  return pieces.map((amount_cents, idx) => ({
    amount_cents,
    due_date: addDaysFrom(uniformFirstDueDate.value, idx * (uniformIntervalDays.value || 0)),
    payment_method: kind,
    payment_method_id: uniformPaymentMethodId.value,
  }));
}

function buildEntryPlusPlan() {
  const entryCents = brlInputToCents(entryAmountStr.value);
  const restCents = Math.max(0, totalCents.value - entryCents);
  const n = Math.max(1, remainingCount.value || 1);
  const pieces = splitCents(restCents, n);
  const entryKind = kindFromId(entryPaymentMethodId.value);
  const remainingKind = kindFromId(remainingPaymentMethodId.value);
  const plan = [
    {
      amount_cents: entryCents,
      due_date: entryDueDate.value,
      payment_method: entryKind,
      payment_method_id: entryPaymentMethodId.value,
    },
  ];
  pieces.forEach((amount_cents, idx) => {
    plan.push({
      amount_cents,
      due_date: addDaysFrom(remainingFirstDueDate.value, idx * (remainingIntervalDays.value || 0)),
      payment_method: remainingKind,
      payment_method_id: remainingPaymentMethodId.value,
    });
  });
  return plan;
}

function addDaysFrom(isoDate, days) {
  const d = new Date(isoDate);
  d.setDate(d.getDate() + (days || 0));
  return d.toISOString().slice(0, 10);
}

// Expansão de perna multi-cartão: cada perna de CRÉDITO com card_installments=N
// vira N cobranças mensais (matchando o que a maquininha vai cobrar do paciente).
// Pernas que não são crédito ou são 1x passam direto. Mantemos um `map` paralelo
// indicando de qual perna cada cobrança expandida veio, pra agregar a simulação
// de volta no nível da perna (que é o que o PaymentSplitBuilder mostra).
const expandedPlanWithMap = computed(() => {
  const out = [];
  const map = [];
  installmentsPlan.value.forEach((perna, pidx) => {
    const n = Number(perna.card_installments) || 1;
    if (perna.payment_method === 'credito' && n > 1) {
      const pieces = splitCents(perna.amount_cents || 0, n);
      pieces.forEach((amount_cents, k) => {
        out.push({
          ...perna,
          amount_cents,
          due_date: addDaysFrom(perna.due_date, k * 30),
        });
        map.push({ perna_idx: pidx, seq: k + 1, seq_total: n });
      });
    } else {
      out.push({ ...perna });
      map.push({ perna_idx: pidx, seq: 1, seq_total: 1 });
    }
  });
  return { plan: out, map };
});
const expandedPlan = computed(() => expandedPlanWithMap.value.plan);
const expandedPlanMap = computed(() => expandedPlanWithMap.value.map);

// Agrega a simulação backend (que vem por cobrança expandida) de volta no nível
// da perna — pro PaymentSplitBuilder mostrar Taxa/Cliente paga/Clínica recebe
// total da perna, mesmo quando ela vira várias cobranças.
const pernaAggregates = computed(() => {
  const sim = simulationData.value?.plan;
  if (!sim) return [];
  const aggs = installmentsPlan.value.map(() => ({
    amount_cents: 0,
    fee_amount_cents: 0,
    net_amount_cents: 0,
    passes_fee_to_patient: false,
    fee_resolved: true,
  }));
  expandedPlanMap.value.forEach((entry, idx) => {
    const row = sim[idx];
    const agg = aggs[entry.perna_idx];
    if (!row || !agg) return;
    agg.amount_cents += row.amount_cents || 0;
    agg.fee_amount_cents += row.fee_amount_cents || 0;
    agg.net_amount_cents += row.net_amount_cents || 0;
    if (row.passes_fee_to_patient) agg.passes_fee_to_patient = true;
    if (row.fee_resolved === false) agg.fee_resolved = false;
  });
  return aggs;
});

// Sincroniza customRows quando entra no Step 4 com modo "custom" — popula
// com snapshot do plano atual (uniform ou entry_plus) pra operador editar.
watch(() => [planMode.value, currentStep.value], ([mode, step]) => {
  if (mode === 'custom' && step === 4 && customRows.value.length === 0) {
    const base = planMode.value === 'custom'
      ? buildUniformPlan() // primeira entrada — usa uniform como base
      : installmentsPlan.value;
    customRows.value = base.map(r => ({
      amount_str: centsToInputString(r.amount_cents),
      amount_cents: r.amount_cents,
      due_date: r.due_date,
      payment_method_id: r.payment_method_id,
      card_installments: r.card_installments || null,
    }));
  }
});

// ─── Load payment methods ────────────────────────────────────────────────
async function loadPaymentMethods() {
  paymentMethodsLoading.value = true;
  try {
    const { data } = await FinancialV2.paymentMethods.index({ status: 'active' });
    paymentMethods.value = (data?.data || []).filter(m => m.status === 'active');
    // Default: primeira forma ativa
    if (!uniformPaymentMethodId.value && paymentMethods.value[0]) {
      uniformPaymentMethodId.value = paymentMethods.value[0].id;
      entryPaymentMethodId.value = paymentMethods.value[0].id;
      remainingPaymentMethodId.value = paymentMethods.value[0].id;
      adhocPmId.value = paymentMethods.value[0].id;
    }
  } catch (e) {
    paymentMethods.value = [];
  } finally {
    paymentMethodsLoading.value = false;
  }
}

// ─── Simulação do plano (debounced quando entra no Step 4/5) ─────────────
let simulateTimer = null;
function scheduleSimulate() {
  clearTimeout(simulateTimer);
  simulateTimer = setTimeout(runSimulate, 350);
}

async function runSimulate() {
  if (!props.budget?.id) return;
  if (expandedPlan.value.length === 0) return;

  simulating.value = true;
  simulateError.value = '';
  try {
    // Simula a lista EXPANDIDA (1 cobrança = 1 row), pra MDR de cada parcela
    // do cartão bater 1:1 com o snapshot que vai ser congelado no ReceivePayment.
    const { data } = await FinancialV2.budgets.simulatePlan(props.budget.id, expandedPlan.value);
    simulationData.value = data?.data || null;
  } catch (e) {
    simulationData.value = null;
    simulateError.value = e?.response?.data?.errors?.[0] || e.message || 'Falha ao simular plano';
  } finally {
    simulating.value = false;
  }
}

watch([installmentsPlan, currentStep], ([_plan, step]) => {
  if (step === 4 || step === 5) scheduleSimulate();
});

// ─── Simulação ad-hoc de fee (Step 4) ────────────────────────────────────
async function runAdhoc() {
  if (!adhocPmId.value || !adhocAmountStr.value) {
    adhocResult.value = null;
    return;
  }
  adhocLoading.value = true;
  try {
    const { data } = await FinancialV2.paymentMethods.simulateFee(adhocPmId.value, {
      amount_cents: brlInputToCents(adhocAmountStr.value),
      installments_count: adhocInstallments.value || 1,
      on_date: today(),
    });
    adhocResult.value = data?.data || null;
  } catch {
    adhocResult.value = null;
  } finally {
    adhocLoading.value = false;
  }
}
watch([adhocPmId, adhocAmountStr, adhocInstallments], () => {
  clearTimeout(adhocTimer);
  adhocTimer = setTimeout(runAdhoc, 300);
});

// ─── Submit ──────────────────────────────────────────────────────────────
// O `amount_cents` no installments_plan é interpretado pelo backend como BASE
// (= o que clínica deve receber). Logo a soma das bases é o que precisa bater
// com o total do orçamento — não a soma dos amount_cents inflados (que seria
// o que o cliente paga, sempre >= total).
const canSubmit = computed(() => {
  if (!props.budget?.id) return false;
  if (installmentsPlan.value.length === 0) return false;
  const sumBase = installmentsPlan.value.reduce((acc, r) => acc + (r.amount_cents || 0), 0);
  if (sumBase !== totalCents.value) return false;
  if (installmentsPlan.value.some(r => !r.payment_method_id || !r.amount_cents || !r.due_date)) return false;
  return true;
});

// Avançar do Step 4 (Parcelas) só quando soma das parcelas = total do orçamento
// e cada linha completa (valor, vencimento, forma). Steps 1-3 e 5 não têm
// restrição extra aqui (Step 5 tem seu botão Confirmar próprio com canSubmit).
const canAdvance = computed(() => {
  if (currentStep.value !== 4) return true;
  if (installmentsPlan.value.length === 0) return false;
  const sumBase = installmentsPlan.value.reduce((acc, r) => acc + (r.amount_cents || 0), 0);
  if (sumBase !== totalCents.value) return false;
  if (installmentsPlan.value.some(r => !r.payment_method_id || !r.amount_cents || !r.due_date)) return false;
  return true;
});

const advanceBlockReason = computed(() => {
  if (currentStep.value !== 4) return '';
  if (installmentsPlan.value.length === 0) return 'Adicione ao menos 1 parcela.';
  const sumBase = installmentsPlan.value.reduce((acc, r) => acc + (r.amount_cents || 0), 0);
  if (sumBase < totalCents.value) {
    return `Faltam ${centsToBRL(totalCents.value - sumBase)} para fechar o total do orçamento.`;
  }
  if (sumBase > totalCents.value) {
    return `Parcelas excedem o total em ${centsToBRL(sumBase - totalCents.value)}.`;
  }
  if (installmentsPlan.value.some(r => !r.payment_method_id)) return 'Selecione a forma de pagamento de todas as parcelas.';
  if (installmentsPlan.value.some(r => !r.amount_cents)) return 'Defina o valor de todas as parcelas.';
  if (installmentsPlan.value.some(r => !r.due_date)) return 'Defina o vencimento de todas as parcelas.';
  return '';
});

// Marca pernas pagas no MESMO momento (mesma data de vencimento) com um
// tender_group compartilhado — "este pagamento foi dividido em N cartões".
// Só agrupa quando há 2+ pernas na mesma data; parcela avulsa fica sem grupo.
function withTenderGroups(plan) {
  const counts = {};
  plan.forEach(r => { const k = r.due_date || ''; counts[k] = (counts[k] || 0) + 1; });
  const groups = {};
  return plan.map(r => {
    const k = r.due_date || '';
    if (counts[k] < 2) return { ...r, tender_group: null };
    if (!groups[k]) groups[k] = uuidv4();
    return { ...r, tender_group: groups[k] };
  });
}

async function submit() {
  if (!canSubmit.value) return;
  submitting.value = true;
  submitError.value = '';

  // Manda a lista EXPANDIDA pra approve — cada perna multi-cartão (crédito Nx)
  // já vira N cobranças aqui no front, mesma lista que foi simulada.
  const planToSubmit = withTenderGroups(expandedPlan.value);

  // Payload da F2 + payment_plan snapshot (intenção original do wizard)
  const payment_plan = {
    version: 'v2',
    wizard_session_id: wizardSessionId.value,
    configured_at: new Date().toISOString(),
    discount: discountKind.value === 'none'
      ? null
      : { kind: discountKind.value, value: discountValue.value, cents: discountCents.value },
    mode: planMode.value,
    installments_plan: planToSubmit,
    totals: simulationData.value?.totals || null,
  };

  try {
    const { data } = await FinancialV2.budgets.approve(props.budget.id, {
      installments_plan: planToSubmit,
      // payment_plan ainda não é persistido em F2 — backend ignora keys
      // desconhecidas; persistência é F3+ no controller (lê params[:payment_plan]
      // e grava em Budget.payment_plan JSONB).
      payment_plan,
    });
    emit('approved', data?.data || data);
  } catch (e) {
    submitError.value = e?.response?.data?.errors?.[0] || e.message || 'Falha ao aprovar orçamento';
  } finally {
    submitting.value = false;
  }
}

// ─── Navegação entre steps ───────────────────────────────────────────────
function goNext() {
  if (currentStep.value < 5) currentStep.value += 1;
}
function goPrev() {
  if (currentStep.value > 1) currentStep.value -= 1;
}

function close() {
  // Memory `modal_no_backdrop_close` — só fecha por ação explícita
  emit('close');
}

// Progress do stepper (0..100%) — line atrás dos circles preenche
// proporcional ao step atual. step 1 = 0%, step 5 = 100%.
const connectorPct = computed(() =>
  Math.max(0, ((currentStep.value - 1) / (STEPS.length - 1)) * 100),
);

// ─── Lifecycle ───────────────────────────────────────────────────────────
onMounted(loadPaymentMethods);
watch(() => props.show, (visible) => {
  if (visible) {
    currentStep.value = 1;
    wizardSessionId.value = uuidv4();
    loadPaymentMethods();
  }
});
</script>

<template>
  <div v-if="show" class="wizard-overlay">
    <div class="wizard">
      <header class="wizard-header">
        <div class="header-left">
          <h2 class="title">
            <span class="title-badge">
              <i class="i-lucide-credit-card w-4 h-4" />
            </span>
            Configurar pagamento
          </h2>
          <div v-if="budget" class="subtitle">
            <span>Orçamento</span>
            <span class="chip">#{{ budget.id }}</span>
            <span class="dot">·</span>
            <span>Total:</span>
            <strong class="total">{{ centsToBRL(budget.total_cents) }}</strong>
          </div>
        </div>
        <button
          type="button"
          class="btn-close"
          :disabled="submitting"
          aria-label="Fechar"
          @click="close"
        >
          <i class="i-lucide-x w-4 h-4" />
        </button>
      </header>

      <!-- Stepper premium 2026-05-28: connector line atrás (preenche conforme
           o progresso), step circle 36×36 com gradient + ring no current. -->
      <nav class="stepper">
        <div class="step-connector">
          <div class="step-connector-fill" :style="{ width: connectorPct + '%' }" />
        </div>
        <button
          v-for="step in STEPS"
          :key="step.n"
          type="button"
          class="step"
          :class="{ current: currentStep === step.n, done: currentStep > step.n }"
          :disabled="step.n > currentStep"
          @click="currentStep = step.n"
        >
          <span class="step-circle">
            <i v-if="currentStep > step.n" class="i-lucide-check w-4 h-4" />
            <template v-else>{{ step.n }}</template>
          </span>
          <span class="step-label">{{ step.label }}</span>
        </button>
      </nav>

      <div class="wizard-body">
        <!-- ─────────────── Step 1: Resumo ─────────────── -->
        <section v-if="currentStep === 1" class="step-pane">
          <h3>Resumo do orçamento</h3>

          <!-- Cards de paciente + profissional usando o Avatar canon do
               Chatwoot — mesmo componente da listagem /app/accounts/:id/patients
               (iniciais coloridas determinísticas, suporte futuro a foto). -->
          <div v-if="budget" class="people-cards">
            <div class="person-card">
              <Avatar
                :src="budget.patient_avatar_url || ''"
                :name="budget.patient_name || 'Paciente'"
                :size="42"
                rounded-full
              />
              <div class="person-info">
                <span class="role">Paciente</span>
                <strong>{{ budget.patient_name || `#${budget.patient_id}` }}</strong>
              </div>
            </div>
            <div class="person-card">
              <Avatar
                :src="budget.professional_avatar_url || ''"
                :name="budget.professional_name || 'Profissional'"
                :size="42"
                rounded-full
              />
              <div class="person-info">
                <span class="role">Profissional</span>
                <strong>{{ budget.professional_name || (budget.professional_id ? `#${budget.professional_id}` : 'Não definido') }}</strong>
              </div>
            </div>
          </div>

          <!-- Tabela de itens — fonte primária do valor (não duplica em sumário) -->
          <table v-if="budget?.items?.length" class="items">
            <thead>
              <tr><th>Item</th><th>Qtd</th><th>Unit.</th><th>Subtotal</th></tr>
            </thead>
            <tbody>
              <tr v-for="item in budget.items" :key="item.id">
                <td>{{ item.description }}</td>
                <td>{{ item.quantity }}</td>
                <td>{{ centsToBRL(item.unit_price_cents) }}</td>
                <td>{{ centsToBRL(item.total_cents) }}</td>
              </tr>
              <tr class="items-total">
                <td colspan="3"><strong>Total</strong></td>
                <td><strong>{{ centsToBRL(budget.total_cents) }}</strong></td>
              </tr>
            </tbody>
          </table>

          <p class="hint">
            Os próximos passos configuram <strong>desconto</strong>, <strong>modo de parcelamento</strong>
            e <strong>parcelas heterogêneas</strong> (formas/datas distintas por parcela).
          </p>
        </section>

        <!-- ─────────────── Step 2: Desconto ─────────────── -->
        <section v-if="currentStep === 2" class="step-pane">
          <h3>Desconto (opcional)</h3>

          <!-- Cards full-width estilo Step 3 (Modo). Cada um clicável (label),
               radio escondido. Selected = border azul + bg azul claro + ícone. -->
          <div class="discount-cards">
            <label class="discount-card" :class="{ selected: discountKind === 'none' }">
              <input v-model="discountKind" type="radio" value="none" />
              <i class="i-lucide-ban w-5 h-5" />
              <div class="dc-text">
                <strong>Sem desconto</strong>
                <p>Cobrar o valor cheio do plano</p>
              </div>
            </label>

            <label class="discount-card" :class="{ selected: discountKind === 'percentual' }">
              <input v-model="discountKind" type="radio" value="percentual" />
              <i class="i-lucide-percent w-5 h-5" />
              <div class="dc-text">
                <strong>Percentual</strong>
                <p>Aplicar % sobre o total (ex: 10% off)</p>
              </div>
            </label>

            <label class="discount-card" :class="{ selected: discountKind === 'fixo' }">
              <input v-model="discountKind" type="radio" value="fixo" />
              <i class="i-lucide-tag w-5 h-5" />
              <div class="dc-text">
                <strong>Valor fixo</strong>
                <p>Subtrair valor em reais (ex: R$ 150 off)</p>
              </div>
            </label>
          </div>

          <!-- Campo de input só aparece quando há desconto selecionado -->
          <div v-if="discountKind !== 'none'" class="discount-input-row">
            <input
              v-model="discountValue"
              type="text"
              inputmode="decimal"
              :placeholder="discountKind === 'percentual' ? '5,00' : '50,00'"
              class="discount-input"
            />
            <span class="discount-input-suffix">{{ discountKind === 'percentual' ? '%' : 'R$' }}</span>
          </div>

          <!-- Sumário único (sem duplicação) — só mostra desconto se houver -->
          <div class="total-preview">
            <div class="row">
              <span>Subtotal do plano</span>
              <strong>{{ centsToBRL(subtotalCents) }}</strong>
            </div>
            <div v-if="discountCents > 0" class="row negative">
              <span>− Desconto aplicado</span>
              <strong>− {{ centsToBRL(discountCents) }}</strong>
            </div>
            <div class="row total">
              <span>Total a parcelar</span>
              <strong>{{ centsToBRL(totalCents) }}</strong>
            </div>
          </div>
        </section>

        <!-- ─────────────── Step 3: Modo ─────────────── -->
        <section v-if="currentStep === 3" class="step-pane">
          <h3>Modo de parcelamento</h3>
          <div class="mode-cards">
            <label class="mode-card" :class="{ selected: planMode === 'uniform' }">
              <input v-model="planMode" type="radio" value="uniform" />
              <i class="i-lucide-equal-square w-6 h-6" />
              <strong>Uniforme</strong>
              <p>N parcelas iguais com mesma forma e intervalo</p>
            </label>

            <label class="mode-card" :class="{ selected: planMode === 'entry_plus' }">
              <input v-model="planMode" type="radio" value="entry_plus" />
              <i class="i-lucide-arrow-down-up w-6 h-6" />
              <strong>Entrada + Restante</strong>
              <p>Entrada à vista (PIX/dinheiro) + parcelas do restante</p>
            </label>

            <label class="mode-card" :class="{ selected: planMode === 'custom' }">
              <input v-model="planMode" type="radio" value="custom" />
              <i class="i-lucide-list-tree w-6 h-6" />
              <strong>Customizado</strong>
              <p>Cada parcela com valor, data e forma próprios</p>
            </label>
          </div>
        </section>

        <!-- ─────────────── Step 4: Parcelas ─────────────── -->
        <section v-if="currentStep === 4" class="step-pane">
          <div class="section-title">
            <h3>
              <i class="i-lucide-calendar-days w-4 h-4" />
              Parcelas
              <span class="section-count">{{ installmentsPlan.length }}</span>
            </h3>
            <div class="section-helper">
              <i class="i-lucide-info w-3 h-3" />
              Configure os valores, formas e prazos de cada parcela
            </div>
          </div>

          <!-- Uniform -->
          <div v-if="planMode === 'uniform'" class="uniform-form">
            <div class="grid-4">
              <label>
                <span>Quantidade</span>
                <input v-model.number="uniformCount" type="number" min="1" max="60" />
              </label>
              <label>
                <span>Forma</span>
                <FormSelect
                  v-model="uniformPaymentMethodId"
                  :options="paymentMethodOptions"
                  placeholder="Selecione…"
                  auto-searchable
                >
                  <template #selected="{ option }">
                    <PaymentMethodBadge
                      v-if="option?.raw"
                      :kind="option.raw.kind"
                      :method="option.raw"
                      size="sm"
                      hide-installments
                    />
                  </template>
                  <template #option="{ option }">
                    <PaymentMethodBadge
                      :kind="option.raw.kind"
                      :method="option.raw"
                      size="sm"
                      hide-installments
                    />
                  </template>
                </FormSelect>
              </label>
              <label>
                <span>1ª venc.</span>
                <DatePickerBR v-model="uniformFirstDueDate" placeholder="DD/MM/AAAA" />
              </label>
              <label>
                <span>Intervalo (dias)</span>
                <input v-model.number="uniformIntervalDays" type="number" min="1" max="365" />
              </label>
            </div>
          </div>

          <!-- Entry + Remaining -->
          <div v-if="planMode === 'entry_plus'" class="entry-form">
            <fieldset>
              <legend>Entrada</legend>
              <div class="grid-3">
                <label>
                  <span>Valor</span>
                  <input v-model="entryAmountStr" type="text" inputmode="decimal" placeholder="0,00" />
                </label>
                <label>
                  <span>Forma</span>
                  <FormSelect
                    v-model="entryPaymentMethodId"
                    :options="paymentMethodOptions"
                    placeholder="Selecione…"
                    auto-searchable
                  >
                    <template #selected="{ option }">
                      <PaymentMethodBadge v-if="option?.raw" :kind="option.raw.kind" :method="option.raw" size="sm" hide-installments />
                    </template>
                    <template #option="{ option }">
                      <PaymentMethodBadge :kind="option.raw.kind" :method="option.raw" size="sm" hide-installments />
                    </template>
                  </FormSelect>
                </label>
                <label>
                  <span>Data</span>
                  <DatePickerBR v-model="entryDueDate" placeholder="DD/MM/AAAA" />
                </label>
              </div>
            </fieldset>

            <fieldset>
              <legend>Restante</legend>
              <div class="grid-4">
                <label>
                  <span>Parcelas</span>
                  <input v-model.number="remainingCount" type="number" min="1" max="60" />
                </label>
                <label>
                  <span>Forma</span>
                  <FormSelect
                    v-model="remainingPaymentMethodId"
                    :options="paymentMethodOptions"
                    placeholder="Selecione…"
                    auto-searchable
                  >
                    <template #selected="{ option }">
                      <PaymentMethodBadge v-if="option?.raw" :kind="option.raw.kind" :method="option.raw" size="sm" hide-installments />
                    </template>
                    <template #option="{ option }">
                      <PaymentMethodBadge :kind="option.raw.kind" :method="option.raw" size="sm" hide-installments />
                    </template>
                  </FormSelect>
                </label>
                <label>
                  <span>1ª venc.</span>
                  <DatePickerBR v-model="remainingFirstDueDate" placeholder="DD/MM/AAAA" />
                </label>
                <label>
                  <span>Intervalo (dias)</span>
                  <input v-model.number="remainingIntervalDays" type="number" min="1" max="365" />
                </label>
              </div>
            </fieldset>
          </div>

          <!-- Custom split -->
          <div v-if="planMode === 'custom'" class="custom-form">
            <PaymentSplitBuilder
              v-model="customRows"
              :payment-methods="paymentMethods"
              :perna-aggregates="pernaAggregates"
              :target-total-cents="totalCents"
            />
          </div>

          <!-- Preview agregado (sempre) -->
          <div v-if="planMode !== 'custom'" class="plan-preview">
            <h4>Pré-visualização</h4>
            <table class="rows">
              <thead>
                <tr>
                  <th>#</th>
                  <th>Valor base</th>
                  <th>Vencimento</th>
                  <th>Forma</th>
                  <th v-if="simulationData?.totals?.has_passthrough_rows">Cliente paga</th>
                  <th>Clínica recebe</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(row, idx) in installmentsPlan" :key="idx">
                  <td class="num">{{ idx + 1 }}</td>
                  <td class="value-col">{{ centsToBRL(row.amount_cents) }}</td>
                  <td>{{ formatDateBR(row.due_date) }}</td>
                  <td>
                    <PaymentMethodBadge
                      v-if="findPaymentMethod(row.payment_method_id)"
                      :kind="findPaymentMethod(row.payment_method_id).kind"
                      :method="findPaymentMethod(row.payment_method_id)"
                      size="sm"
                      hide-installments
                    />
                    <span v-else class="muted">—</span>
                  </td>
                  <td v-if="simulationData?.totals?.has_passthrough_rows" class="value-col">
                    <template v-if="simulationData?.plan?.[idx]">
                      {{ centsToBRL(simulationData.plan[idx].amount_cents) }}
                      <span
                        v-if="simulationData.plan[idx].passes_fee_to_patient"
                        class="passthrough-tag"
                      >+ taxa</span>
                    </template>
                    <span v-else class="muted">…</span>
                  </td>
                  <td class="value-col">
                    <template v-if="simulationData?.plan?.[idx]">
                      <strong>{{ centsToBRL(simulationData.plan[idx].net_amount_cents) }}</strong>
                    </template>
                    <span v-else class="muted">…</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <!-- Sumário e simulador ad-hoc lado a lado -->
          <div class="step-4-aside">
            <NetAmountCard
              v-if="simulationData?.totals"
              :totals="simulationData.totals"
              :budget-total-cents="totalCents"
            />
            <div v-else-if="simulating" class="loading-card">Simulando…</div>
            <div v-else-if="simulateError" class="error-card">{{ simulateError }}</div>

            <div class="adhoc">
              <h4>Calcular taxa de outro pagamento</h4>
              <p class="adhoc-hint">
                Quanto a clínica recebe líquido em uma forma e valor específicos —
                útil para conferir antes de aprovar.
              </p>
              <div class="adhoc-row">
                <FormSelect
                  v-model="adhocPmId"
                  :options="paymentMethodOptions"
                  placeholder="Forma"
                  auto-searchable
                >
                  <template #selected="{ option }">
                    <PaymentMethodBadge v-if="option?.raw" :kind="option.raw.kind" :method="option.raw" size="sm" hide-installments />
                  </template>
                  <template #option="{ option }">
                    <PaymentMethodBadge :kind="option.raw.kind" :method="option.raw" size="sm" hide-installments />
                  </template>
                </FormSelect>
                <input v-model="adhocAmountStr" type="text" inputmode="decimal" placeholder="Valor R$" />
                <input v-model.number="adhocInstallments" type="number" min="1" max="24" placeholder="Nx" />
              </div>
              <FeeSimulationCard :simulation="adhocResult" :loading="adhocLoading" />
            </div>
          </div>
        </section>

        <!-- ─────────────── Step 5: Confirmar ─────────────── -->
        <section v-if="currentStep === 5" class="step-pane">
          <h3>Confirmar aprovação</h3>

          <NetAmountCard
            v-if="simulationData?.totals"
            :totals="simulationData.totals"
            :budget-total-cents="totalCents"
          />

          <!-- Lista das cobranças REAIS que vão pra A Receber. Cada perna de
               crédito Nx aparece como N linhas (1/5, 2/5, ...) com vencimentos
               mensais — match exato com o que o paciente vê na fatura. -->
          <div class="generated-list">
            <div class="generated-list__header">
              <h4>
                Cobranças que serão criadas
                <span class="generated-list__count">{{ expandedPlan.length }}</span>
              </h4>
              <span class="generated-list__hint">
                Cada parcela de cartão Nx vira uma cobrança própria com vencimento mensal.
              </span>
            </div>

            <div class="generated-list__scroll">
              <table class="generated-table">
                <thead>
                  <tr>
                    <th class="num">#</th>
                    <th>Vencimento</th>
                    <th>Forma</th>
                    <th class="right">Valor</th>
                    <th class="right">Líquido</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="(row, idx) in expandedPlan"
                    :key="idx"
                    :class="{ 'tender-grouped': isTenderHead(idx) }"
                  >
                    <td class="num">{{ idx + 1 }}</td>
                    <td>{{ formatDateBR(row.due_date) }}</td>
                    <td class="forma">
                      <PaymentMethodBadge
                        v-if="findPaymentMethod(row.payment_method_id)"
                        :kind="findPaymentMethod(row.payment_method_id).kind"
                        :method="findPaymentMethod(row.payment_method_id)"
                        size="sm"
                        hide-installments
                      />
                      <span v-else class="muted">—</span>
                      <span
                        v-if="expandedPlanMap[idx]?.seq_total > 1"
                        class="seq-tag"
                        :title="`Parcela ${expandedPlanMap[idx].seq} de ${expandedPlanMap[idx].seq_total} no cartão`"
                      >{{ expandedPlanMap[idx].seq }}/{{ expandedPlanMap[idx].seq_total }}</span>
                    </td>
                    <td class="right value-col">{{ centsToBRL(amountForPatientAt(idx)) }}</td>
                    <td class="right value-col net">{{ centsToBRL(netAt(idx)) }}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>

          <p
            v-if="simulationData?.totals?.expected_commission_cents > 0"
            class="confirm-hint"
          >
            <i class="i-lucide-info w-4 h-4" />
            Comissão estimada de
            <strong>{{ centsToBRL(simulationData.totals.expected_commission_cents) }}</strong>
            será provisionada para o profissional.
          </p>

          <div v-if="submitError" class="error-card">{{ submitError }}</div>
        </section>
      </div>

      <footer class="wizard-footer">
        <div class="footer-note">
          <i class="i-lucide-shield-check w-3 h-3" />
          {{ currentStep === 5
            ? 'Revise os dados acima antes de confirmar — a aprovação é irreversível.'
            : 'Você poderá revisar tudo no passo Confirmar antes de aprovar.' }}
        </div>
        <div class="footer-actions">
          <button type="button" class="btn btn-ghost" :disabled="submitting" @click="close">
            Cancelar
          </button>
          <button
            v-if="currentStep > 1"
            type="button"
            class="btn btn-secondary"
            :disabled="submitting"
            @click="goPrev"
          >
            <i class="i-lucide-chevron-left w-4 h-4" /> Voltar
          </button>
          <button
            v-if="currentStep < 5"
            type="button"
            class="btn btn-primary"
            :disabled="!canAdvance"
            :title="advanceBlockReason"
            @click="goNext"
          >
            Avançar <i class="i-lucide-chevron-right w-4 h-4" />
          </button>
          <button
            v-else
            type="button"
            class="btn btn-primary"
            :disabled="!canSubmit || submitting"
            @click="submit"
          >
            <i class="i-lucide-check w-4 h-4" />
            {{ submitting ? 'Aprovando…' : 'Confirmar aprovação' }}
          </button>
        </div>
      </footer>
    </div>
  </div>
</template>

<style scoped lang="scss">
.wizard-overlay {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.55);
  display: grid; place-items: center; z-index: 1000;
  padding: 24px; overflow: auto;

  @media (max-width: 768px) {
    padding: 0; // mobile = full-screen, sem gap em volta
  }
}

.wizard {
  width: min(1100px, 100%); max-height: 92vh;
  background: rgb(var(--slate-1));
  border-radius: 12px;
  display: flex; flex-direction: column;
  box-shadow: 0 24px 64px rgba(0, 0, 0, 0.32);

  @media (max-width: 768px) {
    width: 100%;
    max-width: 100%;
    height: 100vh;
    max-height: 100vh;
    border-radius: 0;
    box-shadow: none;
  }
}

// ─── Header premium: title com icon-badge + subtitle com chip + total ──
.wizard-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 16px;
  padding: 22px 28px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
  background: linear-gradient(180deg, rgb(var(--blue-2) / 0.3) 0%, rgb(var(--slate-1)) 100%);

  .header-left { min-width: 0; flex: 1; }
  .title {
    margin: 0;
    font-size: 19px;
    font-weight: 700;
    color: rgb(var(--slate-12));
    letter-spacing: -0.01em;
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .title-badge {
    width: 32px;
    height: 32px;
    border-radius: 9px;
    // Solid + fallback Tailwind (blue-600) — `--blue-10` nem sempre resolve.
    background: rgb(var(--blue-9, 37 99 235));
    color: #fff;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    box-shadow: 0 4px 12px -3px rgb(var(--blue-9, 37 99 235) / 0.45);
    flex-shrink: 0;
  }
  .subtitle {
    margin-top: 8px;
    font-size: 13px;
    color: rgb(var(--slate-10));
    display: flex;
    align-items: center;
    gap: 8px;
    flex-wrap: wrap;

    .chip {
      background: rgb(var(--blue-3));
      color: rgb(var(--blue-11));
      padding: 2px 8px;
      border-radius: 6px;
      font-weight: 600;
      font-size: 12px;
      border: 1px solid rgb(var(--blue-5));
      font-variant-numeric: tabular-nums;
    }
    .dot { color: rgb(var(--slate-8)); }
    .total {
      font-weight: 700;
      color: rgb(var(--slate-12));
      font-size: 14px;
      font-variant-numeric: tabular-nums;
    }
  }
  .btn-close {
    width: 36px;
    height: 36px;
    border-radius: 10px;
    border: 1px solid rgb(var(--slate-4));
    background: rgb(var(--slate-1));
    color: rgb(var(--slate-10));
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    transition: background 160ms, color 160ms, border-color 160ms;
    flex-shrink: 0;

    &:hover:not(:disabled) {
      background: rgb(var(--slate-3));
      color: rgb(var(--slate-12));
      border-color: rgb(var(--slate-6));
    }
    &:disabled { opacity: 0.4; cursor: not-allowed; }
  }

  @media (max-width: 640px) {
    padding: 16px 18px 14px;
    .title { font-size: 16px; gap: 10px; }
    .title-badge { width: 28px; height: 28px; }
    .subtitle { font-size: 12px; }
  }
}

// ─── Section title (Step 4 + similar) ─────────────────────────────────────
.section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;

  h3 {
    margin: 0;
    font-size: 16px;
    font-weight: 700;
    color: rgb(var(--slate-12));
    letter-spacing: -0.01em;
    display: inline-flex;
    align-items: center;
    gap: 10px;
    i { color: rgb(var(--blue-10)); }
  }
  .section-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 24px;
    height: 22px;
    padding: 0 8px;
    border-radius: 11px;
    background: rgb(var(--blue-3));
    color: rgb(var(--blue-11));
    border: 1px solid rgb(var(--blue-5));
    font-size: 12px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .section-helper {
    font-size: 12px;
    color: rgb(var(--slate-10));
    display: inline-flex;
    align-items: center;
    gap: 6px;
    i { color: rgb(var(--slate-9)); }
  }

  @media (max-width: 640px) {
    flex-direction: column;
    align-items: flex-start;
    gap: 6px;
  }
}

// ─── Stepper premium ─────────────────────────────────────────────────────
// Circles 36×36 com gradient (verde quando done, azul quando current).
// Connector line atrás dos circles preenche conforme o progresso.
.stepper {
  position: relative;
  display: grid;
  grid-template-columns: repeat(5, 1fr);
  gap: 0;
  padding: 24px 28px 22px;
  border-bottom: 1px solid rgb(var(--slate-4));
  background: linear-gradient(180deg, rgb(var(--slate-1)) 0%, rgb(var(--slate-2)) 100%);
}
.step-connector {
  position: absolute;
  top: 42px;  // = padding-top(24) + circle-radius(18)
  left: calc(28px + 10%);
  right: calc(28px + 10%);
  height: 2px;
  background: rgb(var(--slate-4));
  z-index: 0;
  border-radius: 2px;
  overflow: hidden;
}
.step-connector-fill {
  height: 100%;
  // Fallbacks Tailwind (green-500 / blue-600) — `--green-9`/`--blue-9` nem
  // sempre resolvem no scope da componente; sem fallback o gradient inteiro
  // ficava inválido e a barra sumia.
  background: linear-gradient(
    90deg,
    rgb(var(--green-9, 34 197 94)) 0%,
    rgb(var(--blue-9, 37 99 235)) 100%
  );
  border-radius: 2px;
  transition: width 320ms cubic-bezier(0.16, 1, 0.3, 1);
}

.step {
  position: relative;
  z-index: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  background: transparent;
  border: 0;
  cursor: pointer;
  padding: 0;
  color: rgb(var(--slate-9));
  transition: color 200ms;

  .step-circle {
    width: 36px;
    height: 36px;
    border-radius: 50%;
    background: rgb(var(--slate-1));
    border: 2px solid rgb(var(--slate-5));
    color: rgb(var(--slate-9));
    display: inline-flex;
    align-items: center;
    justify-content: center;
    font-weight: 700;
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    transition: background 240ms, border-color 240ms, color 240ms,
                box-shadow 240ms, transform 240ms cubic-bezier(0.16, 1, 0.3, 1);
    i { color: inherit; }
  }
  .step-label {
    font-size: 12.5px;
    font-weight: 600;
    color: rgb(var(--slate-9));
    transition: color 200ms;
    white-space: nowrap;
  }

  // Done/current usam SOLID bg com fallbacks RGB porque `--green-10`/`--blue-10`
  // nem sempre resolvem; o gradient com token inválido vira `background: none`
  // e o checkmark branco fica invisível em fundo branco. Bug visto em 2026-05-28.
  &.done {
    .step-circle {
      background: rgb(var(--green-9, 34 197 94));
      border-color: rgb(var(--green-9, 34 197 94));
      color: #fff;
      box-shadow: 0 4px 12px -3px rgb(var(--green-9, 34 197 94) / 0.45);
    }
    .step-label { color: rgb(var(--green-11, 21 128 61)); }
  }
  &.current {
    .step-circle {
      background: rgb(var(--blue-9, 37 99 235));
      border-color: rgb(var(--blue-9, 37 99 235));
      color: #fff;
      box-shadow:
        0 0 0 4px rgb(var(--blue-5, 147 197 253) / 0.4),
        0 6px 16px -3px rgb(var(--blue-9, 37 99 235) / 0.5);
      transform: scale(1.06);
    }
    .step-label { color: rgb(var(--blue-11, 30 64 175)); }
  }

  &:disabled { cursor: not-allowed; }
  &:hover:not(:disabled):not(.current):not(.done) .step-circle {
    border-color: rgb(var(--slate-7));
  }

  @media (max-width: 640px) {
    gap: 6px;
    .step-circle { width: 30px; height: 30px; font-size: 12px; }
    .step-label {
      font-size: 10.5px;
      max-width: 100%;
      overflow: hidden;
      text-overflow: ellipsis;
    }
  }
}

@media (max-width: 640px) {
  .stepper { padding: 14px 12px 12px; }
  .step-connector {
    top: 28px;  // = padding-top(14) + circle-radius(15)
    left: calc(12px + 10%);
    right: calc(12px + 10%);
  }
}

.wizard-body {
  flex: 1; overflow-y: auto;
  padding: 24px;

  @media (max-width: 640px) {
    padding: 16px;
  }
}

.step-pane h3 {
  margin: 0 0 16px; font-size: 16px; color: rgb(var(--slate-12));
}
.step-pane h4 {
  margin: 16px 0 8px; font-size: 14px; color: rgb(var(--slate-11)); font-weight: 600;
}

.people-cards {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-bottom: 20px;

  @media (max-width: 640px) {
    grid-template-columns: 1fr;
  }

  .person-card {
    display: flex; align-items: center; gap: 12px;
    background: rgb(var(--slate-2));
    border: 1px solid rgb(var(--slate-4));
    border-radius: 10px;
    padding: 12px 14px;
  }
  // .avatar custom removido — Avatar shared do Chatwoot traz seu próprio
  // shadow root visual (iniciais coloridas determinísticas, suporte a `src`).
  .person-info {
    display: flex; flex-direction: column;
    min-width: 0;  // evita overflow quando nome do paciente é longo
    .role {
      font-size: 11px;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
    }
    strong {
      color: rgb(var(--slate-12));
      font-size: 14px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
}

table.items {
  width: 100%; border-collapse: collapse; margin-top: 16px;
  font-size: 13px;
  th, td { padding: 8px; border-bottom: 1px solid rgb(var(--slate-3)); text-align: left; }
  th { font-weight: 600; color: rgb(var(--slate-11)); text-transform: uppercase; font-size: 11px; letter-spacing: 0.05em; }

  // Colunas numéricas (Qtd, Unit., Subtotal) alinhadas à direita.
  // Item fica à esquerda (descrição).
  th:nth-child(2), td:nth-child(2),
  th:nth-child(3), td:nth-child(3),
  th:nth-child(4), td:nth-child(4) {
    text-align: right;
    font-variant-numeric: tabular-nums;
  }

  tr.items-total td {
    border-bottom: 0;
    padding-top: 12px;
    strong {
      color: rgb(var(--blue-11));
      font-size: 15px;
    }
  }
}

.hint {
  margin-top: 16px; padding: 10px 12px;
  background: rgb(var(--blue-2)); color: rgb(var(--blue-11));
  border-radius: 6px; font-size: 13px;
}

// Cards de desconto — 3 colunas em desktop, empilhados em mobile.
// Layout dentro do card: ícone à ESQUERDA + texto à direita (grid 2 cols).
.discount-cards {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 10px;
  margin-bottom: 20px;

  @media (max-width: 640px) {
    grid-template-columns: 1fr;
  }

  .discount-card {
    position: relative;
    // Grid 2 colunas: ícone (auto) + bloco de texto (1fr).
    // `align-items: start` + `margin-top` no ícone alinha visualmente com
    // a primeira linha do strong (padrão Material list item). Mais robusto
    // que `center` quando o subtítulo é multi-linha.
    display: grid;
    grid-template-columns: auto 1fr;
    align-items: start;
    gap: 12px;
    padding: 14px 16px;
    background: rgb(var(--slate-2));
    border: 2px solid rgb(var(--slate-5));
    border-radius: 10px;
    cursor: pointer;
    transition: all 120ms ease;
    color: rgb(var(--slate-12));
    min-height: 84px;

    input[type="radio"] {
      position: absolute; opacity: 0; pointer-events: none;
    }
    > i {
      // Tamanho explícito (não depende das classes utilitárias inline w-5/h-5
      // que podem ser sobrescritas por outros bundles).
      width: 22px; height: 22px;
      color: rgb(var(--slate-10));
      flex-shrink: 0;
      // Alinha topo do ícone com baseline do título: 14px font × 1.3 line-height
      // = ~18.2px / 2 → centro do strong fica ~9px do topo. Ícone 22/2 = 11px
      // centro. Compensa com margin-top 1px pra centros baterem na 1a linha.
      margin-top: 1px;
    }
    .dc-text {
      display: flex; flex-direction: column; gap: 2px; min-width: 0;
      strong { font-size: 14px; line-height: 1.3; }
      p {
        margin: 0; font-size: 12px; line-height: 1.4;
        color: rgb(var(--slate-10));
      }
    }

    &:hover { border-color: rgb(var(--slate-7)); }
    &.selected {
      border-color: rgb(var(--blue-9));
      background: rgb(var(--blue-2));
      > i { color: rgb(var(--blue-11)); }
      .dc-text strong { color: rgb(var(--blue-11)); }
    }
  }
}

.discount-input-row {
  position: relative;
  display: flex; align-items: center; margin-bottom: 20px;
  max-width: 280px;

  .discount-input {
    flex: 1; padding: 10px 44px 10px 14px;
    border: 1px solid rgb(var(--slate-6)); border-radius: 8px;
    background: rgb(var(--slate-1)); color: rgb(var(--slate-12));
    font-size: 16px; font-weight: 500;
    &:focus { outline: 2px solid rgb(var(--blue-8)); outline-offset: -1px; }
  }
  .discount-input-suffix {
    position: absolute; right: 14px;
    color: rgb(var(--slate-10)); font-weight: 600;
    pointer-events: none;
  }
}

.total-preview {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 14px 18px;
  display: flex; flex-direction: column; gap: 8px;

  .row { display: flex; justify-content: space-between; font-size: 14px; }
  .row.negative { color: rgb(var(--ruby-11)); }
  .row.total {
    border-top: 1px solid rgb(var(--slate-5));
    padding-top: 10px; margin-top: 4px;
    font-size: 17px; color: rgb(var(--blue-11)); font-weight: 700;
  }
}

.mode-cards {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
  gap: 12px;

  .mode-card {
    position: relative;
    background: rgb(var(--slate-2));
    border: 2px solid rgb(var(--slate-5));
    border-radius: 10px;
    padding: 16px;
    cursor: pointer;
    display: flex; flex-direction: column; gap: 6px;
    color: rgb(var(--slate-12));

    input[type="radio"] { position: absolute; opacity: 0; pointer-events: none; }
    strong { font-size: 15px; }
    p { margin: 0; color: rgb(var(--slate-10)); font-size: 12px; }
    i { color: rgb(var(--blue-10)); }

    &.selected {
      border-color: rgb(var(--blue-9));
      background: rgb(var(--blue-2));
      i { color: rgb(var(--blue-11)); }
    }
  }
}

.grid-3 { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.grid-4 { display: grid; grid-template-columns: repeat(4, 1fr); gap: 12px; }
.uniform-form, .entry-form { margin-bottom: 20px; }
.entry-form fieldset {
  border: 1px solid rgb(var(--slate-4)); border-radius: 8px;
  padding: 14px; margin: 0 0 12px;
  legend { padding: 0 6px; font-weight: 600; color: rgb(var(--slate-11)); }
}
label {
  display: flex; flex-direction: column; gap: 4px;
  font-size: 13px; color: rgb(var(--slate-11));
  > input { padding: 6px 8px; border: 1px solid rgb(var(--slate-6));
    border-radius: 6px; background: rgb(var(--slate-1)); color: rgb(var(--slate-12)); }
}

.plan-preview {
  margin-top: 20px;
  table.rows {
    width: 100%; border-collapse: collapse; font-size: 13px;
    th { text-align: left; padding: 8px; border-bottom: 1px solid rgb(var(--slate-3));
      font-weight: 600; color: rgb(var(--slate-11)); }
    td { padding: 6px 8px; border-bottom: 1px solid rgb(var(--slate-2)); }
    td.num { color: rgb(var(--slate-10)); width: 32px; }
    .muted { color: rgb(var(--slate-9)); }
    strong { color: rgb(var(--blue-11)); }
    // Colunas de valor (Valor base, Cliente paga, Clínica recebe) alinhadas
    // à direita com tabular-nums pra coluna ficar perfeitamente alinhada
    // (vírgulas e pontos colunados). Headers da última coluna também à direita.
    td.value-col {
      text-align: right;
      font-variant-numeric: tabular-nums;
      white-space: nowrap;
    }
    th:nth-child(2),
    th:nth-last-child(-n+2) {
      text-align: right;
    }
  }
  .passthrough-tag {
    margin-left: 4px; padding: 1px 5px;
    background: rgb(var(--amber-3));
    color: rgb(var(--amber-11));
    border: 1px solid rgb(var(--amber-7));
    border-radius: 4px;
    font-size: 10px;
    font-weight: 500;
  }
}

.step-4-aside {
  display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin-top: 20px;

  @media (max-width: 900px) {
    grid-template-columns: 1fr;
  }

  .adhoc {
    background: rgb(var(--slate-2));
    border: 1px solid rgb(var(--slate-4));
    border-radius: 10px;
    padding: 12px;

    h4 { margin: 0 0 4px; font-size: 13px; }
    .adhoc-hint {
      margin: 0 0 10px;
      font-size: 11px;
      color: rgb(var(--slate-10));
      line-height: 1.4;
    }
    .adhoc-row {
      display: grid; grid-template-columns: 2fr 1fr 1fr; gap: 8px; margin-bottom: 12px;
      input { padding: 6px 8px; border: 1px solid rgb(var(--slate-6)); border-radius: 6px;
        background: rgb(var(--slate-1)); color: rgb(var(--slate-12)); font-size: 13px; }
    }
  }
}

// Mobile: 4 colunas grid viram 2 / 2 colunas (sem 3 cols)
.grid-3 {
  @media (max-width: 640px) { grid-template-columns: 1fr 1fr; }
}
.grid-4 {
  @media (max-width: 640px) { grid-template-columns: 1fr 1fr; }
}

.loading-card, .error-card {
  padding: 14px; border-radius: 8px; font-size: 13px;
}
.loading-card { background: rgb(var(--slate-2)); color: rgb(var(--slate-10)); }
.error-card {
  background: rgb(var(--ruby-3));
  color: rgb(var(--ruby-11));
  border: 1px solid rgb(var(--ruby-7));
}

// Mensagem amigável do Step 5 — substituiu o bloco técnico de "Eventos que
// serão gerados" + "Ver payload" (dev-only). Cliente não precisa ver detalhes
// de implementação na hora de confirmar.
.confirm-hint {
  margin: 16px 0 0;
  padding: 12px 14px;
  background: rgb(var(--blue-2));
  border: 1px solid rgb(var(--blue-6));
  border-radius: 8px;
  color: rgb(var(--blue-11));
  font-size: 13px;
  line-height: 1.5;
  display: inline-flex;
  align-items: center;
  gap: 8px;

  strong { font-weight: 600; }
}

// Lista de cobranças geradas no Step 5 — tabela compacta, scrollável,
// mostrando 1:1 o que vai virar Installment. Cada perna de crédito Nx
// aparece como N linhas com tag de sequência "k/N", de forma que o
// operador SE o paciente vê na fatura aqui na confirmação.
.generated-list {
  margin-top: 20px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  overflow: hidden;

  &__header {
    padding: 14px 16px 10px;
    border-bottom: 1px solid rgb(var(--slate-3));
    background: rgb(var(--slate-2));

    h4 {
      margin: 0;
      font-size: 14px;
      font-weight: 600;
      color: rgb(var(--slate-12));
      display: inline-flex;
      align-items: center;
      gap: 8px;
    }
  }
  &__count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 22px;
    padding: 0 7px;
    height: 22px;
    border-radius: 11px;
    background: rgb(var(--blue-9));
    color: #fff;
    font-size: 12px;
    font-weight: 600;
  }
  &__hint {
    display: block;
    margin-top: 4px;
    font-size: 12px;
    color: rgb(var(--slate-10));
  }
  &__scroll {
    max-height: 280px;
    overflow-y: auto;
  }
}
.generated-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;

  thead th {
    position: sticky;
    top: 0;
    background: rgb(var(--slate-1));
    text-align: left;
    padding: 10px 14px;
    font-weight: 600;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: rgb(var(--slate-10));
    border-bottom: 1px solid rgb(var(--slate-3));

    &.right { text-align: right; }
    &.num { width: 40px; text-align: right; padding-right: 8px; }
  }
  tbody td {
    padding: 9px 14px;
    border-bottom: 1px solid rgb(var(--slate-2));
    color: rgb(var(--slate-12));
    vertical-align: middle;

    &.num {
      width: 40px;
      text-align: right;
      padding-right: 8px;
      color: rgb(var(--slate-9));
      font-variant-numeric: tabular-nums;
    }
    &.right { text-align: right; }
    &.value-col { font-variant-numeric: tabular-nums; white-space: nowrap; }
    &.net { color: rgb(var(--blue-11)); font-weight: 600; }
    &.forma { display: flex; align-items: center; gap: 8px; }
    &.muted { color: rgb(var(--slate-9)); }
  }
  tbody tr:last-child td { border-bottom: 0; }
  tbody tr.tender-grouped td {
    border-top: 2px solid rgb(var(--slate-3));
  }
}
.seq-tag {
  display: inline-flex;
  align-items: center;
  padding: 1px 7px;
  border-radius: 999px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  font-size: 11px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}

// ─── Footer premium: note esquerda + ações direita, primary com gradient ──
.wizard-footer {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  padding: 18px 28px;
  border-top: 1px solid rgb(var(--slate-4));
  background: linear-gradient(180deg, rgb(var(--slate-2)) 0%, rgb(var(--slate-1)) 100%);
  border-radius: 0 0 12px 12px;

  .footer-note {
    font-size: 12px;
    color: rgb(var(--slate-9));
    display: inline-flex;
    align-items: center;
    gap: 6px;
    flex: 1;
    min-width: 0;
    i { color: rgb(var(--slate-9)); flex-shrink: 0; }
  }
  .footer-actions {
    display: flex;
    gap: 10px;
    flex-shrink: 0;
  }

  .btn {
    height: 40px;
    padding: 0 18px;
    border-radius: 10px;
    border: 1px solid transparent;
    font-size: 13.5px;
    font-weight: 600;
    font-family: inherit;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 8px;
    transition: background 160ms, border-color 160ms, color 160ms,
                box-shadow 160ms, transform 100ms;

    &:disabled { opacity: 0.55; cursor: not-allowed; }
  }
  .btn-ghost {
    background: transparent;
    color: rgb(var(--slate-11));
    &:hover:not(:disabled) {
      background: rgb(var(--slate-3));
      color: rgb(var(--slate-12));
    }
  }
  .btn-secondary {
    background: rgb(var(--slate-1));
    color: rgb(var(--slate-11));
    border-color: rgb(var(--slate-6));
    &:hover:not(:disabled) {
      background: rgb(var(--slate-2));
      border-color: rgb(var(--slate-8));
      color: rgb(var(--slate-12));
    }
  }
  .btn-primary {
    // Solid bg + fallbacks pra sobreviver quando `--blue-10`/`--blue-11` não
    // resolvem (gradient inválido = `background: none` → botão branco).
    background: rgb(var(--blue-9, 37 99 235));
    color: #fff;
    box-shadow:
      0 4px 12px -3px rgb(var(--blue-9, 37 99 235) / 0.5),
      inset 0 1px 0 rgb(255 255 255 / 0.2);

    &:hover:not(:disabled) {
      background: rgb(var(--blue-10, 29 78 216));
      box-shadow:
        0 6px 16px -3px rgb(var(--blue-9, 37 99 235) / 0.6),
        inset 0 1px 0 rgb(255 255 255 / 0.2);
      transform: translateY(-1px);
    }
    &:active:not(:disabled) { transform: translateY(0); }
    &:disabled {
      background: rgb(var(--slate-6));
      box-shadow: none;
    }
  }

  @media (max-width: 640px) {
    flex-direction: column-reverse;
    align-items: stretch;
    gap: 12px;
    padding: 14px 16px;
    border-radius: 0;
    .footer-note { justify-content: center; }
    .footer-actions {
      width: 100%;
      justify-content: stretch;
      .btn { flex: 1; justify-content: center; }
    }
  }
}
</style>
