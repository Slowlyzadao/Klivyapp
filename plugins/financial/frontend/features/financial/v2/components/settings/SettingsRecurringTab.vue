<script setup>
/**
 * Aba "Despesas Fixas" — wireframe Setup #7 (2026-05-23).
 *
 * Modelo de despesas que se repetem (aluguel, sistema, internet, software, etc.).
 * Cron diário (`Financial::RecurringExpensesCronJob`) materializa as próximas
 * em A Pagar automaticamente — operador só configura aqui.
 *
 * Canon §4.4:
 *   - Editar valor afeta APENAS competências futuras (não recalcula histórico)
 *   - Inativar não exclui despesas já geradas
 *   - `variable_amount=true` → cron gera com `amount=0` (operador edita ao pagar)
 *
 * Tabela 8 colunas: NOME, CATEGORIA, FREQUÊNCIA (badge), DIA, VALOR, VIGÊNCIA, STATUS, AÇÕES.
 * KPIs: Despesas Ativas, Total Mensal Estimado, Total Anualizado.
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import ConfirmDangerModalV2 from '../ConfirmDangerModalV2.vue';
import FinancialV2 from '../../api/financialV2';
import RecurringExpenseFormModalV2 from './RecurringExpenseFormModalV2.vue';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const items = ref([]);
const summary = ref({ active_count: 0, total_count: 0, monthly_estimate_cents: 0, annual_estimate_cents: 0 });
const loading = ref(false);
const errorState = ref(null);

const showFormModal = ref(false);
const editingItem = ref(null);

const showDeleteModal = ref(false);
const itemToDelete = ref(null);
const deleting = ref(false);

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const { data } = await FinancialV2.recurringExpenses.index({ include_summary: 'true' });
    items.value = data?.data || [];
    summary.value = data?.summary || summary.value;
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar despesas fixas';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// ── Formatadores ─────────────────────────────────────────────────────
function centsToBRL(cents) {
  if (cents == null) return 'R$ 0,00';
  return 'R$ ' + (cents / 100).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function centsToBRLShort(cents) {
  if (cents == null) return 'R$ 0';
  const v = cents / 100;
  if (Math.abs(v) >= 1_000_000) return 'R$ ' + (v / 1_000_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + 'M';
  if (Math.abs(v) >= 1_000)     return 'R$ ' + (v / 1_000).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) + 'K';
  return 'R$ ' + v.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}

const FREQ_LABEL = {
  monthly:    'Mensal',
  bimonthly:  'Bimestral',
  quarterly:  'Trimestral',
  semiannual: 'Semestral',
  annual:     'Anual',
};

const FREQ_CLASS = {
  monthly:    'freq--monthly',
  bimonthly:  'freq--bimonthly',
  quarterly:  'freq--quarterly',
  semiannual: 'freq--semiannual',
  annual:     'freq--annual',
};

function freqLabel(f) { return FREQ_LABEL[f] || f; }
function freqClass(f) { return FREQ_CLASS[f] || ''; }

function formatDate(iso) {
  if (!iso) return null;
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

function vigencyLabel(item) {
  const from = formatDate(item.start_date);
  if (!from) return '—';
  if (!item.end_date) return `${from} → indeterminada`;
  return `${from} → ${formatDate(item.end_date)}`;
}

// ── Ações ─────────────────────────────────────────────────────────────
function openModalForNew() {
  editingItem.value = null;
  showFormModal.value = true;
}

function openModalForEdit(item) {
  editingItem.value = item;
  showFormModal.value = true;
}

function onItemSaved() {
  showFormModal.value = false;
  load();
}

function startInactivate(item) {
  itemToDelete.value = item;
  showDeleteModal.value = true;
}

async function confirmInactivate() {
  const item = itemToDelete.value;
  if (!item) return;
  deleting.value = true;
  try {
    await FinancialV2.recurringExpenses.destroy(item.id);
    notifySuccess('Despesa inativada. Próximas gerações são interrompidas.');
    showDeleteModal.value = false;
    itemToDelete.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao inativar');
  } finally {
    deleting.value = false;
  }
}

const sortedItems = computed(() => {
  return [...items.value].sort((a, b) => {
    if (a.active !== b.active) return a.active ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
});
</script>

<template>
  <div class="rec-tab">
    <header class="rec-tab__header">
      <div>
        <h2 class="rec-tab__title">Despesas Fixas</h2>
        <p class="rec-tab__subtitle">Setup #7 · Aluguel, sistema, internet — geração automática mensal</p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Adicionar"
        class="finv2-btn-icon-only-mobile"
        @click="openModalForNew"
      />
    </header>

    <!-- KPIs -->
    <div class="rec-tab__kpis">
      <div class="rec-tab__kpi rec-tab__kpi--accent-emerald">
        <span class="rec-tab__kpi-label">Despesas Ativas</span>
        <strong class="rec-tab__kpi-value">{{ summary.active_count }}</strong>
        <span class="rec-tab__kpi-hint">de {{ summary.total_count }} totais</span>
      </div>
      <div class="rec-tab__kpi rec-tab__kpi--accent-amber">
        <span class="rec-tab__kpi-label">Total Mensal Estimado</span>
        <strong class="rec-tab__kpi-value">{{ centsToBRLShort(summary.monthly_estimate_cents) }}</strong>
        <span class="rec-tab__kpi-hint">excluindo variáveis</span>
      </div>
      <div class="rec-tab__kpi rec-tab__kpi--accent-blue">
        <span class="rec-tab__kpi-label">Total Anualizado</span>
        <strong class="rec-tab__kpi-value">{{ centsToBRLShort(summary.annual_estimate_cents) }}</strong>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading && items.length === 0" class="rec-tab__state">
      <div class="rec-tab__spinner" />
      <span>Carregando despesas...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="rec-tab__state rec-tab__state--error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="items.length === 0" class="rec-tab__state rec-tab__state--empty">
      <i class="i-lucide-repeat" />
      <h3>Nenhuma despesa fixa cadastrada</h3>
      <p>Cadastre aluguel, sistema, internet, etc. A cada dia, um cron gera as próximas em <strong>A Pagar</strong>.</p>
      <BeclinicButton variant="solid" color="blue" icon="i-lucide-plus" label="Adicionar primeira" @click="openModalForNew" />
    </div>

    <!-- Tabela -->
    <div v-else class="rec-tab__table-wrap">
      <table class="rec-tab__table">
        <thead>
          <tr>
            <th class="rec-tab__th-name">NOME</th>
            <th class="rec-tab__th-cat">CATEGORIA</th>
            <th class="rec-tab__th-freq">FREQUÊNCIA</th>
            <th class="rec-tab__th-day">DIA</th>
            <th class="rec-tab__th-amount">VALOR</th>
            <th class="rec-tab__th-vig">VIGÊNCIA</th>
            <th class="rec-tab__th-status">STATUS</th>
            <th class="rec-tab__th-actions"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="r in sortedItems" :key="r.id" :class="{ 'rec-tab__row--inactive': !r.active }">
            <td class="rec-tab__td-name">
              <strong>{{ r.name }}</strong>
              <span v-if="r.auto_pay" class="rec-tab__autopay-chip">auto-pay</span>
            </td>
            <td class="rec-tab__td-cat">{{ r.category?.name || '—' }}</td>
            <td class="rec-tab__td-freq">
              <span class="rec-tab__freq-badge" :class="freqClass(r.frequency)">{{ freqLabel(r.frequency) }}</span>
            </td>
            <td class="rec-tab__td-day">{{ r.due_day }}</td>
            <td class="rec-tab__td-amount">
              {{ centsToBRL(r.amount_cents) }}
              <small v-if="r.variable_amount" class="rec-tab__variable">(variável)</small>
            </td>
            <td class="rec-tab__td-vig">{{ vigencyLabel(r) }}</td>
            <td class="rec-tab__td-status">
              <span class="rec-tab__status" :class="r.active ? 'rec-tab__status--ok' : 'rec-tab__status--inactive'">
                {{ r.active ? 'ATIVA' : 'INATIVA' }}
              </span>
            </td>
            <td class="rec-tab__td-actions">
              <BeclinicButton size="sm" variant="ghost" color="slate" label="Editar" @click="openModalForEdit(r)" />
              <BeclinicButton v-if="r.active" size="sm" variant="ghost" color="slate" label="Inativar" @click="startInactivate(r)" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <RecurringExpenseFormModalV2
      v-if="showFormModal"
      :show="showFormModal"
      :existing-item="editingItem"
      @close="showFormModal = false"
      @confirm="onItemSaved"
    />

    <ConfirmDangerModalV2
      v-if="showDeleteModal"
      :show="showDeleteModal"
      title="Inativar despesa fixa?"
      confirm-label="Sim, inativar"
      tone="warn"
      :loading="deleting"
      @close="showDeleteModal = false; itemToDelete = null"
      @confirm="confirmInactivate"
    >
      A despesa <strong>{{ itemToDelete?.name }}</strong> não será mais gerada
      automaticamente. Despesas já criadas em <em>A Pagar</em> permanecem intactas
      (canon §4.4).
    </ConfirmDangerModalV2>
  </div>
</template>

<style scoped lang="scss">
.rec-tab { color: rgb(var(--slate-12)); }

.rec-tab__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 16px; margin-bottom: 20px;
  padding-bottom: 16px; border-bottom: 1px solid rgb(var(--slate-4));
}
.rec-tab__title { margin: 0 0 4px; font-size: 22px; font-weight: 700; }
.rec-tab__subtitle { margin: 0; font-size: 13px; color: rgb(var(--slate-10)); }

/* ── KPIs ────────────────────────────────────────────────── */
.rec-tab__kpis {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 20px;
  @media (max-width: 720px) { grid-template-columns: 1fr; }
}

