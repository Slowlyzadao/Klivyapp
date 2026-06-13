<script setup>
/**
 * Aba "Metas de Receita" — wireframe Setup #8 (2026-05-23).
 *
 * Tabela 9 colunas: NOME, TIPO (badge), PERÍODO, MEDIR, MÍNIMA, PRINCIPAL,
 * DESAFIO, ATUAL (+ progresso %), STATUS, AÇÕES (Encerrar).
 *
 * Canon §4.5:
 *   - 3 tiers (Mínima/Principal/Desafio) — visão clara de bater/superar
 *   - Tipos: Total (clínica) | Por Categoria | Por Agente
 *   - Métrica: Valor em R$ ou Quantidade
 *   - ATUAL recalculado on-the-fly por SUM/COUNT de Entry no período
 *   - "Encerrar" inativa (active=false) — preserva histórico
 */
import { ref, computed, onMounted } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import ConfirmDangerModalV2 from '../ConfirmDangerModalV2.vue';
import FinancialV2 from '../../api/financialV2';
import RevenueGoalFormModalV2 from './RevenueGoalFormModalV2.vue';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const goals = ref([]);
const loading = ref(false);
const errorState = ref(null);

const showFormModal = ref(false);
const editingGoal = ref(null);

const showEndModal = ref(false);
const goalToEnd = ref(null);
const ending = ref(false);

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const { data } = await FinancialV2.revenueGoals.index();
    goals.value = data?.data || [];
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar metas';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// ── Formatadores ─────────────────────────────────────────────────────
function centsToBRL(cents) {
  if (cents == null) return '—';
  return 'R$ ' + (cents / 100).toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}

function formatQty(n) {
  if (n == null) return '—';
  return n.toLocaleString('pt-BR');
}

function formatDate(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

function periodLabel(g) {
  return `${formatDate(g.start_date)} → ${formatDate(g.end_date)}`;
}

const KIND_LABEL = {
  total:         'TOTAL',
  por_categoria: 'POR CATEGORIA',
  por_agente:    'POR AGENTE',
};

const KIND_CLASS = {
  total:         'kind--total',
  por_categoria: 'kind--cat',
  por_agente:    'kind--agente',
};

function metricLabel(g) {
  return g.metric === 'count' ? 'Quantidade' : 'Valor em R$';
}

function tierValue(g, tier) {
  if (g.metric === 'count') return formatQty(g[`${tier}_qty`]);
  return centsToBRL(g[`${tier}_cents`]);
}

function actualLabel(g) {
  if (g.metric === 'count') return formatQty(g.actual_value);
  return centsToBRL(g.actual_value);
}

function progressLabel(g) {
  if (g.progress_percent == null) return '—';
  return `${Math.round(g.progress_percent)}%`;
}

function progressClass(g) {
  const p = g.progress_percent;
  if (p == null) return '';
  if (p >= 100) return 'progress--ok';
  if (p >= 60)  return 'progress--mid';
  return 'progress--low';
}

// ── Ações ─────────────────────────────────────────────────────────────
function openModalForNew() {
  editingGoal.value = null;
  showFormModal.value = true;
}

function openModalForEdit(goal) {
  editingGoal.value = goal;
  showFormModal.value = true;
}

function onGoalSaved() {
  showFormModal.value = false;
  load();
}

function startEnd(goal) {
  goalToEnd.value = goal;
  showEndModal.value = true;
}

async function confirmEnd() {
  const goal = goalToEnd.value;
  if (!goal) return;
  ending.value = true;
  try {
    await FinancialV2.revenueGoals.destroy(goal.id);
    notifySuccess('Meta encerrada. Histórico preservado.');
    showEndModal.value = false;
    goalToEnd.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.message || 'Erro ao encerrar meta');
  } finally {
    ending.value = false;
  }
}

const sortedGoals = computed(() => {
  return [...goals.value].sort((a, b) => {
    if (a.active !== b.active) return a.active ? -1 : 1;
    return new Date(b.start_date) - new Date(a.start_date);
  });
});
</script>

