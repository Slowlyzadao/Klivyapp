<script setup>
/**
 * Lançamento manual avulso — canon F-25 + Fase 1 (2026-05-23).
 *
 * Modal dual-purpose com Status que muda o destino do payload:
 *   - Pago/Recebido → cria `Financial::Entry` (lançamento direto no Fluxo de Caixa)
 *   - Pendente      → cria `Financial::Expense` (vai pra A Pagar)
 *                    → bloqueia se direction='in' (canon: A Receber só vem
 *                      de Budget; mostra CTA "Criar orçamento" no lugar)
 *
 * Campos por direção:
 *   • Entrada: + Paciente (Contact picker, opcional) + Dentista (AgentProfile, opcional)
 *   • Saída:   + Fornecedor (texto livre, opcional)
 *
 * Props:
 *   - show: Boolean
 *   - direction: 'in' | 'out' | null (pré-seleciona; null = usuário escolhe)
 *
 * Eventos:
 *   - close
 *   - confirm: { entry|expense } (objeto retornado pelo backend)
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import UserPickerSelect from '@plugins/beclinic_core/frontend/components/UserPickerSelect.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import PaymentMethodBadge from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import PatientsAPI from '@plugins/patients/frontend/api/patients';
import FinancialV2 from '../api/financialV2';
import { brlInputToCents, formatCurrencyInput, centsToBRL, bankKindLabel } from '../composables/useMoney';

const props = defineProps({
  show: { type: Boolean, default: false },
  direction: { type: String, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const router = useRouter();
const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// ── Estado do form ──────────────────────────────────────────────
const dir = ref('in');
const status = ref('paid'); // 'paid' (pago/recebido) ou 'pending'
const amountStr = ref('');
const description = ref('');
const cashDate = ref(new Date().toISOString().slice(0, 10));
const competenceDate = ref('');
const dueDate = ref('');
const bankAccountId = ref(null);
const categoryId = ref(null);
// Canon V2 (1.8.0.10): FK pra PaymentMethod do Settings, não string enum.
// `payment_method` (kind) é derivado do PM selecionado pra compat com backend.
const paymentMethodId = ref(null);
// Override da conta destino — info-card "da forma · Alterar" some quando true.
// Reset toda vez que muda Forma (watch abaixo).
const overrideBankAccount = ref(false);
const submitting = ref(false);

// Entrada-only — busca remota de paciente reusa UserPickerSelect com
// cache acumulativo. Cada query do dropdown dispara fetch no servidor
// e mergeia no `patientCache` (sem remover entradas — mantém o paciente
// selecionado visível mesmo quando o usuário troca a busca).
const selectedPatientId = ref(null);
const patientCache = ref([]); // [{ id, name, avatar_url }]
let patientSearchTimer = null;

const selectedProfessionalId = ref(null);

// Saída-only
const supplierName = ref('');

// Dados auxiliares
const bankAccounts = ref([]);
const categories = ref([]);
const agentProfiles = ref([]);
const paymentMethods = ref([]);
const paymentMethodsLoading = ref(false);

// Canon V2 (1.8.0.10): formas de pagamento carregadas de Settings → Formas
// de Pagamento (não mais hardcoded). Cada PM tem kind canônico + provider
// custom (ex: "PIX Cielo"). Visual via PaymentMethodBadge.
const selectedPaymentMethod = computed(() =>
  paymentMethods.value.find(m => m.id === paymentMethodId.value) || null,
);

const paymentMethodOptions = computed(() => {
  const list = [...paymentMethods.value];
  // Sem provider primeiro (operação direta), depois alfabético por provider
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

const bankAccountOptions = computed(() =>
  bankAccounts.value.map(b => ({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` })),
);

const selectedBankAccount = computed(
  () => bankAccounts.value.find(b => b.id === bankAccountId.value) || null,
);

// Info-card "da forma · Alterar" aparece quando a Forma escolhida tem
// `default_bank_account_id` configurado E operador não clicou em Alterar.
// Caso contrário, mostra FormSelect editável (mesmo padrão do
// ReceivePaymentModalV2 — UX coerente em todos os modais financeiros).
const showBankAccountInfo = computed(
  () => !!selectedPaymentMethod.value?.default_bank_account_id && !overrideBankAccount.value,
);

// Mapa do `agent_category` canon → label curto pro badge do picker.
// Mesma convenção usada em Settings → Agentes.
const AGENT_CATEGORY_LABEL = {
  profissional: 'Profissional',
  operacional:  'Operacional',
  comercial:    'Comercial',
  administrador: 'Administrador',
};

// Lista todos os Users da conta no picker (canon F-25 lançamento manual
// não exige AgentProfile — diferente de Budget/Commission que sim).
// Users SEM AgentProfile aparecem só com avatar + nome (sem badge).
// Users COM AgentProfile ativo ganham badge da categoria (Profissional,
// Operacional, etc). Inativos são ocultados.
const professionalUsers = computed(() =>
  agentProfiles.value
    .filter(ap => ap.user && (!ap.profile || ap.profile.status !== 'inactive'))
    .map(ap => ({
      id: ap.user.id,
      name: ap.user.name,
      avatar_url: ap.user.avatar_url || null,
      role: ap.profile ? AGENT_CATEGORY_LABEL[ap.profile.agent_category] : null,
    })),
);

// Cor por tipo (espelha Badge global) — FormSelect renderiza bolinha + hint.
const CATEGORY_VISUAL = {
  receita:        { color: '#10b981', hint: 'Receita' },
  despesa_fixa:   { color: '#dc2626', hint: 'Despesa fixa' },
  custo_variavel: { color: '#f59e0b', hint: 'Custo variável' },
  outra_despesa:  { color: '#64748b', hint: 'Outra despesa' },
};

const categoryOptions = computed(() => {
  const allowedKinds = dir.value === 'in'
    ? ['receita']
    : ['despesa_fixa', 'custo_variavel', 'outra_despesa'];
  return categories.value
    .filter(c => allowedKinds.includes(c.kind))
    .map(c => {
      const v = CATEGORY_VISUAL[c.kind] || { color: '#94a3b8', hint: c.kind };
      return { value: c.id, label: c.name, color: v.color, hint: v.hint };
    });
});

const grossCents = computed(() => brlInputToCents(amountStr.value));

const isIn = computed(() => dir.value === 'in');
const isPending = computed(() => status.value === 'pending');

// Canon: A Receber pendente sempre vem de Budget. Entrada+Pendente bloqueia
// e mostra CTA pra criar orçamento avulso.
const blockedEntrancePending = computed(() => isIn.value && isPending.value);

const statusOptions = computed(() =>
  isIn.value
    ? [
        { value: 'paid',    label: 'Recebido', icon: 'i-lucide-check-circle-2' },
        { value: 'pending', label: 'Pendente', icon: 'i-lucide-clock' },
      ]
    : [
        { value: 'paid',    label: 'Pago',     icon: 'i-lucide-check-circle-2' },
        { value: 'pending', label: 'Pendente', icon: 'i-lucide-clock' },
      ],
);

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!dir.value) return false;
  if (blockedEntrancePending.value) return false;
  if (grossCents.value <= 0) return false;
  if (!description.value.trim()) return false;
  // Expense exige categoria (FK NOT NULL). Entry permite null (vira "Sem categoria").
  if (isPending.value && !categoryId.value) return false;
  // Status=Pago/Recebido vai pra Entry, exige conta. Status=Pendente vai
  // pra Expense, conta é opcional (será preenchida no momento do pagamento).
  if (!isPending.value && !bankAccountId.value) return false;
  return true;
});

// ── Patient remote search ───────────────────────────────────────
// Disparado pelo `@search-change` do UserPickerSelect quando o usuário
// digita no campo de busca do dropdown. Debounce 250ms pra evitar
// floodar o backend. Cache só CRESCE (de-dup por id) — assim o paciente
// selecionado nunca desaparece do `users` da prop e o trigger continua
// mostrando avatar+nome corretamente.
function onPatientSearch(query) {
  clearTimeout(patientSearchTimer);
  const q = (query || '').trim();
  if (q.length < 2) return;
  patientSearchTimer = setTimeout(() => fetchPatients(q), 250);
}

async function fetchPatients(query) {
  try {
    const params = query ? { search: query, perPage: 20 } : { perPage: 20 };
    const { data } = await PatientsAPI.get(params);
    const fetched = data?.payload || data?.data || data?.patients || [];
    const seen = new Set(patientCache.value.map(p => p.id));
    for (const p of fetched) {
      if (!seen.has(p.id)) {
        patientCache.value.push({
          id: p.id,
          name: p.name,
          avatar_url: p.avatar_url || null,
        });
      }
    }
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('[ManualEntryModalV2] patient search failed', e);
  }
}

// ── Aux data load ───────────────────────────────────────────────
async function loadAux() {
  paymentMethodsLoading.value = true;
  try {
    const [b, c, ap, pm] = await Promise.all([
      FinancialV2.bankAccounts.index({ active: 'true' }),
      FinancialV2.categories.index({ active: 'true' }),
      FinancialV2.agentProfiles.index({}),
      FinancialV2.paymentMethods.index({ status: 'active' }),
    ]);
    bankAccounts.value = b?.data?.data || [];
    categories.value = c?.data?.data || [];
    agentProfiles.value = ap?.data?.data || ap?.data || [];
    paymentMethods.value = (pm?.data?.data || []).filter(m => m.status === 'active');
    if (bankAccounts.value.length === 1) bankAccountId.value = bankAccounts.value[0].id;

    // Pré-seleciona PIX (sem provider) por default. Fallback: 1º da lista.
    // Mesma heurística do ReceivePaymentModalV2 — mantém UX coerente.
    if (!paymentMethodId.value) {
      const pixDirect = paymentMethods.value.find(m => m.kind === 'pix' && !m.provider);
      paymentMethodId.value = pixDirect?.id || paymentMethods.value[0]?.id || null;
    }

    // Pre-carrega 20 pacientes recentes pra dropdown ja abrir populado.
    // Subsequente busca por digitação acumula no mesmo cache (de-dup por id).
    fetchPatients(null);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[ManualEntryModalV2] loadAux error', err);
  } finally {
    paymentMethodsLoading.value = false;
  }
}

function reset() {
  dir.value = props.direction || 'in';
  status.value = 'paid';
  amountStr.value = '';
  description.value = '';
  cashDate.value = new Date().toISOString().slice(0, 10);
  competenceDate.value = '';
  dueDate.value = '';
  categoryId.value = null;
  // paymentMethodId é re-pré-selecionado pelo loadAux (PIX default ou 1º da lista)
  paymentMethodId.value = null;
  overrideBankAccount.value = false;
  submitting.value = false;
  selectedPatientId.value = null;
  patientCache.value = [];
  selectedProfessionalId.value = null;
  supplierName.value = '';
  if (bankAccounts.value.length === 1) bankAccountId.value = bankAccounts.value[0].id;
}

watch(
  () => props.show,
  (val) => {
    if (val) {
      reset();
      loadAux();
    }
  },
);

// Quando muda direção, limpa categoria + reseta status (rótulos mudam)
watch(dir, () => {
  categoryId.value = null;
  status.value = 'paid';
});

// Canon V2 (1.8.0.11): quando muda Forma de Pagamento, auto-seleciona
// a Conta Destino se a forma tiver `default_bank_account_id` configurado
// em Settings. Operador pode override depois clicando no dropdown.
// Mesmo padrão do ReceivePaymentModalV2 — UX coerente.
watch(selectedPaymentMethod, (method) => {
  if (!method) return;
  // Reset override sempre que muda Forma — info-card volta a aparecer.
  overrideBankAccount.value = false;
  if (method.default_bank_account_id) {
    bankAccountId.value = method.default_bank_account_id;
  }
});

onMounted(() => {
  if (props.show) {
    reset();
    loadAux();
  }
});

function onAmountInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  amountStr.value = formatted;
  e.target.value = formatted;
}

// ── Submit ──────────────────────────────────────────────────────
async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    if (status.value === 'paid') {
      await submitAsEntry();
    } else {
      await submitAsExpense();
    }
  } catch (err) {
    const errors = err?.response?.data?.errors;
    const msg = Array.isArray(errors) ? errors.join('; ') : errors || err?.response?.data?.message;
    notifyError(msg || 'Erro ao registrar lançamento');
  } finally {
    submitting.value = false;
  }
}

async function submitAsEntry() {
  const pm = selectedPaymentMethod.value;
  // Nota: `financial_entries` não tem coluna `payment_method_id` (só `payment_method`
  // string). Visual UI usa PaymentMethodBadge canon, mas FK só persiste em Expense
  // e Installment. Se quiser FK em Entry no futuro, adicionar migration
  // `add_column :financial_entries, :payment_method_id`.
  const payload = {
    entry: {
      direction: dir.value,
      amount_cents: grossCents.value,
      description: description.value.trim(),
      cash_date: cashDate.value,
      competence_date: competenceDate.value || cashDate.value,
      financial_bank_account_id: bankAccountId.value,
      financial_dre_category_id: categoryId.value,
      payment_method: pm?.kind || null,
      patient_id: isIn.value ? selectedPatientId.value || null : null,
      professional_id: isIn.value ? selectedProfessionalId.value : null,
    },
  };
  const { data } = await FinancialV2.entries.create(payload);
  notifySuccess(
    isIn.value
      ? 'Entrada registrada no Fluxo de Caixa.'
      : 'Saída registrada no Fluxo de Caixa.',
  );
  emit('confirm', data);
  emit('close');
}

async function submitAsExpense() {
  // Aqui sempre direction='out' porque entrada+pendente é bloqueada acima.
  const competence = competenceDate.value || cashDate.value;
  const due = dueDate.value || cashDate.value;
  const pm = selectedPaymentMethod.value;
  const payload = {
    expense: {
      description: description.value.trim(),
      financial_dre_category_id: categoryId.value,
      financial_bank_account_id: bankAccountId.value,
      supplier_name: supplierName.value.trim() || null,
      amount_cents: grossCents.value,
      status: 'pendente',
      // Canon V2: kind (string compat) + FK pra Settings (rastreio provider)
      payment_method: pm?.kind || null,
      payment_method_id: pm?.id || null,
      competence_date: competence,
      due_date: due,
      installments_count: 1,
      installment_number: 1,
    },
  };
  const { data } = await FinancialV2.expenses.create(payload);
  notifySuccess('Despesa criada em A Pagar.');
  emit('confirm', data);
  emit('close');
}

function goToCreateBudget() {
  // Canon: A Receber pendente sempre nasce de um Budget. Redireciona pra
  // tela "A Receber" onde o operador cria orçamento avulso. Eventualmente
  // aqui pode abrir o BudgetFormModalV2 direto.
  router.push({ name: 'financial_v2_receivables' });
  emit('close');
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const titleText = computed(() => (isIn.value ? 'Nova entrada' : 'Nova saída'));
const titleIcon = computed(() => (isIn.value ? 'i-lucide-arrow-down-to-line' : 'i-lucide-arrow-up-from-line'));
const ctaColor = computed(() => (isIn.value ? 'teal' : 'ruby'));
const ctaLabel = computed(() => {
  if (isPending.value) return 'Lançar como pendente';
  return isIn.value ? 'Registrar entrada' : 'Registrar saída';
});
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="men-v2__backdrop"
    >
      <div class="men-v2__modal" role="dialog" aria-modal="true">
        <!-- Header -->
        <header class="men-v2__header">
          <div class="men-v2__header-text">
            <h2 class="men-v2__title">
              <i :class="titleIcon" class="men-v2__title-icon" />
              {{ titleText }}
              <span class="men-v2__title-kind">
                ({{ isIn ? 'Receita' : 'Despesa' }})
              </span>
            </h2>
            <p class="men-v2__subtitle">
              <template v-if="isPending">
                Lançamento <strong>pendente</strong> — entra em
                {{ isIn ? 'A Receber' : 'A Pagar' }} até ser confirmado.
              </template>
              <template v-else>
                Lançamento confirmado direto no Fluxo de Caixa.
              </template>
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

        <!-- Body -->
        <div class="men-v2__body">
          <!-- Direção (chips In/Out) — só se caller não pré-selecionou -->
          <section v-if="!direction" class="men-v2__section">
            <label class="men-v2__field-label">Tipo de lançamento</label>
            <div class="men-v2__chips">
              <button
                type="button"
                class="men-v2__chip men-v2__chip--tone-emerald"
                :class="{ 'men-v2__chip--active': isIn }"
                @click="dir = 'in'"
              >
                <i class="i-lucide-arrow-down-to-line w-3.5 h-3.5" />
                <span>Entrada</span>
              </button>
              <button
                type="button"
                class="men-v2__chip men-v2__chip--tone-ruby"
                :class="{ 'men-v2__chip--active': !isIn }"
                @click="dir = 'out'"
              >
                <i class="i-lucide-arrow-up-from-line w-3.5 h-3.5" />
                <span>Saída</span>
              </button>
            </div>
          </section>

          <!-- Status (chips Pago/Recebido vs Pendente) -->
          <section class="men-v2__section">
            <label class="men-v2__field-label">Status *</label>
            <div class="men-v2__chips">
              <button
                v-for="opt in statusOptions"
                :key="opt.value"
                type="button"
                class="men-v2__chip men-v2__chip--status"
                :class="{ 'men-v2__chip--status-active': status === opt.value }"
                @click="status = opt.value"
              >
                <i :class="opt.icon" class="w-3.5 h-3.5" />
                <span>{{ opt.label }}</span>
              </button>
            </div>
          </section>

          <!-- ⚠ Aviso: Entrada+Pendente bloqueada -->
          <section v-if="blockedEntrancePending" class="men-v2__blocked">
            <i class="i-lucide-info" />
            <div class="men-v2__blocked-content">
              <strong>Entrada pendente exige orçamento</strong>
              <p>
                Recebíveis em aberto (A Receber) nascem sempre de um orçamento
                no Klivy. Pra registrar um valor que <em>vai</em> entrar mas ainda
                não entrou, crie um orçamento (de paciente ou avulso) e ele
                aparecerá em A Receber.
              </p>
              <BeclinicButton
                variant="solid"
                color="blue"
                size="sm"
                icon="i-lucide-plus"
                label="Ir pra A Receber"
                @click="goToCreateBudget"
              />
            </div>
          </section>

          <!-- Form principal — só renderiza se não estiver bloqueado -->
          <!-- Ordem semântica (1.8.0.11): O QUE → QUANTO → COMO → QUANDO → QUEM
               • Descrição (o que)
               • Valor + Categoria (quanto + onde no DRE)
               • Forma de pagamento + Conta destino (Forma 1º — auto-seleciona Conta)
               • Data + Competência (quando — Fluxo de Caixa + DRE)
               • Paciente + Profissional (entrada) / Fornecedor (saída) -->
          <template v-else>
            <section class="men-v2__section">
              <div class="men-v2__grid">
                <label class="men-v2__field men-v2__field--full">
                  <span class="men-v2__field-label">Descrição *</span>
                  <input
                    v-model="description"
                    type="text"
                    class="finv2-input"
                    placeholder="Ex.: Aporte de sócio, Compra de papelaria, Multa bancária"
                  />
                </label>

                <label class="men-v2__field">
                  <span class="men-v2__field-label">Valor *</span>
                  <div class="men-v2__currency-wrap">
                    <span class="men-v2__currency-prefix">R$</span>
                    <input
                      :value="amountStr"
                      type="text"
                      inputmode="numeric"
                      placeholder="0,00"
                      class="finv2-input men-v2__currency-input"
                      @input="onAmountInput"
                    />
                  </div>
                </label>

                <label class="men-v2__field">
                  <span class="men-v2__field-label">
                    Categoria
                    <span class="men-v2__field-hint">
                      {{ isPending ? '*' : `(${isIn ? 'apenas receitas' : 'apenas despesas'})` }}
                    </span>
                  </span>
                  <FormSelect
                    v-model="categoryId"
                    :options="categoryOptions"
                    placeholder="Selecione a categoria"
                    searchable
                    auto-searchable
                    :clearable="!isPending"
                  />
                </label>

                <label class="men-v2__field">
                  <span class="men-v2__field-label">Forma de pagamento</span>
                  <!-- Canon V2 (1.8.0.10): carrega PMs ativos do Settings via
                       PaymentMethodBadge (trigger + dropdown options). Mesmo
                       padrão do ReceivePaymentModalV2/EditInstallmentModal etc.
                       Trocar Forma auto-seleciona Conta destino (watch acima). -->
                  <div v-if="paymentMethodsLoading" class="men-v2__pm-loading">
                    <i class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin" />
                    <span>Carregando…</span>
                  </div>
                  <div v-else-if="paymentMethods.length === 0" class="men-v2__pm-empty">
                    <i class="i-lucide-info w-3.5 h-3.5" />
                    <span>
                      Nenhuma forma cadastrada. Vá em
                      <em>Configurações → Formas de Pagamento</em>.
                    </span>
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
                      <span v-if="option.hint" class="men-v2__pm-provider-hint">
                        <i class="i-lucide-building-2 w-3 h-3" />
                        {{ option.hint }}
                      </span>
                    </template>
                  </FormSelect>
                </label>

                <label class="men-v2__field">
                  <span class="men-v2__field-label">
                    {{ isIn ? 'Conta Destino' : 'Conta Débito' }}
                    <span class="men-v2__field-hint">
                      {{ isPending ? '(opcional — define no pagamento)' : '*' }}
                    </span>
                  </span>
                  <!-- Info-card "da forma · Alterar" quando a Forma escolhida
                       tem default_bank_account_id (caso comum, 95%); FormSelect
                       quando sem default OU operador clica "Alterar" pra override.
                       Mesmo padrão do ReceivePaymentModalV2 — UX coerente. -->
                  <div
                    v-if="showBankAccountInfo && selectedBankAccount"
                    class="men-v2__bank-info"
                  >
                    <i class="i-lucide-landmark w-3.5 h-3.5" />
                    <span class="men-v2__bank-info-name">{{ selectedBankAccount.name }}</span>
                    <span class="men-v2__bank-info-tag">da forma</span>
                    <button
                      type="button"
                      class="men-v2__bank-info-edit"
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
                    :clearable="isPending"
                  />
                </label>

                <!-- Data + Competência (regime caixa + regime competência) -->
                <label class="men-v2__field">
                  <span class="men-v2__field-label">
                    {{ isPending ? 'Vencimento *' : 'Data *' }}
                  </span>
                  <DatePickerBR
                    v-if="isPending"
                    v-model="dueDate"
                  />
                  <DatePickerBR
                    v-else
                    v-model="cashDate"
                  />
                </label>

                <label class="men-v2__field">
                  <span class="men-v2__field-label">
                    Competência
                    <Tooltip
                      label="Data usada no DRE (regime contábil). Se diferente da Data, separa o mês do DRE do mês do Fluxo de Caixa. Default: mesma data."
                      position="top"
                      multiline
                    >
                      <i class="i-lucide-info w-3.5 h-3.5 text-slate-9 cursor-help" />
                    </Tooltip>
                    <span class="men-v2__field-hint">(opcional)</span>
                  </span>
                  <DatePickerBR v-model="competenceDate" />
                </label>

                <!-- ── Entrada-only: Paciente + Profissional (lado a lado) ── -->
                <template v-if="isIn">
                  <label class="men-v2__field">
                    <span class="men-v2__field-label">
                      Paciente
                      <span class="men-v2__field-hint">(opcional)</span>
                    </span>
                    <UserPickerSelect
                      v-model="selectedPatientId"
                      :users="patientCache"
                      placeholder="Selecione o paciente"
                      searchable
                      clearable
                      @search-change="onPatientSearch"
                    />
                  </label>

                  <label class="men-v2__field">
                    <span class="men-v2__field-label">
                      Profissional
                      <span class="men-v2__field-hint">(opcional)</span>
                    </span>
                    <UserPickerSelect
                      v-model="selectedProfessionalId"
                      :users="professionalUsers"
                      placeholder="Selecione o profissional"
                      searchable
                      auto-searchable
                      clearable
                    />
                  </label>
                </template>

                <!-- ── Saída-only: Fornecedor ── -->
                <label v-else class="men-v2__field men-v2__field--full">
                  <span class="men-v2__field-label">
                    Fornecedor
                    <span class="men-v2__field-hint">(opcional)</span>
                  </span>
                  <input
                    v-model="supplierName"
                    type="text"
                    class="finv2-input"
                    placeholder="Ex.: Distribuidora Dental Brasil, Aluguel João Silva"
                  />
                </label>
              </div>
            </section>

            <!-- Resumo -->
            <section v-if="grossCents > 0" class="men-v2__summary">
              <div class="men-v2__summary-row men-v2__summary-row--total">
                <span>
                  {{
                    isPending
                      ? 'Vai pra A Pagar'
                      : isIn ? 'Total a creditar' : 'Total a debitar'
                  }}
                </span>
                <strong :class="isIn ? 'men-v2__summary-amount--in' : 'men-v2__summary-amount--out'">
                  {{ isIn ? '+' : '−' }} {{ centsToBRL(grossCents) }}
                </strong>
              </div>
              <p v-if="!categoryId && !isPending" class="men-v2__warning">
                <i class="i-lucide-info w-3.5 h-3.5" />
                Sem categoria, este lançamento não aparece no DRE — só no Fluxo de Caixa.
                Você pode reclassificar depois pela tela "Sem categoria".
              </p>
            </section>
          </template>
        </div>

        <!-- Footer -->
        <footer class="men-v2__footer">
          <BeclinicButton
            variant="ghost"
            color="slate"
            label="Cancelar"
            :disabled="submitting"
            @click="close"
          />
          <BeclinicButton
            v-if="!blockedEntrancePending"
            variant="solid"
            :color="ctaColor"
            :icon="titleIcon"
            :label="ctaLabel"
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
.men-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999; padding: 0;
}
@media (min-width: 640px) {
  .men-v2__backdrop { align-items: center; padding: 16px; }
}

.men-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  border: 0; border-radius: 0;
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .men-v2__modal {
    width: min(720px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

/* Header */
.men-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.men-v2__title {
  margin: 0; font-size: 17px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.men-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--slate-9)); }