.rec-tab__kpi {
  position: relative;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 18px 16px 14px;
  display: flex; flex-direction: column; gap: 4px;
  overflow: hidden;

  &::before {
    content: '';
    position: absolute; top: 0; left: 0; right: 0; height: 3px;
    background: rgb(var(--slate-6));
  }
  &--accent-emerald::before { background: linear-gradient(90deg, rgb(var(--emerald-9)), rgb(var(--emerald-7))); }
  &--accent-amber::before   { background: linear-gradient(90deg, rgb(var(--amber-9)),   rgb(var(--amber-7))); }
  &--accent-blue::before    { background: linear-gradient(90deg, rgb(var(--blue-9)),    rgb(var(--blue-7))); }
}

.rec-tab__kpi-label {
  font-size: 10px; font-weight: 600; letter-spacing: 0.06em;
  text-transform: uppercase; color: rgb(var(--slate-9));
}
.rec-tab__kpi-value {
  font-size: 26px; font-weight: 700;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
}
.rec-tab__kpi-hint { font-size: 11px; color: rgb(var(--slate-9)); }

/* ── States ──────────────────────────────────────────────── */
.rec-tab__state {
  display: flex; align-items: center; justify-content: center;
  padding: 60px 24px; text-align: center;
  color: rgb(var(--slate-9));
  font-size: 14px; gap: 12px;
}
.rec-tab__state--empty, .rec-tab__state--error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.rec-tab__state--error { color: rgb(var(--ruby-10)); }

