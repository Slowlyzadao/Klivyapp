<script setup>
/**
 * Lançamento manual avulso — canon F-25.
 *
 * Cria um Financial::Entry com `kind: 'manual_entry'`. NÃO vincula a
 * paciente nem a parcela — é movimentação livre que afeta saldo da conta
 * + DRE (se categoria informada).
 *
 * Use casos:
 *   • Aporte de sócio (entrada)
 *   • Compra avulsa (saída)
 *   • Multa/juros recebidos (entrada)
 *   • Reembolso pago avulso (saída)
 *
 * UI premium: chips In/Out coloridos, FormSelect, DatePickerBR, live formatter,
 * mobile fullscreen — mesmo padrão do ReceivePaymentModalV2.
 *
 * Props:
 *   - show: Boolean
 *   - direction: 'in' | 'out' | null (pré-seleciona; null = usuário escolhe)
 *
 * Eventos:
 *   - close
 *   - confirm: { entry } (objeto retornado pelo backend)
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
  // Pré-seleciona direção quando o caller já sabe (ex.: tela A Pagar abre
  // sempre com 'out'; A Receber com 'in'). Se null, mostra os 2 chips.
  direction: { type: String, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Estado do form
const dir = ref('in');
const amountStr = ref('');
const description = ref('');
const cashDate = ref(new Date().toISOString().slice(0, 10));
const competenceDate = ref('');
const bankAccountId = ref(null);
const categoryId = ref(null);
const paymentMethod = ref('pix');
const submitting = ref(false);

// Dados auxiliares
const bankAccounts = ref([]);
const categories = ref([]);

// Valores alinhados ao enum v2 (Installment/Expense/PaymentReceipt usam o
// mesmo `Installment::PAYMENT_METHODS`). Entry não valida payment_method
// (campo livre), mas mantemos os mesmos valores pra consistência visual
// entre as UIs e evitar confusão do usuário.
const PAYMENT_METHODS = [
  { value: 'pix',           label: 'PIX' },
  { value: 'dinheiro',      label: 'Dinheiro' },
  { value: 'credito',       label: 'Cartão de crédito' },
  { value: 'debito',        label: 'Cartão de débito' },
  { value: 'boleto',        label: 'Boleto' },
  { value: 'transferencia', label: 'Transferência' },
  { value: 'cheque',        label: 'Cheque' },
];

const bankAccountOptions = computed(() =>
  bankAccounts.value.map(b => ({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` })),
);

// Cor por tipo (espelha Badge global) — FormSelect renderiza bolinha + hint.
const CATEGORY_VISUAL = {
  receita:        { color: '#10b981', hint: 'Receita' },
  despesa_fixa:   { color: '#dc2626', hint: 'Despesa fixa' },
  custo_variavel: { color: '#f59e0b', hint: 'Custo variável' },
  outra_despesa:  { color: '#64748b', hint: 'Outra despesa' },
};

// Categorias filtradas pela direção (in → receita; out → despesas).
// Ajuda a evitar atribuição errada (despesa categorizada como receita no DRE).
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

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!dir.value) return false;
  if (!bankAccountId.value) return false;
  if (grossCents.value <= 0) return false;
  if (!description.value.trim()) return false;
  return true;
});

async function loadAux() {
  try {
    const [b, c] = await Promise.all([
      FinancialV2.bankAccounts.index({ active: 'true' }),
      FinancialV2.categories.index({ active: 'true' }),
    ]);
    bankAccounts.value = b?.data?.data || [];
    categories.value = c?.data?.data || [];
    if (bankAccounts.value.length === 1) bankAccountId.value = bankAccounts.value[0].id;
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[ManualEntryModalV2] loadAux error', err);
  }
}

function reset() {
  dir.value = props.direction || 'in';
  amountStr.value = '';
  description.value = '';
  cashDate.value = new Date().toISOString().slice(0, 10);
  competenceDate.value = '';
  categoryId.value = null;
  paymentMethod.value = 'pix';
  submitting.value = false;
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

// Quando muda direção, limpa categoria (a lista filtrada muda).
watch(dir, () => { categoryId.value = null; });

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

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      entry: {
        direction: dir.value,
        amount_cents: grossCents.value,
        description: description.value.trim(),
        cash_date: cashDate.value,
        competence_date: competenceDate.value || cashDate.value,
        financial_bank_account_id: bankAccountId.value,
        financial_dre_category_id: categoryId.value,
        payment_method: paymentMethod.value,
      },
    };
    const { data } = await FinancialV2.entries.create(payload);
    notifySuccess(
      dir.value === 'in'
        ? 'Entrada registrada no Fluxo de Caixa.'
        : 'Saída registrada no Fluxo de Caixa.',
    );
    emit('confirm', data);
    emit('close');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao registrar lançamento');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const isIn = computed(() => dir.value === 'in');
const titleText = computed(() => (isIn.value ? 'Nova entrada' : 'Nova saída'));
const titleIcon = computed(() => (isIn.value ? 'i-lucide-arrow-down-to-line' : 'i-lucide-arrow-up-from-line'));
const ctaColor = computed(() => (isIn.value ? 'teal' : 'ruby'));
const ctaLabel = computed(() => (isIn.value ? 'Registrar entrada' : 'Registrar saída'));
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="men-v2__backdrop"
      @click.self="close"
    >
      <div class="men-v2__modal" role="dialog" aria-modal="true">
        <!-- Header -->
        <header class="men-v2__header">
          <div class="men-v2__header-text">
            <h2 class="men-v2__title">
              <i :class="titleIcon" class="men-v2__title-icon" :class-active="isIn ? 'in' : 'out'" />
              {{ titleText }}
            </h2>
            <p class="men-v2__subtitle">
              Lançamento avulso no Fluxo de Caixa. Não vincula a paciente.
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
          <!-- Direção (chips In/Out) — só mostra se o caller não pré-selecionou -->
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

          <!-- Valor + descrição -->
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
                <span class="men-v2__field-label">Data do caixa *</span>
                <DatePickerBR v-model="cashDate" />
              </label>

              <label class="men-v2__field">
                <span class="men-v2__field-label">
                  Data de competência
                  <span class="men-v2__field-hint">(opcional — default = data do caixa)</span>
                </span>
                <DatePickerBR v-model="competenceDate" />
              </label>

              <label class="men-v2__field">
                <span class="men-v2__field-label">Conta *</span>
                <FormSelect
                  v-model="bankAccountId"
                  :options="bankAccountOptions"
                  placeholder="Selecione a conta"
                  searchable
                  auto-searchable
                />
              </label>

              <label class="men-v2__field">
                <span class="men-v2__field-label">
                  Categoria DRE
                  <span class="men-v2__field-hint">
                    ({{ isIn ? 'apenas receitas' : 'apenas despesas' }})
                  </span>
                </span>
                <FormSelect
                  v-model="categoryId"
                  :options="categoryOptions"
                  placeholder="Selecione a categoria"
                  searchable
                  auto-searchable
                  clearable
                />
              </label>

              <label class="men-v2__field">
                <span class="men-v2__field-label">Forma de pagamento</span>
                <FormSelect v-model="paymentMethod" :options="PAYMENT_METHODS" />
              </label>
            </div>
          </section>

          <!-- Resumo -->
          <section v-if="grossCents > 0" class="men-v2__summary">
            <div class="men-v2__summary-row men-v2__summary-row--total">
              <span>{{ isIn ? 'Total a creditar' : 'Total a debitar' }}</span>
              <strong :class="isIn ? 'men-v2__summary-amount--in' : 'men-v2__summary-amount--out'">
                {{ isIn ? '+' : '−' }} {{ centsToBRL(grossCents) }}
              </strong>
            </div>
            <p v-if="!categoryId" class="men-v2__warning">
              <i class="i-lucide-info w-3.5 h-3.5" />
              Sem categoria, este lançamento não aparece no DRE — só no Fluxo de Caixa.
              Você pode reclassificar depois pela tela "Sem categoria".
            </p>
          </section>
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

/* Chips In/Out */
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