.men-v2__title-kind { font-size: 13px; color: rgb(var(--slate-9)); font-weight: 400; }
.men-v2__subtitle { margin: 4px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }

/* Body */
.men-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 18px;
}

.men-v2__section { display: flex; flex-direction: column; gap: 10px; }
.men-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: inline-flex; align-items: center; gap: 6px;
}
.men-v2__field-hint { font-weight: 400; font-size: 11px; color: rgb(var(--slate-9)); }

/* Chips In/Out + Status */
.men-v2__chips { display: flex; flex-wrap: wrap; gap: 6px; }
.men-v2__chip {
  display: inline-flex; align-items: center; gap: 5px;
  padding: 8px 16px;
  border-radius: 999px;
  font-size: 13px; font-weight: 500;
  cursor: pointer;
  border: 1px solid transparent;
  transition: background 0.12s ease, color 0.12s ease, border-color 0.12s ease;
}
.men-v2__chip--tone-emerald {
  background: rgba(16, 185, 129, 0.10);
  color: #047857;
  border-color: rgba(16, 185, 129, 0.28);
  &:hover { background: rgba(16, 185, 129, 0.18); }
}
.men-v2__chip--tone-ruby {
  background: rgba(220, 38, 38, 0.10);
  color: #b91c1c;
  border-color: rgba(220, 38, 38, 0.32);
  &:hover { background: rgba(220, 38, 38, 0.18); }
}
:root.dark .men-v2__chip--tone-emerald { background: rgba(16, 185, 129, 0.18); color: #6ee7b7; border-color: rgba(16, 185, 129, 0.4); }
:root.dark .men-v2__chip--tone-ruby    { background: rgba(220, 38, 38, 0.18); color: #fca5a5; border-color: rgba(220, 38, 38, 0.4); }
.men-v2__chip--active { color: #ffffff; border-color: transparent; }
.men-v2__chip--tone-emerald.men-v2__chip--active { background: #059669; &:hover { background: #047857; } }
.men-v2__chip--tone-ruby.men-v2__chip--active    { background: #dc2626; &:hover { background: #b91c1c; } }
:root.dark .men-v2__chip--active { color: #ffffff; }

/* Status chips (neutros — não color-encoded por direção) */
.men-v2__chip--status {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));
  border-color: rgb(var(--slate-5));
  &:hover { background: rgb(var(--slate-4)); color: rgb(var(--slate-12)); }
}
.men-v2__chip--status-active {
  background: rgb(var(--blue-9));
  color: #ffffff;
  border-color: rgb(var(--blue-9));
  &:hover { background: rgb(var(--blue-10)); }
}

/* Blocked state — Entrada pendente */
.men-v2__blocked {
  display: flex; gap: 12px;
  padding: 14px 16px;
  border-radius: 12px;
  background: rgba(245, 158, 11, 0.10);
  border: 1px solid rgba(245, 158, 11, 0.35);
  i { width: 20px; height: 20px; color: #d97706; flex-shrink: 0; margin-top: 2px; }
}
.men-v2__blocked-content {
  display: flex; flex-direction: column; gap: 8px;
  strong { color: rgb(var(--slate-12)); font-size: 14px; }
  p { margin: 0; font-size: 13px; color: rgb(var(--slate-11)); line-height: 1.5; }
  em { color: rgb(var(--slate-12)); font-style: normal; font-weight: 500; }
}
:root.dark .men-v2__blocked {
  background: rgba(245, 158, 11, 0.18);
  border-color: rgba(245, 158, 11, 0.4);
  i { color: #fcd34d; }
}

/* Grid */
.men-v2__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 640px) { .men-v2__grid { grid-template-columns: 1fr; } }
.men-v2__field { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.men-v2__field--full { grid-column: 1 / -1; }

/* Currency input */
.men-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.men-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.men-v2__currency-input {
  padding-left: 32px; text-align: right;
  font-variant-numeric: tabular-nums;
}

/* Summary */
.men-v2__summary {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 12px 14px;
  display: flex; flex-direction: column; gap: 8px;
}
.men-v2__summary-row {
  display: flex; justify-content: space-between; align-items: center;
  font-size: 14px;
  span { color: rgb(var(--slate-11)); font-weight: 500; }
}
.men-v2__summary-row--total {
  font-size: 16px;
  span { color: rgb(var(--slate-12)); font-weight: 600; }
  strong { font-size: 18px; font-weight: 700; font-variant-numeric: tabular-nums; }
}
.men-v2__summary-amount--in  { color: #047857; }
.men-v2__summary-amount--out { color: #b91c1c; }
:root.dark .men-v2__summary-amount--in  { color: #6ee7b7; }
:root.dark .men-v2__summary-amount--out { color: #fca5a5; }

.men-v2__warning {
  display: flex; align-items: center; gap: 6px;
  margin: 0; padding: 8px 10px;
  border-radius: 8px;
  background: rgba(245, 158, 11, 0.10);
  border-left: 3px solid #f59e0b;
  color: #b45309; font-size: 12.5px;
}
:root.dark .men-v2__warning { color: #fcd34d; background: rgba(245, 158, 11, 0.18); }

/* Forma de pagamento — provider hint à direita do badge no dropdown
   (canon V2 1.8.0.10, mesmo visual do ReceivePaymentModalV2). */
.men-v2__pm-provider-hint {
  margin-left: auto;
  display: inline-flex; align-items: center; gap: 4px;
  font-size: 11px; color: rgb(var(--slate-9));
  font-weight: 400;
}
.men-v2__pm-loading,
.men-v2__pm-empty {
  display: flex; align-items: center; gap: 6px;
  padding: 8px 10px;
  font-size: 12.5px; color: rgb(var(--slate-9));
  background: rgb(var(--slate-2));
  border: 1px dashed rgb(var(--slate-5));
  border-radius: 8px;
  em { color: rgb(var(--slate-11)); font-style: normal; font-weight: 500; }
}

/* Info-card "Conta destino: X · da forma · Alterar" — read-only quando a
   Forma escolhida tem default_bank_account_id. Reduz fricção (95% dos
   casos a conta é a default). Mesmo visual do ReceivePaymentModalV2 —
   padrão único pra todos os modais financeiros. */
.men-v2__bank-info {
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
.men-v2__bank-info-name {
  font-weight: 500;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  min-width: 0;
}
.men-v2__bank-info-tag {
  /* line-height: 1 + inline-flex força a altura do chip a ser ditada SÓ
     pelo font-size + padding (1 + 10.5 + 1 ≈ 12.5px). Sem isso, o chip
     herda o line-height do <label> pai (~1.5) e cresce ~5px a mais
     que o equivalente do ReceivePaymentModalV2 (que vive dentro de <div>). */
  display: inline-flex;
  align-items: center;
  line-height: 1;
  font-size: 10.5px;
  font-weight: 500;
  padding: 3px 6px;
  border-radius: 999px;
  background: rgb(var(--blue-4));
  color: rgb(var(--blue-11));
  text-transform: lowercase;
  letter-spacing: 0.01em;
  white-space: nowrap;
}
.men-v2__bank-info-edit {
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
  line-height: 1;
  cursor: pointer;
  transition: background 0.12s, border-color 0.12s;
  white-space: nowrap;

  &:hover {
    background: rgb(var(--blue-3));
    border-color: rgb(var(--blue-7));
  }
}

/* Footer */
.men-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
@media (max-width: 640px) {
  .men-v2__footer { flex-direction: column-reverse; }
  .men-v2__footer > * { width: 100%; }
}
</style>
