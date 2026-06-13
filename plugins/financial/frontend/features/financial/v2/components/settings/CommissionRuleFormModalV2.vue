<script setup>
/**
 * Modal de criar/editar Regra de Comissão — wireframe Setup #5 (2026-05-23).
 *
 * 10 campos do wireframe:
 *   Nome*, Profissional*, Papel* (DR/SDR/Comercial),
 *   Gatilho* (paciente_comparece/orcamento_aceito/profissional_realizou/pagamento_confirmado),
 *   Tipo* (Fixo R$ / Percentual), Valor*,
 *   Escopo (todos/por_procedimento/por_especialidade), Quando Pagar (fechamento_mes/imediato/no_recebimento),
 *   Vigência início*, Status.
 *
 * Campos legacy (base, deduct_mdr, deduct_lab, vigência fim) ficam em "Avançado"
 * (details/summary) pra não poluir UX padrão mas preservar funcionalidade
 * canon — comissão sobre RECEBIDO (não orçado), MDR e laboratório opcionais.
 *
 * Props: show, mode ('create'|'edit'), initial
 * Eventos: close, confirm
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import FinancialV2 from '../../api/financialV2';
import AgentsAPI from 'dashboard/api/agents';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' },
  initial: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// ── Canon (alinhado com model Financial::CommissionRule) ─────────────
const ROLE_OPTIONS = [
  { value: 'DR',        label: 'DR' },
  { value: 'SDR',       label: 'SDR' },
  { value: 'Comercial', label: 'Comercial' },
];

const TRIGGER_OPTIONS = [
  { value: 'paciente_comparece',     label: 'Paciente comparece' },
  { value: 'orcamento_aceito',       label: 'Orçamento aceito' },
  { value: 'profissional_realizou',  label: 'Profissional realizou' },
  { value: 'pagamento_confirmado',   label: 'Pagamento confirmado' },
];

// Tipo simplificado no wireframe (Fixo R$ / Percentual) → mapeia
// pra `kind` técnico do model.
const TYPE_OPTIONS = [
  { value: 'valor_fixo',       label: 'Fixo (R$)' },
  { value: 'percentual_geral', label: 'Percentual' },
];

const SCOPE_OPTIONS = [
  { value: 'todos',             label: 'Todos os eventos' },
  { value: 'por_procedimento',  label: 'Por procedimento' },
  { value: 'por_especialidade', label: 'Por especialidade' },
];

const PAY_WHEN_OPTIONS = [
  { value: 'fechamento_mes', label: 'Fechamento do Mês' },
  { value: 'imediato',       label: 'Imediato' },
  { value: 'no_recebimento', label: 'No Recebimento' },
];

const STATUS_OPTIONS = [
  { value: true,  label: 'Ativo' },
  { value: false, label: 'Inativo' },
];

const BASE_OPTIONS = [
  { value: 'recebido',           label: 'Recebido (canon)' },
  { value: 'bruto',              label: 'Bruto / orçado' },
  { value: 'recebido_menos_mdr', label: 'Recebido − MDR' },
  { value: 'recebido_menos_lab', label: 'Recebido − Lab' },
];

// ── Form state ───────────────────────────────────────────────────────
const form = ref(emptyForm());
const submitting = ref(false);
const agents = ref([]);

const isEdit = computed(() => props.mode === 'edit');

function emptyForm() {
  return {
    name: '',
    professional_id: null,
    role: 'DR',
    trigger_event: 'pagamento_confirmado',
    kind: 'percentual_geral',
    percent: '30',
    fixed_amount_str: '0,00',
    scope: 'todos',
    procedure_name: '',
    specialty: '',
    pay_when: 'fechamento_mes',
    valid_from: new Date().toISOString().slice(0, 10),
    valid_until: '',
    active: true,
    // Advanced
    base: 'recebido',
    deduct_mdr: false,
    deduct_lab: false,
  };
}

// Carrega lista de profissionais (User core da conta)
async function loadAgents() {
  try {
    const { data } = await AgentsAPI.get();
    agents.value = (data || []).map(a => ({
      value: a.id,
      label: a.name,
      avatar_url: a.thumbnail || a.avatar_url || '',
    }));
  } catch {
    agents.value = [];
  }
}

onMounted(loadAgents);

// Resetar form quando abre o modal
watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;
    if (isEdit.value && props.initial) {
      const r = props.initial;
      form.value = {
        name: r.name || '',
        professional_id: r.professional_id,
        role: r.role || 'DR',
        trigger_event: r.trigger_event || 'pagamento_confirmado',
        kind: r.kind === 'valor_fixo' ? 'valor_fixo' : 'percentual_geral',
        percent: r.percent_basis_points != null
          ? (r.percent_basis_points / 100).toString().replace('.', ',')
          : '',
        fixed_amount_str: r.fixed_amount_cents
          ? (r.fixed_amount_cents / 100).toFixed(2).replace('.', ',')
          : '0,00',
        scope: r.scope || 'todos',
        procedure_name: r.procedure_name || '',
        specialty: r.specialty || '',
        pay_when: r.pay_when || 'fechamento_mes',
        valid_from: r.valid_from || new Date().toISOString().slice(0, 10),
        valid_until: r.valid_until || '',
        active: r.active !== false,
        base: r.base || 'recebido',
        deduct_mdr: !!r.deduct_mdr,
        deduct_lab: !!r.deduct_lab,
      };
    } else {
      form.value = emptyForm();
    }
  },
  { immediate: true },
);

// Conversões
function parsePercent(text) {
  if (!text) return null;
  const normalized = String(text).trim().replace(/\./g, '').replace(',', '.');
  const f = parseFloat(normalized);
  return Number.isFinite(f) ? f : null;
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

function onFixedAmountInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value.fixed_amount_str = formatted;
  e.target.value = formatted;
}

const isPercent = computed(() => form.value.kind !== 'valor_fixo');

const showProcedureField = computed(() => form.value.scope === 'por_procedimento');
const showSpecialtyField = computed(() => form.value.scope === 'por_especialidade');

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.professional_id) return false;
  if (!form.value.trigger_event) return false;
  if (!form.value.valid_from) return false;
  if (isPercent.value) {
    const p = parsePercent(form.value.percent);
    if (p == null || p <= 0 || p > 100) return false;
  } else {
    const cents = brlInputToCents(form.value.fixed_amount_str);
    if (cents <= 0) return false;
  }
  if (form.value.scope === 'por_procedimento' && !form.value.procedure_name?.trim()) return false;
  if (form.value.scope === 'por_especialidade' && !form.value.specialty?.trim()) return false;
  return true;
});

// Quando muda o scope, espelha kind tecnicamente pra alinhar com canon.
// Wireframe simplifica em (Fixo/Percentual), mas backend tem 4 kinds —
// derivamos do scope quando é Percentual.
const derivedKind = computed(() => {
  if (form.value.kind === 'valor_fixo') return 'valor_fixo';
  if (form.value.scope === 'por_procedimento') return 'percentual_por_procedimento';
  if (form.value.scope === 'por_especialidade') return 'percentual_por_especialidade';
  return 'percentual_geral';
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      commission_rule: {
        name: form.value.name?.trim() || null,
        professional_id: form.value.professional_id,
        role: form.value.role,
        trigger_event: form.value.trigger_event,
        kind: derivedKind.value,
        scope: form.value.scope,
        pay_when: form.value.pay_when,
        valid_from: form.value.valid_from,
        valid_until: form.value.valid_until || null,
        active: form.value.active,
        base: form.value.base,
        deduct_mdr: form.value.deduct_mdr,
        deduct_lab: form.value.deduct_lab,
        procedure_name: form.value.scope === 'por_procedimento' ? form.value.procedure_name.trim() : null,
        specialty: form.value.scope === 'por_especialidade' ? form.value.specialty.trim() : null,
      },
    };

    if (isPercent.value) {
      const p = parsePercent(form.value.percent);
      payload.commission_rule.percent_basis_points = Math.round(p * 100);
    } else {
      payload.commission_rule.fixed_amount_cents = brlInputToCents(form.value.fixed_amount_str);
    }

    if (isEdit.value) {
      await FinancialV2.commissionRules.update(props.initial.id, payload);
      notifySuccess('Regra atualizada.');
    } else {
      await FinancialV2.commissionRules.create(payload);
      notifySuccess('Regra criada.');
    }
    emit('confirm');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ')
      || err?.response?.data?.message
      || 'Erro ao salvar regra');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const titleText = computed(() => isEdit.value ? 'Editar Regra de Comissão' : 'Nova Regra de Comissão');
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="crm-v2__backdrop">
      <div class="crm-v2__modal" role="dialog" aria-modal="true">
        <header class="crm-v2__header">
          <h2 class="crm-v2__title">
            <i class="i-lucide-percent crm-v2__title-icon" />
            {{ titleText }}
          </h2>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="crm-v2__body">
          <div class="crm-v2__row">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Nome da Regra <span class="crm-v2__required">*</span></span>
              <input
                v-model="form.name"
                type="text"
                class="finv2-input"
                placeholder="Ex.: Rafael Streit · DR Padrão"
                maxlength="120"
              />
            </label>
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Profissional <span class="crm-v2__required">*</span></span>
              <FormSelect
                v-model="form.professional_id"
                :options="agents"
                placeholder="Selecione um profissional"
                auto-searchable
              />
            </label>
          </div>

          <div class="crm-v2__row">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Papel <span class="crm-v2__required">*</span></span>
              <FormSelect v-model="form.role" :options="ROLE_OPTIONS" />
            </label>
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Gatilho <span class="crm-v2__required">*</span></span>
              <FormSelect v-model="form.trigger_event" :options="TRIGGER_OPTIONS" />
            </label>
          </div>

          <div class="crm-v2__row">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Tipo <span class="crm-v2__required">*</span></span>
              <FormSelect v-model="form.kind" :options="TYPE_OPTIONS" />
            </label>
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Valor <span class="crm-v2__required">*</span></span>
              <div v-if="isPercent" class="crm-v2__percent-wrap">
                <input
                  v-model="form.percent"
                  type="text"
                  inputmode="decimal"
                  class="finv2-input crm-v2__percent-input"
                  placeholder="30"
                />
                <span class="crm-v2__percent-suffix">%</span>
              </div>
              <div v-else class="crm-v2__currency-wrap">
                <span class="crm-v2__currency-prefix">R$</span>
                <input
                  :value="form.fixed_amount_str"
                  type="text"
                  inputmode="numeric"
                  class="finv2-input crm-v2__currency-input"
                  placeholder="0,00"
                  @input="onFixedAmountInput"
                />
              </div>
            </label>
          </div>

          <div class="crm-v2__row">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Escopo</span>
              <FormSelect v-model="form.scope" :options="SCOPE_OPTIONS" />
            </label>
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Quando Pagar</span>
              <FormSelect v-model="form.pay_when" :options="PAY_WHEN_OPTIONS" />
            </label>
          </div>

          <!-- Campo condicional: procedimento (quando scope = por_procedimento) -->
          <div v-if="showProcedureField" class="crm-v2__row crm-v2__row--single">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Nome do procedimento <span class="crm-v2__required">*</span></span>
              <input
                v-model="form.procedure_name"
                type="text"
                class="finv2-input"
                placeholder="Ex.: Endodontia, Implante"
                maxlength="200"
              />
            </label>
          </div>

          <!-- Campo condicional: especialidade (quando scope = por_especialidade) -->
          <div v-if="showSpecialtyField" class="crm-v2__row crm-v2__row--single">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Especialidade <span class="crm-v2__required">*</span></span>
              <input
                v-model="form.specialty"
                type="text"
                class="finv2-input"
                placeholder="Ex.: Ortodontia"
                maxlength="80"
              />
            </label>
          </div>

          <div class="crm-v2__row">
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Vigência início <span class="crm-v2__required">*</span></span>
              <DatePickerBR v-model="form.valid_from" :clearable="false" placeholder="DD/MM/AAAA" />
            </label>
            <label class="crm-v2__field">
              <span class="crm-v2__field-label">Status</span>
              <FormSelect v-model="form.active" :options="STATUS_OPTIONS" />
            </label>
          </div>

          <!-- Advanced: base + deduct + vigência fim (canon §4.3 estrito) -->
          <details class="crm-v2__details">
            <summary>Avançado (canon estrito: base / MDR / lab / vigência fim)</summary>
            <div class="crm-v2__details-content">
              <div class="crm-v2__row">
                <label class="crm-v2__field">
                  <span class="crm-v2__field-label">Base do cálculo</span>
                  <FormSelect v-model="form.base" :options="BASE_OPTIONS" />
                  <span class="crm-v2__field-hint-mini">Canon recomenda "Recebido" (não orçado).</span>
                </label>
                <label class="crm-v2__field">
                  <span class="crm-v2__field-label">Vigência fim (opcional)</span>
                  <DatePickerBR v-model="form.valid_until" placeholder="Em branco = indeterminada" :min="form.valid_from" />
                </label>
              </div>
              <div class="crm-v2__advanced-checks">
                <Checkbox v-model="form.deduct_mdr">
                  <span>Descontar <strong>MDR</strong> antes de calcular (cartão)</span>
                </Checkbox>
                <Checkbox v-model="form.deduct_lab">
                  <span>Descontar <strong>custo de laboratório</strong> antes de calcular</span>
                </Checkbox>
              </div>
            </div>
          </details>
        </div>

        <footer class="crm-v2__footer">
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
.crm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .crm-v2__backdrop { align-items: center; padding: 16px; }
}

.crm-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .crm-v2__modal {
    width: min(640px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.crm-v2__header {
  display: flex; justify-content: space-between; align-items: center;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.crm-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.crm-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--blue-9)); }

.crm-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.crm-v2__row {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }

  &--single { grid-template-columns: 1fr; }
}

.crm-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.crm-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.crm-v2__required { color: rgb(var(--ruby-9)); }
.crm-v2__field-hint-mini {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* Currency input (R$) */
.crm-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.crm-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.crm-v2__currency-input {
  padding-left: 32px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

/* Percent input (sufixo %) */
.crm-v2__percent-wrap { position: relative; display: flex; align-items: center; }
.crm-v2__percent-suffix {
  position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.crm-v2__percent-input {
  padding-right: 28px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

.crm-v2__details {
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
.crm-v2__details-content {
  padding: 0 14px 14px;
  display: flex; flex-direction: column; gap: 10px;
}
.crm-v2__advanced-checks {
  display: flex; flex-direction: column; gap: 8px;
  padding-top: 8px;
}

.crm-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
