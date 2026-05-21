<script setup>
/**
 * Reclassificação em massa — canon F-28.
 *
 * Lista todos os Financial::Entry sem categoria e permite atribuir uma
 * categoria a vários de uma vez. Caminho rápido pra zerar o aviso "X sem
 * categoria" do DRE quando há muitos lançamentos legados/herdados sem
 * classificação.
 *
 * UI premium:
 *   • Listagem agrupada por direção (entradas vs saídas) — facilita
 *     atribuir categoria correta (receita vs despesa).
 *   • Bulk action com preview antes de aplicar.
 *   • Filtros: paciente, data, busca por descrição.
 *   • Mobile responsive.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import FinSearchInput from '../components/FinSearchInput.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const entries = ref([]);
const meta = ref({});
const categories = ref([]);
const selected = ref({});
const targetCategoryId = ref(null);
const loading = ref(false);
const applying = ref(false);
const filters = ref({
  direction: '',
  q: '',
  from: '',
  to: '',
});
const currentPage = ref(1);
const perPage = ref(25);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const DIRECTION_CHIPS = [
  { key: 'all', label: 'Todos',   tone: 'blue',    direction: '' },
  { key: 'in',  label: 'Entradas', tone: 'emerald', direction: 'in' },
  { key: 'out', label: 'Saídas',   tone: 'ruby',    direction: 'out' },
];

const activeChip = computed(
  () => DIRECTION_CHIPS.find(c => c.direction === filters.value.direction) || DIRECTION_CHIPS[0]
);

// Cor por tipo de categoria — espelha STATUS_BADGE do Badge global.
// FormSelect aceita `color` (renderiza como bolinha) e `hint` (texto secundário).
const KIND_VISUAL = {
  receita:        { color: '#10b981', hint: 'Receita' },
  despesa_fixa:   { color: '#dc2626', hint: 'Despesa fixa' },
  custo_variavel: { color: '#f59e0b', hint: 'Custo variável' },
  outra_despesa:  { color: '#64748b', hint: 'Outra despesa' },
};

// Categorias filtradas pela direção selecionada (igual ManualEntryModal):
// se filtrando entradas, só receitas; se saídas, só despesas; se "todos",
// mostra todas (operador escolhe ad-hoc).
const categoryOptions = computed(() => {
  let allowedKinds;
  if (filters.value.direction === 'in') {
    allowedKinds = ['receita'];
  } else if (filters.value.direction === 'out') {
    allowedKinds = ['despesa_fixa', 'custo_variavel', 'outra_despesa'];
  } else {
    allowedKinds = ['receita', 'despesa_fixa', 'custo_variavel', 'outra_despesa'];
  }
  return categories.value
    .filter(c => allowedKinds.includes(c.kind) && c.active)
    .map(c => {
      const v = KIND_VISUAL[c.kind] || { color: '#94a3b8', hint: c.kind };
      return {
        value: c.id,
        label: c.name,
        // FormSelect renderiza bolinha colorida + hint cinza ao lado.
        color: v.color,
        hint: v.hint,
      };
    });
});

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

const selectedIds = computed(() => Object.keys(selected.value).filter(k => selected.value[k]).map(Number));
const selectedCount = computed(() => selectedIds.value.length);

const hasFilter = computed(() =>
  filters.value.q || filters.value.from || filters.value.to || filters.value.direction
);

async function load() {
  loading.value = true;
  try {
    const params = {
      uncategorized: 'true',
      page: currentPage.value,
      per_page: perPage.value,
    };
    if (filters.value.direction) params.direction = filters.value.direction;
    if (filters.value.q) params.q = filters.value.q;
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;

    const { data } = await FinancialV2.entries.index(params);
    entries.value = data?.data || [];
    meta.value = data?.meta || {};
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[ReclassifyV2] load error', err);
    notifyError('Falha ao carregar lançamentos sem categoria');
  } finally {
    loading.value = false;
  }
}

async function loadCategories() {
  try {
    const { data } = await FinancialV2.categories.index({ active: 'true' });
    categories.value = data?.data || [];
  } catch {
    categories.value = [];
  }
}

watch(filters, () => {
  currentPage.value = 1;
  selected.value = {};
  load();
}, { deep: true });

watch([currentPage, perPage], load);

onMounted(() => {
  load();
  loadCategories();
});

function toggleAll(value) {
  if (value) {
    entries.value.forEach(e => { selected.value[e.id] = true; });
  } else {
    selected.value = {};
  }
}

const allSelected = computed(() =>
  entries.value.length > 0 && entries.value.every(e => selected.value[e.id])
);

async function applyReclassify() {
  if (!targetCategoryId.value) {
    notifyError('Selecione uma categoria pra atribuir.');
    return;
  }
  if (selectedIds.value.length === 0) {
    notifyError('Selecione ao menos 1 lançamento.');
    return;
  }
  applying.value = true;
  try {
    const { data } = await FinancialV2.entries.bulkReclassify({
      entry_ids: selectedIds.value,
      category_id: targetCategoryId.value,
    });
    notifySuccess(`${data.updated} lançamento(s) reclassificado(s).`);
    selected.value = {};
    targetCategoryId.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao reclassificar');
  } finally {
    applying.value = false;
  }
}

function clearDates() {
  filters.value.from = '';
  filters.value.to = '';
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Reclassificar lançamentos</h1>
        <p class="finv2-page__subtitle">
          Lançamentos sem categoria caem na linha "Sem categoria" do DRE.
          Atribua categorias específicas aqui em massa pra detalhar o relatório
          por receita/despesa (canon F-28).
        </p>
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- KPI / progress -->
      <div class="rcl-v2__kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger"><i class="i-lucide-alert-circle w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Sem categoria</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ meta.total || 0 }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--positive"><i class="i-lucide-trending-up w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total entradas</span>
            <strong class="finv2-kpi__value finv2-kpi__value--positive">
              {{ centsToBRL(meta.total_in_cents || 0) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger"><i class="i-lucide-trending-down w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total saídas</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ centsToBRL(meta.total_out_cents || 0) }}
            </strong>
          </div>
        </div>
      </div>

      <!-- Filtros -->
      <div class="rcl-v2__filters">
        <div class="finv2-chips" role="tablist">
          <button
            v-for="chip in DIRECTION_CHIPS"
            :key="chip.key"
            type="button"
            class="finv2-chip"
            :class="[`finv2-chip--tone-${chip.tone}`, { 'finv2-chip--active': activeChip.key === chip.key }]"
            @click="filters.direction = chip.direction"
          >
            <span>{{ chip.label }}</span>
          </button>
        </div>
        <div class="rcl-v2__inputs">
          <FinSearchInput
            v-model="filters.q"
            placeholder="Buscar descrição…"
            class="rcl-v2__input--grow"
          />
          <div class="finv2-input-wrap finv2-input-wrap--date">
            <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
          </div>
          <div class="finv2-input-wrap finv2-input-wrap--date">
            <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
          </div>
          <button v-if="hasFilter" type="button" class="rcl-v2__clear" @click="clearDates">
            <i class="i-lucide-x w-3.5 h-3.5" /> Limpar
          </button>
        </div>
      </div>

      <!-- Bulk action bar -->
      <div v-if="selectedCount > 0" class="rcl-v2__bulk-bar">
        <div class="rcl-v2__bulk-info">
          <i class="i-lucide-check-square w-4 h-4" />
          <span>
            <strong>{{ selectedCount }}</strong>
            {{ selectedCount === 1 ? 'lançamento selecionado' : 'lançamentos selecionados' }}
          </span>
        </div>
        <div class="rcl-v2__bulk-form">
          <FormSelect
            v-model="targetCategoryId"
            :options="categoryOptions"
            placeholder="Atribuir categoria…"
            searchable
            auto-searchable
          />
          <BeclinicButton
            variant="solid"
            color="teal"
            icon="i-lucide-check"
            label="Aplicar"
            :is-loading="applying"
            :disabled="!targetCategoryId || applying"
            @click="applyReclassify"
          />
        </div>
      </div>

      <!-- Tabela -->
      <div class="finv2-table-wrap finv2-hide-mobile">
        <table class="finv2-table">
          <thead>
            <tr>
              <th class="rcl-v2__th-checkbox">
                <Checkbox
                  :model-value="allSelected"
                  :disabled="entries.length === 0"
                  aria-label="Selecionar todos"
                  @update:model-value="toggleAll"
                />
              </th>
              <th>Descrição</th>
              <th>Tipo</th>
              <th>Data</th>
              <th class="finv2-table__th-num">Valor</th>
              <th>Conta</th>
              <th>Paciente</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="7">
                <div class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
              </td>
            </tr>
            <tr v-else-if="entries.length === 0">
              <td colspan="7">
                <div class="finv2-state">
                  <div class="finv2-state__icon-wrap"><i class="i-lucide-check-check w-7 h-7" /></div>
                  <p class="finv2-state__title">Nenhum lançamento sem categoria</p>
                  <p class="finv2-state__hint">DRE limpo — todos os lançamentos estão classificados.</p>
                </div>
              </td>
            </tr>
            <tr
              v-for="e in entries"
              v-else
              :key="e.id"
              :class="{ 'rcl-v2__row--selected': selected[e.id] }"
            >
              <td class="rcl-v2__td-checkbox">
                <Checkbox v-model="selected[e.id]" aria-label="Selecionar lançamento" />
              </td>
              <td>
                <strong>{{ e.description || '—' }}</strong>
              </td>
              <td>
                <Badge
                  :label="e.direction === 'in' ? 'Entrada' : 'Saída'"
                  :color="e.direction === 'in' ? 'emerald' : 'ruby'"
                  :icon="e.direction === 'in' ? 'i-lucide-arrow-down-to-line' : 'i-lucide-arrow-up-from-line'"
                  size="xs"
                />
              </td>
              <td class="finv2-table__td-date">{{ formatDateBR(e.cash_date) }}</td>
              <td
                class="finv2-table__td-num finv2-table__td-num--strong"
                :class="e.direction === 'in' ? 'rcl-v2__amount--in' : 'rcl-v2__amount--out'"
              >
                {{ e.direction === 'in' ? '+' : '−' }} {{ centsToBRL(e.amount_cents) }}
              </td>
              <td class="finv2-table__td-muted">{{ e.bank_account?.name || '—' }}</td>
              <td>
                <ProfessionalChip
                  v-if="e.patient?.name"
                  :name="e.patient.name"
                  :avatar-url="e.patient.avatar_url || ''"
                  size="sm"
                />
                <span v-else class="finv2-table__td-muted">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Mobile: cards -->
      <div class="finv2-cards finv2-show-mobile">
        <div v-if="loading" class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
        <div v-else-if="entries.length === 0" class="finv2-state">
          <div class="finv2-state__icon-wrap"><i class="i-lucide-check-check w-7 h-7" /></div>
          <p class="finv2-state__title">Tudo classificado</p>
        </div>
        <article
          v-for="e in entries"
          v-else
          :key="`m-${e.id}`"
          class="finv2-card rcl-v2__card"
          :class="{ 'rcl-v2__card--selected': selected[e.id] }"
        >
          <div class="rcl-v2__card-row">
            <Checkbox v-model="selected[e.id]" aria-label="Selecionar lançamento" />
            <div class="rcl-v2__card-info">
              <strong>{{ e.description || '—' }}</strong>
              <span class="rcl-v2__card-meta">
                {{ formatDateBR(e.cash_date) }} · {{ e.bank_account?.name || '—' }}
                <template v-if="e.patient?.name"> · {{ e.patient.name }}</template>
              </span>
            </div>
            <Badge
              :label="e.direction === 'in' ? 'Entrada' : 'Saída'"
              :color="e.direction === 'in' ? 'emerald' : 'ruby'"
              size="xs"
            />
          </div>
          <div
            class="rcl-v2__card-amount"
            :class="e.direction === 'in' ? 'rcl-v2__amount--in' : 'rcl-v2__amount--out'"
          >
            {{ e.direction === 'in' ? '+' : '−' }} {{ centsToBRL(e.amount_cents) }}
          </div>
        </article>
      </div>

      <Pagination
        v-model:current-page="currentPage"
        v-model:per-page="perPage"
        :total-count="meta.total || 0"
        item-label="lançamentos"
      />
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Layout, KPIs, table, chips e estados vêm do _layout.scss global. */