<template>
  <div class="goal-tab">
    <header class="goal-tab__header">
      <div>
        <h2 class="goal-tab__title">Metas de Receita</h2>
        <p class="goal-tab__subtitle">Setup #8 · Total / Por Categoria / Por Agente</p>
      </div>
      <BeclinicButton
        variant="solid"
        color="blue"
        icon="i-lucide-plus"
        label="Nova Meta"
        class="finv2-btn-icon-only-mobile"
        @click="openModalForNew"
      />
    </header>

    <!-- Loading -->
    <div v-if="loading && goals.length === 0" class="goal-tab__state">
      <div class="goal-tab__spinner" />
      <span>Carregando metas...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="goal-tab__state goal-tab__state--error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="goals.length === 0" class="goal-tab__state goal-tab__state--empty">
      <i class="i-lucide-target" />
      <h3>Nenhuma meta cadastrada</h3>
      <p>Crie metas Total/Por Categoria/Por Agente com 3 tiers (Mínima/Principal/Desafio) e acompanhe o progresso real ao longo do período.</p>
      <BeclinicButton variant="solid" color="blue" icon="i-lucide-plus" label="Adicionar primeira" @click="openModalForNew" />
    </div>

    <!-- Tabela -->
    <div v-else class="goal-tab__table-wrap">
      <table class="goal-tab__table">
        <thead>
          <tr>
            <th class="goal-tab__th-name">NOME</th>
            <th class="goal-tab__th-kind">TIPO</th>
            <th class="goal-tab__th-period">PERÍODO</th>
            <th class="goal-tab__th-metric">MEDIR</th>
            <th class="goal-tab__th-tier">MÍNIMA</th>
            <th class="goal-tab__th-tier">PRINCIPAL</th>
            <th class="goal-tab__th-tier">DESAFIO</th>
            <th class="goal-tab__th-actual">ATUAL</th>
            <th class="goal-tab__th-status">STATUS</th>
            <th class="goal-tab__th-actions"></th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="g in sortedGoals" :key="g.id" :class="{ 'goal-tab__row--inactive': !g.active }">
            <td class="goal-tab__td-name">
              <strong>{{ g.name }}</strong>
            </td>
            <td class="goal-tab__td-kind">
              <span class="goal-tab__kind-badge" :class="KIND_CLASS[g.kind]">{{ KIND_LABEL[g.kind] }}</span>
              <div v-if="g.kind === 'por_categoria' && g.category" class="goal-tab__kind-sub">{{ g.category.name }}</div>
              <div v-else-if="g.kind === 'por_agente' && g.professional" class="goal-tab__kind-sub">{{ g.professional.name }}</div>
            </td>
            <td class="goal-tab__td-period">{{ periodLabel(g) }}</td>
            <td class="goal-tab__td-metric">{{ metricLabel(g) }}</td>
            <td class="goal-tab__td-tier">{{ tierValue(g, 'min_target') }}</td>
            <td class="goal-tab__td-tier goal-tab__td-tier--principal">{{ tierValue(g, 'target') }}</td>
            <td class="goal-tab__td-tier">{{ tierValue(g, 'stretch_target') }}</td>
            <td class="goal-tab__td-actual">
              <div class="goal-tab__actual-value">{{ actualLabel(g) }}</div>
              <div class="goal-tab__progress" :class="progressClass(g)">{{ progressLabel(g) }}</div>
            </td>
            <td class="goal-tab__td-status">
              <span class="goal-tab__status" :class="g.active ? 'goal-tab__status--ok' : 'goal-tab__status--inactive'">
                {{ g.active ? 'ATIVA' : 'ENCERRADA' }}
              </span>
            </td>
            <td class="goal-tab__td-actions">
              <BeclinicButton size="sm" variant="ghost" color="slate" label="Editar" @click="openModalForEdit(g)" />
              <BeclinicButton v-if="g.active" size="sm" variant="ghost" color="slate" label="Encerrar" @click="startEnd(g)" />
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <RevenueGoalFormModalV2
      v-if="showFormModal"
      :show="showFormModal"
      :existing-goal="editingGoal"
      @close="showFormModal = false"
      @confirm="onGoalSaved"
    />

    <ConfirmDangerModalV2
      v-if="showEndModal"
      :show="showEndModal"
      title="Encerrar meta?"
      confirm-label="Sim, encerrar"
      tone="warn"
      :loading="ending"
      @close="showEndModal = false; goalToEnd = null"
      @confirm="confirmEnd"
    >
      A meta <strong>{{ goalToEnd?.name }}</strong> será marcada como <em>Encerrada</em>.
      <br>
      Histórico permanece — você ainda consegue ver na lista filtrando por encerradas.
    </ConfirmDangerModalV2>
  </div>
