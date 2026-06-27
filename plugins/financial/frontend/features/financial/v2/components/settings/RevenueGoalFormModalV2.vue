<script setup>
/**
 * Modal de criar/editar Meta de Receita — wireframe Setup #8 (2026-05-23).
 *
 * 10 campos do wireframe:
 *   Nome*, Tipo* (Total/Por Categoria/Por Agente),
 *   Categoria (se Por Categoria), Profissional (se Por Agente),
 *   O que medir* (Valor R$ / Quantidade),
 *   Data Início*, Data Fim*,
 *   Meta Mínima*, Meta Principal*, Meta Desafio,
 *   Status.
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import FinancialV2 from '../../api/financialV2';
import AgentsAPI from 'dashboard/api/agents';

const props = defineProps({
  show: { type: Boolean, default: false },
  existingGoal: { type: Object, default: null },
});

const emit = defineEmits(['close', 'confirm']);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const KIND_OPTIONS = [
  { value: 'total',         label: 'Total (clínica)' },
  { value: 'por_categoria', label: 'Por Categoria' },
  { value: 'por_agente',    label: 'Por Agente' },
];

const METRIC_OPTIONS = [
  { value: 'currency', label: 'Valor em R$' },
  { value: 'count',    label: 'Quantidade' },
];

const STATUS_OPTIONS = [
  { value: true,  label: 'Ativa' },
  { value: false, label: 'Encerrada' },
];

const form = ref(emptyForm());
const submitting = ref(false);
const categories = ref([]);
const agents = ref([]);

const isEdit = computed(() => !!props.existingGoal);

function emptyForm() {
  const today = new Date().toISOString().slice(0, 10);
  return {
    name: '',
    kind: 'total',
    metric: 'currency',
    financial_dre_category_id: null,
    professional_id: null,
    start_date: today,
    end_date: '',
    min_target_str: '',
    target_str: '',
    stretch_target_str: '',
    min_target_qty: null,
    target_qty: null,
    stretch_target_qty: null,
    active: true,
  };
}

// Conversões
function centsToInputString(cents) {
  if (cents == null) return '';
  return (cents / 100).toFixed(2).replace('.', ',');
}

function brlInputToCents(text) {
  if (!text) return null;
  const normalized = String(text).trim().replace(/\./g, '').replace(',', '.');
  const f = parseFloat(normalized);
  return Number.isFinite(f) ? Math.round(f * 100) : null;
}

function formatCurrencyInput(text) {
  if (!text) return '';
  const digitsOnly = String(text).replace(/[^\d]/g, '');
  if (!digitsOnly) return '';
  const cents = parseInt(digitsOnly, 10);
  const reais = Math.floor(cents / 100);
  const cs = (cents % 100).toString().padStart(2, '0');
  return reais.toLocaleString('pt-BR') + ',' + cs;
}

function onCurrencyInput(field, e) {
  const formatted = formatCurrencyInput(e.target.value);
  form.value[field] = formatted;
  e.target.value = formatted;
}

async function loadOptions() {
  try {
    const [catsRes, agentsRes] = await Promise.all([
      FinancialV2.categories.index(),
      AgentsAPI.get(),
    ]);
    const allCats = catsRes?.data?.data || [];
    const byId = new Map(allCats.map(c => [c.id, c]));
    function ancestorsLabel(cat) {
      const ids = (cat.path || '').split('/').filter(Boolean).map(Number);
      const ancestorIds = ids.filter(id => id !== cat.id);
      return ancestorIds.map(id => byId.get(id)?.name).filter(Boolean).join(' › ');
    }
    // Apenas categorias de receita-folha pra fins de meta
    categories.value = allCats
      .filter(c => c.kind === 'receita' && !c.has_children && c.active !== false)
      .sort((a, b) => (a.path || '').localeCompare(b.path || ''))
      .map(c => ({ value: c.id, label: c.name, hint: ancestorsLabel(c) || 'Raiz' }));

    agents.value = (agentsRes?.data || []).map(a => ({
      value: a.id,
      label: a.name,
    }));
  } catch {
    categories.value = [];
    agents.value = [];
  }
}

onMounted(loadOptions);

watch(
  () => props.show,
  (val) => {
    if (!val) return;
    submitting.value = false;
    if (isEdit.value && props.existingGoal) {
      const g = props.existingGoal;
      form.value = {
        name: g.name || '',
        kind: g.kind || 'total',
        metric: g.metric || 'currency',
        financial_dre_category_id: g.category_id || null,
        professional_id: g.professional_id || null,
        start_date: g.start_date || new Date().toISOString().slice(0, 10),
        end_date: g.end_date || '',
        min_target_str:     centsToInputString(g.min_target_cents),
        target_str:         centsToInputString(g.target_cents),
        stretch_target_str: centsToInputString(g.stretch_target_cents),
        min_target_qty: g.min_target_qty,
        target_qty: g.target_qty,
        stretch_target_qty: g.stretch_target_qty,
        active: g.active !== false,
      };
    } else {
      form.value = emptyForm();
    }
  },
  { immediate: true },
);

const isCurrency = computed(() => form.value.metric === 'currency');
const showCategory = computed(() => form.value.kind === 'por_categoria');
const showAgent    = computed(() => form.value.kind === 'por_agente');

const validForSubmit = computed(() => {
  if (submitting.value) return false;
  if (!form.value.name?.trim()) return false;
  if (!form.value.kind || !form.value.metric) return false;
  if (showCategory.value && !form.value.financial_dre_category_id) return false;
  if (showAgent.value && !form.value.professional_id) return false;
  if (!form.value.start_date || !form.value.end_date) return false;
  if (form.value.end_date < form.value.start_date) return false;

  if (isCurrency.value) {
    if (!form.value.target_str || brlInputToCents(form.value.target_str) == null) return false;
  } else {
    if (form.value.target_qty == null || form.value.target_qty <= 0) return false;
  }
  return true;
});

async function submit() {
  if (!validForSubmit.value) return;
  submitting.value = true;
  try {
    const payload = {
      revenue_goal: {
        name: form.value.name.trim(),
        kind: form.value.kind,
        metric: form.value.metric,
        financial_dre_category_id: showCategory.value ? form.value.financial_dre_category_id : null,
        professional_id:            showAgent.value    ? form.value.professional_id : null,
        start_date: form.value.start_date,
        end_date: form.value.end_date,
        active: form.value.active,
      },
    };

    if (isCurrency.value) {
      payload.revenue_goal.min_target_cents     = brlInputToCents(form.value.min_target_str);
      payload.revenue_goal.target_cents         = brlInputToCents(form.value.target_str);
      payload.revenue_goal.stretch_target_cents = brlInputToCents(form.value.stretch_target_str);
      // Limpa colunas de qty pra evitar confusão
      payload.revenue_goal.min_target_qty = null;
      payload.revenue_goal.target_qty = null;
      payload.revenue_goal.stretch_target_qty = null;
    } else {
      payload.revenue_goal.min_target_qty     = form.value.min_target_qty;
      payload.revenue_goal.target_qty         = form.value.target_qty;
      payload.revenue_goal.stretch_target_qty = form.value.stretch_target_qty;
      payload.revenue_goal.min_target_cents = null;
      payload.revenue_goal.target_cents = null;
      payload.revenue_goal.stretch_target_cents = null;
    }

    if (isEdit.value) {
      await FinancialV2.revenueGoals.update(props.existingGoal.id, payload);
      notifySuccess('Meta atualizada.');
    } else {
      await FinancialV2.revenueGoals.create(payload);
      notifySuccess('Meta criada.');
    }
    emit('confirm');
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ')
      || err?.response?.data?.message
      || 'Erro ao salvar meta');
  } finally {
    submitting.value = false;
  }
}

function close() {
  if (submitting.value) return;
  emit('close');
}

const titleText = computed(() => isEdit.value ? `Editar — ${props.existingGoal?.name}` : 'Nova Meta');
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="rgm-v2__backdrop">
      <div class="rgm-v2__modal" role="dialog" aria-modal="true">
        <header class="rgm-v2__header">
          <h2 class="rgm-v2__title">
            <i class="i-lucide-target rgm-v2__title-icon" />
            {{ titleText }}
          </h2>
          <BeclinicButton size="sm" variant="ghost" color="slate" icon="i-lucide-x" :disabled="submitting" @click="close" />
        </header>

        <div class="rgm-v2__body">
          <div class="rgm-v2__row">
            <label class="rgm-v2__field">
              <span class="rgm-v2__field-label">Nome <span class="rgm-v2__required">*</span></span>
              <input v-model="form.name" type="text" class="finv2-input" placeholder="Ex.: Meta Mensal de Receita" maxlength="120" />
            </label>
            <label class="rgm-v2__field">
              <span class="rgm-v2__field-label">Tipo <span class="rgm-v2__required">*</span></span>
              <FormSelect v-model="form.kind" :options="KIND_OPTIONS" />
            </label>
          </div>

          <div class="rgm-v2__row">
            <label v-if="showCategory" class="rgm-v2__field">
              <span class="rgm-v2__field-label">Categoria <span class="rgm-v2__required">*</span></span>
              <FormSelect
                v-model="form.financial_dre_category_id"
                :options="categories"
                placeholder="Selecione uma categoria"
                auto-searchable
              />
            </label>
            <label v-else-if="showAgent" class="rgm-v2__field">
              <span class="rgm-v2__field-label">Profissional <span class="rgm-v2__required">*</span></span>
              <FormSelect
                v-model="form.professional_id"
                :options="agents"
                placeholder="Selecione um profissional"
                auto-searchable
              />
            </label>
            <div v-else class="rgm-v2__field rgm-v2__field--placeholder" />

            <label class="rgm-v2__field">
              <span class="rgm-v2__field-label">O que medir <span class="rgm-v2__required">*</span></span>
              <FormSelect v-model="form.metric" :options="METRIC_OPTIONS" />
            </label>
          </div>

          <div class="rgm-v2__row">
            <label class="rgm-v2__field">
              <span class="rgm-v2__field-label">Data Início <span class="rgm-v2__required">*</span></span>
              <DatePickerBR v-model="form.start_date" :clearable="false" placeholder="DD/MM/AAAA" />
            </label>
            <label class="rgm-v2__field">
              <span class="rgm-v2__field-label">Data Fim <span class="rgm-v2__required">*</span></span>
              <DatePickerBR v-model="form.end_date" :clearable="false" :min="form.start_date || null" placeholder="DD/MM/AAAA" />
            </label>
          </div>

          <!-- 3 tiers de meta -->
          <div class="rgm-v2__tiers">
            <h3 class="rgm-v2__tiers-title">Metas (3 tiers)</h3>
            <div class="rgm-v2__row rgm-v2__row--3">
              <label class="rgm-v2__field">
                <span class="rgm-v2__field-label">Meta Mínima</span>
                <div v-if="isCurrency" class="rgm-v2__currency-wrap">
                  <span class="rgm-v2__currency-prefix">R$</span>
                  <input
                    :value="form.min_target_str"
                    type="text"
                    inputmode="numeric"
                    class="finv2-input rgm-v2__currency-input"
                    placeholder="0,00"
                    @input="onCurrencyInput('min_target_str', $event)"
                  />
                </div>
                <input v-else v-model.number="form.min_target_qty" type="number" min="0" class="finv2-input" placeholder="0" />
              </label>
              <label class="rgm-v2__field">
                <span class="rgm-v2__field-label">Meta Principal <span class="rgm-v2__required">*</span></span>
                <div v-if="isCurrency" class="rgm-v2__currency-wrap">
                  <span class="rgm-v2__currency-prefix">R$</span>
                  <input
                    :value="form.target_str"
                    type="text"
                    inputmode="numeric"
                    class="finv2-input rgm-v2__currency-input"
                    placeholder="0,00"
                    @input="onCurrencyInput('target_str', $event)"
                  />
                </div>
                <input v-else v-model.number="form.target_qty" type="number" min="0" class="finv2-input" placeholder="0" />
              </label>
              <label class="rgm-v2__field">
                <span class="rgm-v2__field-label">Meta Desafio</span>
                <div v-if="isCurrency" class="rgm-v2__currency-wrap">
                  <span class="rgm-v2__currency-prefix">R$</span>
                  <input
                    :value="form.stretch_target_str"
                    type="text"
                    inputmode="numeric"
                    class="finv2-input rgm-v2__currency-input"
                    placeholder="0,00"
                    @input="onCurrencyInput('stretch_target_str', $event)"
                  />
                </div>
                <input v-else v-model.number="form.stretch_target_qty" type="number" min="0" class="finv2-input" placeholder="0" />
              </label>
            </div>
            <p class="rgm-v2__tiers-hint">
              Mínima = piso aceitável · Principal = meta esperada · Desafio = supera expectativa.
            </p>
          </div>

          <label class="rgm-v2__field">
            <span class="rgm-v2__field-label">Status</span>
            <FormSelect v-model="form.active" :options="STATUS_OPTIONS" />
          </label>
        </div>

        <footer class="rgm-v2__footer">
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
.rgm-v2__backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: stretch; justify-content: center;
  z-index: 9999;
}
@media (min-width: 640px) {
  .rgm-v2__backdrop { align-items: center; padding: 16px; }
}

.rgm-v2__modal {
  width: 100%; height: 100%;
  background: rgb(var(--slate-1));
  display: flex; flex-direction: column;
  overflow: hidden;
}
@media (min-width: 640px) {
  .rgm-v2__modal {
    width: min(640px, 100%);
    max-height: calc(100vh - 32px);
    height: auto;
    border: 1px solid rgb(var(--slate-4));
    border-radius: 16px;
    box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
  }
}

.rgm-v2__header {
  display: flex; justify-content: space-between; align-items: center;
  gap: 12px; padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.rgm-v2__title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.rgm-v2__title-icon { width: 18px; height: 18px; color: rgb(var(--blue-9)); }

.rgm-v2__body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}

.rgm-v2__row {
  display: grid; grid-template-columns: 1fr 1fr; gap: 12px;
  @media (max-width: 480px) { grid-template-columns: 1fr; }

  &--3 { grid-template-columns: 1fr 1fr 1fr; }
  @media (max-width: 480px) {
    &--3 { grid-template-columns: 1fr; }
  }
}

.rgm-v2__field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.rgm-v2__field--placeholder { /* mantém grid de 2 colunas mesmo sem campo */ }
.rgm-v2__field-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
  display: flex; align-items: center; gap: 4px;
}
.rgm-v2__required { color: rgb(var(--ruby-9)); }

.rgm-v2__currency-wrap { position: relative; display: flex; align-items: center; }
.rgm-v2__currency-prefix {
  position: absolute; left: 12px; top: 50%; transform: translateY(-50%);
  font-size: 13px; font-weight: 500; color: rgb(var(--slate-9));
  pointer-events: none; z-index: 1;
}
.rgm-v2__currency-input {
  padding-left: 32px;
  text-align: right;
  font-variant-numeric: tabular-nums;
}

/* Bloco dos 3 tiers */
.rgm-v2__tiers {
  padding: 14px;
  background: rgb(var(--slate-2));
  border-radius: 10px;
  border-left: 3px solid rgb(var(--blue-7));
  display: flex; flex-direction: column; gap: 10px;
}
.rgm-v2__tiers-title {
  margin: 0;
  font-size: 12px;
  font-weight: 600;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: rgb(var(--slate-10));
}
.rgm-v2__tiers-hint {
  margin: 0;
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-style: italic;
}

.rgm-v2__footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
}
</style>
