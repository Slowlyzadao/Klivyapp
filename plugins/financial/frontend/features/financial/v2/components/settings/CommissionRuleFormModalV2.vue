<script setup>
/**
 * Modal de criar/editar regra de comissão (canon §4.3).
 *
 * Tipos suportados (model `Financial::CommissionRule`):
 *   • percentual_geral             — % sobre toda receita do profissional
 *   • percentual_por_procedimento  — % específico por procedimento (campo procedure_name)
 *   • percentual_por_especialidade — % por especialidade (campo specialty)
 *   • valor_fixo                   — R$ fixo por atendimento (fixed_amount_cents)
 *
 * Bases (sobre o que % incide):
 *   • bruto                — sobre o orçado (raro; canon recomenda RECEBIDO)
 *   • recebido             — sobre o que efetivamente entrou (default)
 *   • recebido_menos_mdr   — recebido descontando MDR de cartão
 *   • recebido_menos_lab   — recebido descontando custo de laboratório
 *
 * Vigência: valid_from obrigatório; valid_until opcional (null = indeterminada).
 *
 * Props:
 *   - show: Boolean
 *   - mode: 'create' | 'edit'
 *   - initial: object (regra existente quando mode=edit)
 *
 * Eventos:
 *   - close
 *   - confirm: { rule } (regra retornada pelo backend)
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import FinancialV2 from '../../api/financialV2';
import { brlInputToCents, centsToInputString, formatCurrencyInput } from '../../composables/useMoney';
import AgentsAPI from 'dashboard/api/agents';

const props = defineProps({
  show: { type: Boolean, default: false },
  mode: { type: String, default: 'create' }, // 'create' | 'edit'
  initial: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const submitting = ref(false);
const agents = ref([]);

const KIND_OPTIONS = [
  { value: 'percentual_geral',             label: '% geral (sobre toda receita)' },
  { value: 'percentual_por_procedimento',  label: '% por procedimento' },
  { value: 'percentual_por_especialidade', label: '% por especialidade' },
  { value: 'valor_fixo',                   label: 'Valor fixo (R$ por atendimento)' },
];

const BASE_OPTIONS = [
  { value: 'recebido',           label: 'Recebido (recomendado)' },
  { value: 'recebido_menos_mdr', label: 'Recebido − MDR (cartão)' },
  { value: 'recebido_menos_lab', label: 'Recebido − Laboratório' },
  { value: 'bruto',              label: 'Bruto (sobre o orçado — raro)' },
];

const form = ref({
  professional_id: null,
  kind: 'percentual_geral',
  base: 'recebido',
  percent: '', // string em "%" — convertido pra basis_points no submit
  fixed_amount_str: '', // string formatada de R$ pra valor_fixo
  procedure_name: '',
  specialty: '',
  deduct_mdr: false,
  deduct_lab: false,
  valid_from: new Date().toISOString().slice(0, 10),
  valid_until: '',
  active: true,
});

const agentOptions = computed(() => {
  const list = agents.value || [];
  return list
    .filter(a => a && a.id && (a.role === 'agent' || a.role === 'administrator' || !a.role))
    .map(a => ({
      value: a.id,
      label: a.name,
      hint: a.email,
    }));
});

const isValorFixo = computed(() => form.value.kind === 'valor_fixo');
const isPorProcedimento = computed(() => form.value.kind === 'percentual_por_procedimento');
const isPorEspecialidade = computed(() => form.value.kind === 'percentual_por_especialidade');

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.professional_id) return false;
  if (!form.value.valid_from) return false;
  if (isValorFixo.value) {
    return brlInputToCents(form.value.fixed_amount_str) > 0;
  }
  // Modos %: precisa de percent > 0
  const pctNum = parseFloat(String(form.value.percent).replace(',', '.'));
  if (!Number.isFinite(pctNum) || pctNum <= 0 || pctNum > 100) return false;
  if (isPorProcedimento.value && !form.value.procedure_name.trim()) return false;
  if (isPorEspecialidade.value && !form.value.specialty.trim()) return false;
  return true;
});

async function loadAgents() {
  try {
    const { data } = await AgentsAPI.get();
    agents.value = Array.isArray(data) ? data : (data?.data || []);
  } catch {
    agents.value = [];
  }
}

function reset() {
  if (props.mode === 'edit' && props.initial) {
    const r = props.initial;
    form.value = {
      professional_id: r.professional_id,
      kind: r.kind || 'percentual_geral',
      base: r.base || 'recebido',
      percent: r.percent_basis_points != null
        ? (r.percent_basis_points / 100).toString().replace('.', ',')
        : '',
      fixed_amount_str: r.fixed_amount_cents
        ? centsToInputString(r.fixed_amount_cents)
        : '',
      procedure_name: r.procedure_name || '',
      specialty: r.specialty || '',
      deduct_mdr: !!r.deduct_mdr,
      deduct_lab: !!r.deduct_lab,
      valid_from: r.valid_from || new Date().toISOString().slice(0, 10),
      valid_until: r.valid_until || '',
      active: r.active !== false,
    };
  } else {
    form.value = {
      professional_id: null,
      kind: 'percentual_geral',
      base: 'recebido',
      percent: '',
      fixed_amount_str: '',
      procedure_name: '',
      specialty: '',
      deduct_mdr: false,
      deduct_lab: false,
      valid_from: new Date().toISOString().slice(0, 10),
      valid_until: '',
      active: true,
    };
  }
  submitting.value = false;
}

watch(
  () => props.show,
  (val) => {
    if (val) {
      reset();
      loadAgents();
    }
  },
);

onMounted(() => {
  if (props.show) {
    reset();
    loadAgents();
  }
});

function onPercentInput(e) {
  // Aceita "12", "12,5", "12.5". Limita a 2 casas decimais.
  let v = String(e.target.value).replace(/[^\d.,]/g, '').replace(/\./g, ',');
  const parts = v.split(',');
  if (parts.length > 2) v = `${parts[0]},${parts.slice(1).join('')}`;
  if (parts[1]?.length > 2) v = `${parts[0]},${parts[1].slice(0, 2)}`;
  form.value.percent = v;
  e.target.value = v;
}

function onFixedAmountInput(e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value.fixed_amount_str = formatted;
  e.target.value = formatted;
}

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = buildPayload();
    let response;
    if (props.mode === 'edit' && props.initial?.id) {
      response = await FinancialV2.commissionRules.update(props.initial.id, { commission_rule: payload });
    } else {
      response = await FinancialV2.commissionRules.create({ commission_rule: payload });
    }
    notifySuccess(props.mode === 'edit' ? 'Regra atualizada.' : 'Regra criada.');
    emit('confirm', response.data);
    emit('close');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao salvar regra');
  } finally {
    submitting.value = false;
  }
}

function buildPayload() {
  const payload = {
    professional_id: form.value.professional_id,
    kind: form.value.kind,
    base: form.value.base,
    deduct_mdr: !!form.value.deduct_mdr,
    deduct_lab: !!form.value.deduct_lab,
    valid_from: form.value.valid_from,
    valid_until: form.value.valid_until || null,
    active: !!form.value.active,
    procedure_name: isPorProcedimento.value ? form.value.procedure_name.trim() : null,
    specialty: isPorEspecialidade.value ? form.value.specialty.trim() : null,
  };
  if (isValorFixo.value) {
    payload.fixed_amount_cents = brlInputToCents(form.value.fixed_amount_str);
    payload.percent_basis_points = null;
  } else {
    const pctNum = parseFloat(String(form.value.percent).replace(',', '.'));
    payload.percent_basis_points = Math.round(pctNum * 100);
    payload.fixed_amount_cents = null;
  }
  return payload;
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const titleText = computed(() => (props.mode === 'edit' ? 'Editar regra de comissão' : 'Nova regra de comissão'));
const ctaLabel = computed(() => (props.mode === 'edit' ? 'Salvar alterações' : 'Criar regra'));
</script>

<template>
  <Teleport to="body">
    <div
      v-if="show"
      class="cmrl-v2__backdrop"
      @click.self="close"
    >
      <div class="cmrl-v2__modal" role="dialog" aria-modal="true">
        <header class="cmrl-v2__header">
          <div>
            <h2 class="cmrl-v2__title">
              <i class="i-lucide-percent w-4 h-4" /> {{ titleText }}
            </h2>
            <p class="cmrl-v2__subtitle">
              Canon §4.3 — comissão sobre RECEBIDO (não sobre orçado), com opção
              de descontar MDR e laboratório.
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

        <div class="cmrl-v2__body">
          <!-- Profissional -->
          <label class="cmrl-v2__field cmrl-v2__field--full">
            <span class="cmrl-v2__field-label">Profissional *</span>
            <FormSelect
              v-model="form.professional_id"
              :options="agentOptions"
              placeholder="Selecione o profissional"
              searchable
              auto-searchable
              :disabled="mode === 'edit'"
            />
            <span v-if="mode === 'edit'" class="cmrl-v2__field-hint">
              Profissional não pode ser alterado após criação. Crie uma nova regra para outro profissional.
            </span>
          </label>

          <!-- Tipo + Base -->
          <div class="cmrl-v2__grid">
            <label class="cmrl-v2__field">
              <span class="cmrl-v2__field-label">Tipo *</span>
              <FormSelect v-model="form.kind" :options="KIND_OPTIONS" />
            </label>
            <label class="cmrl-v2__field">
              <span class="cmrl-v2__field-label">Base de cálculo *</span>
              <FormSelect v-model="form.base" :options="BASE_OPTIONS" />
            </label>
          </div>

          <!-- Procedure name (se kind=percentual_por_procedimento) -->
          <label v-if="isPorProcedimento" class="cmrl-v2__field cmrl-v2__field--full">
            <span class="cmrl-v2__field-label">Nome do procedimento *</span>
            <input
              v-model="form.procedure_name"
              type="text"
              class="finv2-input"
              placeholder="Ex.: Restauração, Implante"
            />
          </label>

          <!-- Specialty (se kind=percentual_por_especialidade) -->
          <label v-if="isPorEspecialidade" class="cmrl-v2__field cmrl-v2__field--full">
            <span class="cmrl-v2__field-label">Especialidade *</span>
            <input
              v-model="form.specialty"
              type="text"
              class="finv2-input"
              placeholder="Ex.: Endodontia, Ortodontia"
            />
          </label>

          <!-- Percentual ou Valor fixo -->
          <div class="cmrl-v2__grid">
            <label v-if="!isValorFixo" class="cmrl-v2__field">
              <span class="cmrl-v2__field-label">Percentual *</span>
              <div class="cmrl-v2__suffix-wrap">
                <input
                  :value="form.percent"
                  type="text"
                  inputmode="decimal"
                  class="finv2-input cmrl-v2__suffix-input"
                  placeholder="0,00"
                  @input="onPercentInput"
                />
                <span class="cmrl-v2__suffix-sign">%</span>
              </div>
            </label>
            <label v-else class="cmrl-v2__field">
              <span class="cmrl-v2__field-label">Valor fixo *</span>
              <div class="cmrl-v2__currency-wrap">
                <span class="cmrl-v2__currency-prefix">R$</span>
                <input
                  :value="form.fixed_amount_str"
                  type="text"
                  inputmode="numeric"
                  class="finv2-input cmrl-v2__currency-input"
                  placeholder="0,00"
                  @input="onFixedAmountInput"
                />
              </div>
            </label>

            <div class="cmrl-v2__field cmrl-v2__deductions">
              <span class="cmrl-v2__field-label">Deduções</span>
              <label class="cmrl-v2__check">
                <Checkbox v-model="form.deduct_mdr" />
                <span>Descontar MDR (taxa de cartão)</span>
              </label>
              <label class="cmrl-v2__check">
                <Checkbox v-model="form.deduct_lab" />
                <span>Descontar laboratório</span>
              </label>
            </div>
          </div>

          <!-- Vigência -->
          <div class="cmrl-v2__grid">
            <label class="cmrl-v2__field">
              <span class="cmrl-v2__field-label">Vigência início *</span>
              <DatePickerBR v-model="form.valid_from" />
            </label>
            <label class="cmrl-v2__field">
              <span class="cmrl-v2__field-label">
                Vigência fim
                <span class="cmrl-v2__field-hint">(opcional — vazio = indeterminada)</span>
              </span>
              <DatePickerBR v-model="form.valid_until" :min="form.valid_from || null" />
            </label>
          </div>

          <label class="cmrl-v2__check cmrl-v2__check--standalone">
            <Checkbox v-model="form.active" />
            <span>Regra ativa (desmarque pra desativar sem excluir)</span>
          </label>
        </div>

        <footer class="cmrl-v2__footer">
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
.cmrl-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999; padding: 0;
}
@media (min-width: 640px) {
  .cmrl-v2__backdrop { align-items: center; padding: 16px; }
}

.cmrl-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  border: 0; border-radius: 0;
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .cmrl-v2__modal {
    width: min(640px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.cmrl-v2__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.cmrl-v2__title {
  margin: 0; font-size: 17px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.cmrl-v2__subtitle { margin: 4px 0 0; font-size: 13px; color: rgb(var(--slate-9)); }

.cmrl-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.cmrl-v2__grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 640px) { .cmrl-v2__grid { grid-template-columns: 1fr; } }

.cmrl-v2__field { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.cmrl-v2__field--full { grid-column: 1 / -1; }
.cmrl-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: inline-flex; align-items: center; gap: 6px;
}
.cmrl-v2__field-hint { font-weight: 400; font-size: 11px; color: rgb(var(--slate-9)); }

.cmrl-v2__suffix-wrap { position: relative; display: flex; align-items: center; }
.cmrl-v2__suffix-sign {
  position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none;
}
.cmrl-v2__suffix-input { padding-right: 28px; text-align: right; font-variant-numeric: tabular-nums; }

.cmrl-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.cmrl-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.cmrl-v2__currency-input { padding-left: 32px; text-align: right; font-variant-numeric: tabular-nums; }

.cmrl-v2__deductions { gap: 6px; }
.cmrl-v2__check {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 13px; color: rgb(var(--slate-12));
  cursor: pointer; user-select: none;
}
.cmrl-v2__check--standalone {
  padding: 10px 12px;
  border-radius: 10px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
}

.cmrl-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
@media (max-width: 640px) {
  .cmrl-v2__footer { flex-direction: column-reverse; }
  .cmrl-v2__footer > * { width: 100%; }
}
</style>