.rec-tab__spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── Table ───────────────────────────────────────────────── */
.rec-tab__table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.rec-tab__table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 880px;

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 10px 12px;
      text-align: left;
      font-size: 10px; font-weight: 600;
      text-transform: uppercase; letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
      border-bottom: 1px solid rgb(var(--slate-4));
      white-space: nowrap;
    }
  }
  tbody {
    tr {
      border-bottom: 1px solid rgb(var(--slate-3));
      transition: background-color .12s ease;
      &:last-child { border-bottom: 0; }
      &:hover { background: rgba(255, 255, 255, 0.02); }
      &.rec-tab__row--inactive { opacity: 0.55; }
    }
    td { padding: 12px; vertical-align: middle; }
  }
}

.rec-tab__th-name, .rec-tab__td-name { min-width: 200px; }
.rec-tab__th-cat,  .rec-tab__td-cat  { min-width: 160px; color: rgb(var(--slate-10)); }
.rec-tab__th-freq, .rec-tab__td-freq { width: 120px; }
.rec-tab__th-day,  .rec-tab__td-day  { width: 60px; text-align: right; font-variant-numeric: tabular-nums; color: rgb(var(--slate-10)); }
.rec-tab__th-amount, .rec-tab__td-amount {
  width: 140px; text-align: right; font-variant-numeric: tabular-nums;
  font-weight: 600; color: rgb(var(--slate-12));
}
.rec-tab__th-vig,  .rec-tab__td-vig  { min-width: 180px; color: rgb(var(--slate-10)); font-size: 12px; }
.rec-tab__th-status, .rec-tab__td-status { width: 90px; white-space: nowrap; }
.rec-tab__th-actions, .rec-tab__td-actions { width: 1%; white-space: nowrap; text-align: right; }

.rec-tab__autopay-chip {
  display: inline-block;
  margin-left: 8px;
  padding: 1px 6px;
  background: rgba(16, 185, 129, 0.15);
  color: rgb(var(--emerald-11));
  border-radius: 4px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;
}

.rec-tab__variable {
  display: block;
  margin-top: 2px;
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-style: italic;
  font-weight: 400;
}

.rec-tab__freq-badge {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 5px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.05em;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));

  &.freq--monthly    { background: rgba(59, 130, 246, 0.12);  color: rgb(var(--blue-11)); }
  &.freq--bimonthly  { background: rgba(14, 165, 233, 0.12);  color: rgb(var(--sky-11)); }
  &.freq--quarterly  { background: rgba(139, 92, 246, 0.12);  color: rgb(var(--violet-11)); }
  &.freq--semiannual { background: rgba(245, 158, 11, 0.12);  color: rgb(var(--amber-11)); }
  &.freq--annual     { background: rgba(16, 185, 129, 0.12);  color: rgb(var(--emerald-11)); }
}

.rec-tab__status {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.05em;

  &--ok       { background: rgba(16, 185, 129, 0.15); color: rgb(var(--emerald-11)); }
  &--inactive { background: rgba(100, 116, 139, 0.15); color: rgb(var(--slate-10)); }
}
</style>