.rcl-v2__kpis {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}
@media (max-width: 720px) { .rcl-v2__kpis { grid-template-columns: 1fr; } }

.rcl-v2__filters { display: flex; flex-direction: column; gap: 12px; }
.rcl-v2__inputs {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr auto;
  gap: 8px;
  align-items: center;
}
@media (max-width: 800px) {
  .rcl-v2__inputs { grid-template-columns: 1fr 1fr; }
  .rcl-v2__input--grow { grid-column: 1 / -1; }
}
.rcl-v2__clear {
  display: inline-flex; align-items: center; gap: 4px;
  background: transparent;
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-9));
  font-size: 12px; cursor: pointer;
  padding: 9px 12px; border-radius: 8px;
  &:hover { color: rgb(var(--slate-12)); border-color: rgb(var(--slate-7)); }
}

/* Bulk action bar — fica sticky no topo do body quando há seleção */
.rcl-v2__bulk-bar {
  position: sticky;
  top: 80px; /* abaixo do header sticky */
  z-index: 5;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  padding: 12px 14px;
  background: rgba(37, 99, 235, 0.08);
  border: 1px solid rgba(37, 99, 235, 0.32);
  border-radius: 12px;
  flex-wrap: wrap;
  backdrop-filter: blur(4px);
}
:root.dark .rcl-v2__bulk-bar { background: rgba(59, 130, 246, 0.15); border-color: rgba(59, 130, 246, 0.4); }
.rcl-v2__bulk-info {
  display: inline-flex; align-items: center; gap: 8px;
  font-size: 13px; color: rgb(var(--slate-12));
  i { color: rgb(var(--blue-9)); }
  strong { font-weight: 700; font-variant-numeric: tabular-nums; }
}
.rcl-v2__bulk-form {
  display: flex; align-items: center; gap: 8px;
  flex: 1; min-width: 280px;
  max-width: 480px;
  > :first-child { flex: 1; min-width: 0; }
}
@media (max-width: 640px) {
  .rcl-v2__bulk-bar { flex-direction: column; align-items: stretch; }
  .rcl-v2__bulk-form { max-width: 100%; }
}

/* Tabela */
.rcl-v2__th-checkbox, .rcl-v2__td-checkbox { width: 36px; }
.rcl-v2__row--selected { background: rgba(59, 130, 246, 0.08) !important; }
.rcl-v2__amount--in,  .rcl-v2__amount--in strong  { color: #047857; }
.rcl-v2__amount--out, .rcl-v2__amount--out strong { color: #b91c1c; }
:root.dark .rcl-v2__amount--in,  :root.dark .rcl-v2__amount--in strong  { color: #6ee7b7; }
:root.dark .rcl-v2__amount--out, :root.dark .rcl-v2__amount--out strong { color: #fca5a5; }

/* Cards mobile */
.rcl-v2__card { gap: 10px; }
.rcl-v2__card--selected { border-color: rgb(var(--blue-8)); background: rgba(59, 130, 246, 0.06); }
.rcl-v2__card-row { display: flex; align-items: flex-start; gap: 10px; }
.rcl-v2__card-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.rcl-v2__card-meta { font-size: 11.5px; color: rgb(var(--slate-9)); }
.rcl-v2__card-amount {
  font-size: 16px; font-weight: 600;
  font-variant-numeric: tabular-nums;
  text-align: right;
}
</style>
