<script setup>
/**
 * Modal de criar/editar Despesa Fixa — wireframe Setup #7 (2026-05-23).
 *
 * Campos alinhados ao wireframe:
 *   Nome*, Categoria* (caminho hierárquico), Conta Débito*,
 *   Tipo de Valor* (combina variable_amount + auto_pay), Valor Padrão*,
 *   Frequência*, Dia Vencimento (1-31)*, Data Início*, Status.
 *
 * "Tipo de Valor" combina 2 flags do backend num único select:
 *   - "Fixo (aprova auto)"   → variable_amount=false, auto_pay=true
 *   - "Fixo (manual)"        → variable_amount=false, auto_pay=false
 *   - "Variável (manual)"    → variable_amount=true,  auto_pay=false
 * (variable=true + auto_pay=true não faz sentido — operador precisa editar valor)
 *
 * Vigência fim + Regra de competência ficam em "Avançado" colapsável.
 *
 * Canon §4.4: editar valor afeta APENAS competências futuras —
 * histórico em A Pagar permanece intacto.
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../../api/financialV2';

const props = defineProps({
  show: { type: Boolean, default: false },
  existingItem: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// ── Canon (model Financial::RecurringExpense) ────────────────────────
const FREQUENCY_OPTIONS = [
  { value: 'monthly',    label: 'Mensal' },
  { value: 'bimonthly',  label: 'Bimestral' },
  { value: 'quarterly',  label: 'Trimestral' },
  { value: 'semiannual', label: 'Semestral' },
  { value: 'annual',     label: 'Anual' },
];

const COMPETENCE_OPTIONS = [
  { value: 'same_month', label: 'Mês atual' },
  { value: 'next_month', label: 'Mês seguinte' },
  { value: 'prev_month', label: 'Mês anterior' },
];

const STATUS_OPTIONS = [
  { value: true,  label: 'Ativa' },
  { value: false, label: 'Inativa' },
];

// Tipo de Valor combina 2 flags do backend (variable_amount + auto_pay).
// Ver mapeamento em flagsForValueType() abaixo.
const VALUE_TYPE_OPTIONS = [
  { value: 'fixed_auto',     label: 'Fixo (aprova auto)' },
  { value: 'fixed_manual',   label: 'Fixo (aprova manual)' },
  { value: 'variable_manual', label: 'Variável (manual)' },
];

function flagsForValueType(type) {
  switch (type) {
    case 'fixed_auto':     return { variable_amount: false, auto_pay: true  };
    case 'fixed_manual':   return { variable_amount: false, auto_pay: false };
    case 'variable_manual': return { variable_amount: true,  auto_pay: false };
    default:               return { variable_amount: false, auto_pay: false };
  }
}

function valueTypeFromFlags(variable_amount, auto_pay) {
  if (variable_amount) return 'variable_manual';
  return auto_pay ? 'fixed_auto' : 'fixed_manual';
}

const form = ref(emptyForm());
const submitting = ref(false);
const categories = ref([]);
const bankAccounts = ref([]);

const isEdit = computed(() => !!props.existingItem);

function emptyForm() {
  return {
    name: '',
    financial_dre_category_id: null,
    financial_bank_account_id: null,
    amount_str: '0,00',
    value_type: 'fixed_auto',
    frequency: 'monthly',
    due_day: 5,
    competence_rule: 'same_month',
    start_date: new Date().toISOString().slice(0, 10),
    end_date: '',
    active: true,
  };
}

// Conversões
function centsToInputString(cents) {
  if (cents == null) return '0,00';
  return (cents / 100).toFixed(2).replace('.', ',');
}

function brlInputToCents(text) {
  if (!text) return 0;
  const normalized = String(text).trim().replace(/\./g, '').replace(',', '.');
  const f = parseFloat(normalized);
  return Number.isFinite(f) ? Math.round(f * 100) : 0;
}

function formatCurrencyInput(text) {
  if (!text) return '0,00';
  const digitsOnly = String(text).replace(/[^\d]/g, '');
  if (!digitsOnly) return '0,00';
  const cents = parseInt(digitsOnly, 10);
  const reais = Math.floor(cents / 100);
  const cs = (cents % 100).toString().padStart(2, '0');
  return reais.toLocaleString('pt-BR') + ',' + cs;
}

function onAmountInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value.amount_str = formatted;
  e.target.value = formatted;
}

// Carrega categorias DRE (filtrando só despesas-folha) + contas bancárias.
// Canon: kind aceita `outra_despesa` (default Klivy) e `despesa` (variante).
// Folhas (`has_children=false`) são as únicas onde se pode lançar — agregadores
// (L1 com filhos) servem só pra somatórios no DRE.
const DESPESA_KINDS = new Set(['outra_despesa', 'despesa']);

async function loadOptions() {
  try {
    const [catsRes, banksRes] = await Promise.all([
      FinancialV2.categories.index(),
      FinancialV2.bankAccounts.index({ active: 'true' }),
    ]);
    const allCats = catsRes?.data?.data || [];

    // Indexa por ID pra resolver `path` (string de IDs "/1/2/3") em nomes.
    const byId = new Map(allCats.map(c => [c.id, c]));

    // Constrói o "caminho ancestral" (sem o próprio nó) — usado como hint
    // visual à direita no FormSelect pra dar contexto de grupo/subgrupo.
    // Ex: pra "Salários e Ordenados" sob "Pessoal", retorna "Pessoal".
    // Pra L3 "Endodontia" sob "Procedimentos > Particulares", "Procedimentos › Particulares".
    function ancestorsLabel(cat) {
      const ids = (cat.path || '').split('/').filter(Boolean).map(Number);
      // Remove o último se é o próprio (o backend inclui self no path).
      const ancestorIds = ids.filter(id => id !== cat.id);
      const names = ancestorIds.map(id => byId.get(id)?.name).filter(Boolean);
      return names.join(' › ');
    }

    categories.value = allCats
      .filter(c => DESPESA_KINDS.has(c.kind) && !c.has_children && c.active !== false)
      .sort((a, b) => (a.path || '').localeCompare(b.path || ''))
      .map(c => ({
        value: c.id,
        // Label só o nome final (folha) — limpo e curto.
        label: c.name,
        // Hint = caminho hierárquico do GRUPO pai. FormSelect renderiza à
        // direita em cinza claro, dando separação visual clara entre folha
        // e contexto (L1 > L2 > L3 …).
        hint: ancestorsLabel(c) || 'Raiz',
      }));

    bankAccounts.value = (banksRes?.data?.data || []).map(b => ({
      value: b.id,
      label: b.name,
    }));
  } catch {
    categories.value = [];
    bankAccounts.value = [];
  }
}

onMounted(loadOptions);

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;
    if (isEdit.value && props.existingItem) {
      const r = props.existingItem;
      form.value = {
        name: r.name || '',
        financial_dre_category_id: r.category_id || null,
        financial_bank_account_id: r.bank_account_id || null,
        amount_str: centsToInputString(r.amount_cents),
        value_type: valueTypeFromFlags(r.variable_amount, r.auto_pay),
        frequency: r.frequency || 'monthly',
        due_day: r.due_day || 5,
        competence_rule: r.competence_rule || 'same_month',
        start_date: r.start_date || new Date().toISOString().slice(0, 10),
        end_date: r.end_date || '',
        active: r.active !== false,
      };
    } else {
      form.value = emptyForm();
    }
  },
  { immediate: true },
);

// Conta Débito agora é obrigatória (wireframe). Sem opção "Decidir ao pagar".
const bankOptions = computed(() => bankAccounts.value);

const isVariable = computed(() => form.value.value_type === 'variable_manual');

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.name?.trim()) return false;
  if (!form.value.financial_dre_category_id) return false;
  if (!form.value.financial_bank_account_id) return false;
  if (!form.value.frequency) return false;
  if (!form.value.due_day || form.value.due_day < 1 || form.value.due_day > 31) return false;
  if (!form.value.start_date) return false;
  if (!isVariable.value && brlInputToCents(form.value.amount_str) <= 0) return false;
  return true;
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const flags = flagsForValueType(form.value.value_type);
    const payload = {
      recurring_expense: {
        name: form.value.name.trim(),
        financial_dre_category_id: form.value.financial_dre_category_id,
        financial_bank_account_id: form.value.financial_bank_account_id,
        amount_cents: flags.variable_amount ? 0 : brlInputToCents(form.value.amount_str),
        variable_amount: flags.variable_amount,
        auto_pay: flags.auto_pay,
        frequency: form.value.frequency,
        due_day: parseInt(form.value.due_day, 10),
        competence_rule: form.value.competence_rule,
        start_date: form.value.start_date,
        end_date: form.value.end_date || null,
        active: form.value.active,
      },
    };
    if (isEdit.value) {
      await FinancialV2.recurringExpenses.update(props.existingItem.id, payload);
      notifySuccess('Despesa atualizada. Próximas competências usarão os novos valores.');
    } else {
      await FinancialV2.recurringExpenses.create(payload);
      notifySuccess('Despesa fixa cadastrada. Cron irá gerar as próximas em A Pagar.');
    }
    emit('confirm');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ')
      || err?.response?.data?.message
      || 'Erro ao salvar');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const titleText = computed(() => isEdit.value ? `Editar — ${props.existingItem?.name}` : 'Nova Despesa Fixa');
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="rem-v2__backdrop">
      <div class="rem-v2__modal" role="dialog" aria-modal="true">
        <header class="rem-v2__header">
          <h2 class="rem-v2__title">
            <i class="i-lucide-repeat rem-v2__title-icon" />
            {{ titleText }}
          </h2>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="rem-v2__body">
          <div class="rem-v2__row">
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Nome <span class="rem-v2__required">*</span></span>
              <input
                v-model="form.name"
                type="text"
                class="finv2-input"
                placeholder="Ex.: Aluguel da Clínica"
                maxlength="200"
              />
            </label>
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Categoria <span class="rem-v2__required">*</span></span>
              <FormSelect
                v-model="form.financial_dre_category_id"
                :options="categories"
                placeholder="Selecione uma categoria"
                auto-searchable
              />
            </label>
          </div>

          <div class="rem-v2__row">
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Conta Débito <span class="rem-v2__required">*</span></span>
              <FormSelect
                v-model="form.financial_bank_account_id"
                :options="bankOptions"
                placeholder="Selecione a conta"
              />
            </label>
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Tipo de Valor</span>
              <FormSelect v-model="form.value_type" :options="VALUE_TYPE_OPTIONS" />
            </label>
          </div>

          <div class="rem-v2__row">
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">
                Valor Padrão <span v-if="!isVariable" class="rem-v2__required">*</span>
              </span>
              <div class="rem-v2__currency-wrap">
                <span class="rem-v2__currency-prefix">R$</span>
                <input
                  :value="form.amount_str"
                  type="text"
                  inputmode="numeric"
                  class="finv2-input rem-v2__currency-input"
                  placeholder="0,00"
                  :disabled="isVariable"
                  @input="onAmountInput"
                />
              </div>
              <span v-if="isVariable" class="rem-v2__field-hint-mini">
                Operador edita ao pagar (variável)
              </span>
            </label>
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Frequência <span class="rem-v2__required">*</span></span>
              <FormSelect v-model="form.frequency" :options="FREQUENCY_OPTIONS" />
            </label>
          </div>

          <div class="rem-v2__row">
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Dia Vencimento (1-31) <span class="rem-v2__required">*</span></span>
              <input v-model.number="form.due_day" type="number" min="1" max="31" class="finv2-input" />
            </label>
            <label class="rem-v2__field">
              <span class="rem-v2__field-label">Data Início <span class="rem-v2__required">*</span></span>
              <DatePickerBR v-model="form.start_date" :clearable="false" placeholder="DD/MM/AAAA" />
            </label>
          </div>

          <label class="rem-v2__field">
            <span class="rem-v2__field-label">Status</span>
            <FormSelect v-model="form.active" :options="STATUS_OPTIONS" />
          </label>

          <details class="rem-v2__details">
            <summary>Avançado (vigência fim + regra de competência)</summary>
            <div class="rem-v2__details-content">
              <label class="rem-v2__field">
                <span class="rem-v2__field-label">Vigência fim (opcional)</span>
                <DatePickerBR v-model="form.end_date" :min="form.start_date || null" placeholder="Em branco = indeterminada" />
              </label>
              <label class="rem-v2__field">
                <span class="rem-v2__field-label">Regra de competência</span>
                <FormSelect v-model="form.competence_rule" :options="COMPETENCE_OPTIONS" />
                <span class="rem-v2__field-hint-mini">
                  Quando a despesa entra no DRE: mês atual / seguinte / anterior do vencimento.
                </span>
              </label>
            </div>
          </details>
        </div>

        <footer class="rem-v2__footer">
          <BeclinicButton variant="ghost" color="slate" label="Cancelar" :disabled="submitting" @click="close" />
          <BeclinicButton
            variant="solid"
            color="blue"
            icon="i-lucide-check"
            :label="isEdit ? 'Salvar alterações' : 'Salvar'"
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
.rem-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .rem-v2__backdrop { align-items: center; padding: 16px; }
}

.rem-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .rem-v2__modal {
    width: min(580px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.rem-v2__header {
  display: flex; justify-content: space-between; align-items: center;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.rem-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.rem-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--blue-9)); }

.rem-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.rem-v2__row {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }
}

.rem-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.rem-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.rem-v2__required { color: rgb(var(--ruby-9)); }
.rem-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-weight: 400;
}

.rem-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.rem-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.rem-v2__currency-input {
  padding-left: 32px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

.rem-v2__checks-row {
  display: flex;
  padding: 8px 12px;
  background: rgb(var(--slate-2));
  border-radius: 8px;
  border-left: 3px solid rgb(var(--amber-7));
}

.rem-v2__details {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  summary {
    padding: 10px 14px;
    cursor: pointer;
    font-size: 12px;
    color: rgb(var(--slate-11));
    user-select: none;
    &:hover { color: rgb(var(--slate-12)); }
  }
}
.rem-v2__details-content {
  padding: 0 14px 14px;
  display: flex; flex-direction: column; gap: 12px;
}

.rem-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