</template>

<style scoped lang="scss">
.goal-tab { color: rgb(var(--slate-12)); }

.goal-tab__header {
  display: flex; justify-content: space-between; align-items: flex-start;
  gap: 16px; margin-bottom: 20px;
  padding-bottom: 16px; border-bottom: 1px solid rgb(var(--slate-4));
}
.goal-tab__title { margin: 0 0 4px; font-size: 22px; font-weight: 700; }
.goal-tab__subtitle { margin: 0; font-size: 13px; color: rgb(var(--slate-10)); }

/* ── States ──────────────────────────────────────────────── */
.goal-tab__state {
  display: flex; align-items: center; justify-content: center;
  padding: 60px 24px; text-align: center;
  color: rgb(var(--slate-9)); font-size: 14px; gap: 12px;
}
.goal-tab__state--empty, .goal-tab__state--error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.goal-tab__state--error { color: rgb(var(--ruby-10)); }

.goal-tab__spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── Table ───────────────────────────────────────────────── */
.goal-tab__table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.goal-tab__table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 1100px;

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
      &.goal-tab__row--inactive { opacity: 0.55; }
    }
    td { padding: 12px; vertical-align: middle; }
  }
}

.goal-tab__th-name,   .goal-tab__td-name   { min-width: 180px; }
.goal-tab__th-kind,   .goal-tab__td-kind   { width: 150px; }
.goal-tab__th-period, .goal-tab__td-period { min-width: 200px; color: rgb(var(--slate-10)); font-size: 12px; }
.goal-tab__th-metric, .goal-tab__td-metric { width: 110px; color: rgb(var(--slate-10)); }
.goal-tab__th-tier,   .goal-tab__td-tier   {
  width: 110px; text-align: right; font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-11));
}
.goal-tab__td-tier--principal {
  color: rgb(var(--slate-12)); font-weight: 600;
}
.goal-tab__th-actual, .goal-tab__td-actual {
  width: 130px; text-align: right; font-variant-numeric: tabular-nums;
}
.goal-tab__th-status, .goal-tab__td-status { width: 100px; white-space: nowrap; }
.goal-tab__th-actions, .goal-tab__td-actions { width: 1%; white-space: nowrap; text-align: right; }

.goal-tab__kind-badge {
  display: inline-block;
  padding: 2px 7px;
  border-radius: 5px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.05em;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));

  &.kind--total  { background: rgba(59, 130, 246, 0.15);  color: rgb(var(--blue-11)); }
  &.kind--cat    { background: rgba(16, 185, 129, 0.15);  color: rgb(var(--emerald-11)); }
  &.kind--agente { background: rgba(139, 92, 246, 0.15);  color: rgb(var(--violet-11)); }
}
.goal-tab__kind-sub {
  margin-top: 4px;
  font-size: 11px;
  color: rgb(var(--slate-10));
}

.goal-tab__actual-value {
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.goal-tab__progress {
  margin-top: 2px;
  display: inline-block;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.04em;

  &.progress--ok  { background: rgba(16, 185, 129, 0.18); color: rgb(var(--emerald-11)); }
  &.progress--mid { background: rgba(245, 158, 11, 0.18); color: rgb(var(--amber-11)); }
  &.progress--low { background: rgba(244, 63, 94, 0.18);  color: rgb(var(--ruby-11)); }
}

.goal-tab__status {
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
