<script setup>
/**
 * Dashboard financeiro — v2 (wireframe 2026-05-23).
 *
 * Layout canon:
 *   1. Header: título, subtitle (período em formato BR), period selector
 *   2. 6 KPIs com barras coloridas no topo (Receita Mês / Despesas Mês /
 *      Margem Mês / Saldo Total Contas / A Receber 30d / A Pagar 30d)
 *   3. 4 charts em grid 2x2:
 *      - Receita vs Meta (barras mensais coloridas por % atingido)
 *      - Receita por Categoria (donut por kind de receita)
 *      - Receita vs Despesa (barras lado-a-lado últimos 6 meses)
 *      - Produção por Profissional (barras horizontais top 10)
 *   4. Tabela Top 10 Procedimentos
 *
 * Datas no subtitle ficam em DD/MM/YYYY (formato BR). As datas internas
 * (period.from / period.to) continuam ISO porque a API espera ISO.
 *
 * Endpoints:
 *   GET /financial/v2/reports/dashboard               → KPIs principais
 *   GET /financial/v2/reports/revenue_vs_goal         → chart Receita vs Meta
 *   GET /financial/v2/reports/revenue_composition    → chart Receita por Categoria
 *   GET /financial/v2/reports/cash_flow_chart         → chart Receita vs Despesa
 *   GET /financial/v2/reports/revenue_by_professional → chart Produção
 *   GET /financial/v2/reports/top_procedures          → tabela Top 10
 */
import { ref, onMounted, computed } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import RevenueVsGoalChart from '../components/charts/RevenueVsGoalChart.vue';
import RevenueCompositionChartV2 from '../components/charts/RevenueCompositionChartV2.vue';
import RevenueVsExpenseChart from '../components/charts/RevenueVsExpenseChart.vue';
import RevenueByProfessionalChartV2 from '../components/charts/RevenueByProfessionalChartV2.vue';
import '@plugins/financial/frontend/styles/financial.scss';

// Formato BR: 2026-05-23 → 23/05/2026
function toBR(isoDate) {
  if (!isoDate) return '';
  const [y, m, d] = isoDate.split('-');
  return `${d}/${m}/${y}`;
}

const PERIOD_TYPES = [
  { value: 'week',    label: 'Semana' },
  { value: 'month',   label: 'Mês' },
  { value: 'quarter', label: 'Trimestre' },
  { value: 'year',    label: 'Ano' },
  { value: 'all',     label: 'Todos' },
];

const periodType = ref('month');
const anchor = ref(new Date());
const period = computed(() => buildPeriod(periodType.value, anchor.value));

function buildPeriod(type, date) {
  const y = date.getFullYear();
  const m = date.getMonth();
  if (type === 'all') {
    return { from: '2010-01-01', to: new Date().toISOString().slice(0, 10), label: 'Todo o período' };
  }
  if (type === 'year') {
    return { from: `${y}-01-01`, to: `${y}-12-31`, label: String(y) };
  }
  if (type === 'quarter') {
    const q = Math.floor(m / 3);
    const first = `${y}-${String(q * 3 + 1).padStart(2, '0')}-01`;
    const last = new Date(y, (q + 1) * 3, 0).toISOString().slice(0, 10);
    return { from: first, to: last, label: `T${q + 1}/${y}` };
  }
  if (type === 'week') {
    const start = new Date(date);
    start.setDate(start.getDate() - start.getDay());
    const end = new Date(start);
    end.setDate(end.getDate() + 6);
    const fmt = d => `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}`;
    return {
      from: start.toISOString().slice(0, 10),
      to: end.toISOString().slice(0, 10),
      label: `${fmt(start)} – ${fmt(end)}/${end.getFullYear()}`,
    };
  }
  // month
  const first = `${y}-${String(m + 1).padStart(2, '0')}-01`;
  const last = new Date(y, m + 1, 0).toISOString().slice(0, 10);
  return { from: first, to: last, label: `${String(m + 1).padStart(2, '0')}/${y}` };
}

function shiftAnchor(direction) {
  const d = new Date(anchor.value);
  if (periodType.value === 'week')     d.setDate(d.getDate() + direction * 7);
  if (periodType.value === 'month')    d.setMonth(d.getMonth() + direction);
  if (periodType.value === 'quarter')  d.setMonth(d.getMonth() + direction * 3);
  if (periodType.value === 'year')     d.setFullYear(d.getFullYear() + direction);
  anchor.value = d;
}

// ── Dados ─────────────────────────────────────────────────────────────
const dashboardData = ref(null);
const revenueVsGoal = ref([]);
const topProcedures = ref([]);
const loading = ref(false);
const errorMessage = ref('');

async function load() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const [dash, rvg, topProcs] = await Promise.all([
      FinancialV2.reports.dashboard({ from: period.value.from, to: period.value.to }),
      FinancialV2.reports.revenueVsGoal({ months: 12 }),
      FinancialV2.reports.topProcedures({ from: period.value.from, to: period.value.to, limit: 10 }),
    ]);
    dashboardData.value = dash?.data || null;
    revenueVsGoal.value = rvg?.data?.months || [];
    topProcedures.value = topProcs?.data?.items || [];
  } catch (err) {
    errorMessage.value = err?.response?.data?.message || 'Erro ao carregar dashboard';
  } finally {
    loading.value = false;
  }
}

onMounted(load);

// Quando muda o período, recarrega
function applyPeriod(type) {
  periodType.value = type;
  load();
}

// ── KPIs derived ─────────────────────────────────────────────────────
const kpis = computed(() => {
  if (!dashboardData.value) return null;
  const m = dashboardData.value.month || {};
  const r = dashboardData.value.receivables || {};
  const p = dashboardData.value.payables || {};
  const c = dashboardData.value.cash || {};
  const goal = dashboardData.value.revenue_goal;

  const receita = m.receita_bruta_cents || 0;
  const despesa = m.despesa_cents || 0;
  const margem  = receita - despesa;
  const margemPct = receita > 0 ? ((margem / receita) * 100).toFixed(1) : null;

  return {
    receita: {
      value: receita,
      hint: goal?.goal_cents
        ? `${(goal.progress_percent || 0).toFixed(1)}% da meta ${centsToBRLShort(goal.goal_cents)}`
        : 'sem meta cadastrada',
    },
    despesa: {
      value: despesa,
      hint: m.despesa_recorrente_count
        ? `${m.despesa_recorrente_count} despesas fixas`
        : null,
    },
    margem: {
      value: margem,
      hint: margemPct != null ? `${margemPct}%` : null,
    },
    saldo: {
      value: c.estimated_total_cents || c.total_balance_cents || 0,
      hint: 'disponível agora (estimado)',
    },
    a_receber: {
      value: r.next_30_days_cents || 0,
      hint: r.next_30_days_count != null ? `${r.next_30_days_count} parcelas futuras` : 'parcelas futuras',
    },
    a_pagar: {
      value: p.next_30_days_cents || 0,
      hint: 'despesas fixas + manuais',
    },
  };
});

function centsToBRLShort(cents) {
  if (cents == null) return 'R$ 0';
  const v = cents / 100;
  if (Math.abs(v) >= 1_000_000) return 'R$ ' + (v / 1_000_000).toLocaleString('pt-BR', { maximumFractionDigits: 1 }) + 'M';
  if (Math.abs(v) >= 1_000)     return 'R$ ' + (v / 1_000).toLocaleString('pt-BR', { maximumFractionDigits: 0 }) + 'K';
  return 'R$ ' + v.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}

// Subtitle dinâmico: "Atualizado XX/XX/XXXX"
const lastUpdated = computed(() => {
  const d = new Date();
  return `${String(d.getDate()).padStart(2, '0')}/${String(d.getMonth() + 1).padStart(2, '0')}/${d.getFullYear()}`;
});
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header dash-v2__header">
      <div>
        <h1 class="finv2-page__title">Dashboard</h1>
        <p class="finv2-page__subtitle">
          Período: <strong>{{ toBR(period.from) }} → {{ toBR(period.to) }}</strong> · Atualizado {{ lastUpdated }}
        </p>
      </div>
      <div class="dash-v2__header-actions">
        <div class="dash-v2__period-chips">
          <button
            v-for="t in PERIOD_TYPES"
            :key="t.value"
            type="button"
            class="dash-v2__period-chip"
            :class="{ 'dash-v2__period-chip--active': periodType === t.value }"
            @click="applyPeriod(t.value)"
          >
            {{ t.label }}
          </button>
        </div>
        <div v-if="periodType !== 'all'" class="dash-v2__period-shift">
          <button class="dash-v2__shift-btn" @click="shiftAnchor(-1); load()" aria-label="Anterior">
            <i class="i-lucide-chevron-left" />
          </button>
          <strong class="dash-v2__period-label">{{ period.label }}</strong>
          <button class="dash-v2__shift-btn" @click="shiftAnchor(1); load()" aria-label="Próximo">
            <i class="i-lucide-chevron-right" />
          </button>
        </div>
      </div>
    </header>

    <div class="finv2-page__body dash-v2">
      <!-- Loading inicial -->
      <div v-if="loading && !dashboardData" class="dash-v2__state">
        <div class="dash-v2__spinner" />
        <span>Carregando dashboard...</span>
      </div>

      <!-- Error -->
      <div v-else-if="errorMessage" class="dash-v2__state dash-v2__state--error">
        <i class="i-lucide-alert-circle" />
        <div>
          <strong>Não foi possível carregar.</strong>
          <p>{{ errorMessage }}</p>
        </div>
        <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
      </div>

      <template v-else-if="kpis">
        <!-- 6 KPIs -->
        <div class="dash-v2__kpis">
          <div class="dash-v2__kpi dash-v2__kpi--accent-emerald">
            <span class="dash-v2__kpi-label">Receita do mês</span>
            <strong class="dash-v2__kpi-value">{{ centsToBRLShort(kpis.receita.value) }}</strong>
            <span class="dash-v2__kpi-hint">{{ kpis.receita.hint }}</span>
          </div>
          <div class="dash-v2__kpi dash-v2__kpi--accent-ruby">
            <span class="dash-v2__kpi-label">Despesas do mês</span>
            <strong class="dash-v2__kpi-value">{{ centsToBRLShort(kpis.despesa.value) }}</strong>
            <span v-if="kpis.despesa.hint" class="dash-v2__kpi-hint">{{ kpis.despesa.hint }}</span>
          </div>
          <div class="dash-v2__kpi dash-v2__kpi--accent-teal">
            <span class="dash-v2__kpi-label">Margem do mês</span>
            <strong class="dash-v2__kpi-value">{{ centsToBRLShort(kpis.margem.value) }}</strong>
            <span v-if="kpis.margem.hint" class="dash-v2__kpi-hint">{{ kpis.margem.hint }}</span>
          </div>
          <div class="dash-v2__kpi dash-v2__kpi--accent-blue">
            <span class="dash-v2__kpi-label">Saldo total contas</span>
            <strong class="dash-v2__kpi-value">{{ centsToBRLShort(kpis.saldo.value) }}</strong>
            <span class="dash-v2__kpi-hint">{{ kpis.saldo.hint }}</span>
          </div>
          <div class="dash-v2__kpi dash-v2__kpi--accent-amber">
            <span class="dash-v2__kpi-label">A receber 30 dias</span>
            <strong class="dash-v2__kpi-value">{{ centsToBRLShort(kpis.a_receber.value) }}</strong>
            <span class="dash-v2__kpi-hint">{{ kpis.a_receber.hint }}</span>
          </div>
          <div class="dash-v2__kpi dash-v2__kpi--accent-amber">
            <span class="dash-v2__kpi-label">A pagar 30 dias</span>
            <strong class="dash-v2__kpi-value">{{ centsToBRLShort(kpis.a_pagar.value) }}</strong>
            <span class="dash-v2__kpi-hint">{{ kpis.a_pagar.hint }}</span>
          </div>
        </div>

        <!-- Charts em grid 2x2 -->
        <div class="dash-v2__charts">
          <article class="dash-v2__chart-card">
            <header class="dash-v2__chart-header">
              <h3 class="dash-v2__chart-title">RECEITA VS META</h3>
              <p class="dash-v2__chart-sub">Mensal · colorido por faixa</p>
            </header>
            <div class="dash-v2__chart-body">
              <RevenueVsGoalChart :data="revenueVsGoal" />
            </div>
          </article>

          <article class="dash-v2__chart-card">
            <header class="dash-v2__chart-header">
              <h3 class="dash-v2__chart-title">RECEITA POR CATEGORIA</h3>
              <p class="dash-v2__chart-sub">Especialidades clínicas</p>
            </header>
            <div class="dash-v2__chart-body">
              <RevenueCompositionChartV2 :from="period.from" :to="period.to" />
            </div>
          </article>

          <article class="dash-v2__chart-card">
            <header class="dash-v2__chart-header">
              <h3 class="dash-v2__chart-title">RECEITA VS DESPESA</h3>
              <p class="dash-v2__chart-sub">Últimos 6 meses</p>
            </header>
            <div class="dash-v2__chart-body">
              <RevenueVsExpenseChart :months="6" />
            </div>
          </article>

          <article class="dash-v2__chart-card">
            <header class="dash-v2__chart-header">
              <h3 class="dash-v2__chart-title">PRODUÇÃO POR PROFISSIONAL</h3>
              <p class="dash-v2__chart-sub">Top profissionais</p>
            </header>
            <div class="dash-v2__chart-body">
              <RevenueByProfessionalChartV2 :from="period.from" :to="period.to" :limit="10" />
            </div>
          </article>
        </div>

        <!-- Top 10 Procedimentos -->
        <article class="dash-v2__chart-card dash-v2__top-card">
          <header class="dash-v2__chart-header">
            <h3 class="dash-v2__chart-title">TOP 10 PROCEDIMENTOS</h3>
            <p class="dash-v2__chart-sub">Mais realizados no período</p>
          </header>
          <div v-if="topProcedures.length === 0" class="dash-v2__top-empty">
            Nenhum procedimento aprovado no período selecionado.
          </div>
          <!-- Wrapper com scroll horizontal: em telas estreitas a tabela
               extrapola o card e vazava pra esquerda. Agora rola dentro
               do próprio wrapper sem quebrar o layout do dashboard. -->
          <div v-else class="dash-v2__top-scroll">
            <table class="dash-v2__top-table">
              <thead>
                <tr>
                  <th class="dash-v2__top-th-name">PROCEDIMENTO</th>
                  <th class="dash-v2__top-th-qty">QTD</th>
                  <th class="dash-v2__top-th-total">VALOR TOTAL</th>
                  <th class="dash-v2__top-th-avg">TICKET MÉDIO</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="p in topProcedures" :key="p.name">
                  <td class="dash-v2__top-td-name">{{ p.name }}</td>
                  <td class="dash-v2__top-td-qty">{{ p.qty.toLocaleString('pt-BR') }}</td>
                  <td class="dash-v2__top-td-total">{{ centsToBRL(p.total_cents) }}</td>
                  <td class="dash-v2__top-td-avg">{{ p.ticket_avg_cents ? centsToBRL(p.ticket_avg_cents) : '—' }}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </article>
      </template>
    </div>

  </div>
</template>

<style scoped lang="scss">
.dash-v2__header {
  flex-wrap: wrap;
  gap: 12px;
}
.dash-v2__header-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

/* Period chips */
.dash-v2__period-chips {
  display: inline-flex;
  align-items: center;
  background: rgb(var(--slate-3));
  border-radius: 8px;
  padding: 2px;
  min-height: 36px; /* mesma altura do datepicker pra harmonizar a barra */
}
.dash-v2__period-chip {
  padding: 6px 12px;
  background: transparent;
  border: 0;
  border-radius: 6px;
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background 0.12s ease, color 0.12s ease;

  &:hover:not(&--active) {
    color: rgb(var(--slate-12));
  }
  &--active {
    background: rgb(var(--slate-1));
    color: rgb(var(--slate-12));
    box-shadow: 0 1px 2px rgba(0, 0, 0, 0.1);
  }
}
.dash-v2__period-shift {
  display: inline-flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  padding: 4px 8px;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  font-size: 12px;
  color: rgb(var(--slate-11));
  /* Largura fixa pro datepicker — sem isso, label "Semana" (24/05–30/05/2026)
     é largo e label "Ano" (2026) é curto, fazendo as abas se deslocarem
     na lateral toda vez que mudava o seletor. Largura cobre o maior label
     (semana) com folga; labels menores ficam centralizados internamente. */
  min-width: 220px;
  min-height: 36px; /* mesma altura das abas pra harmonizar a barra */
  box-sizing: border-box;
}
.dash-v2__shift-btn {
  background: transparent;
  border: 0;
  padding: 0;
  width: 22px;
  height: 22px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 4px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  i { width: 14px; height: 14px; display: block; }
  &:hover { background: rgb(var(--slate-3)); color: rgb(var(--slate-12)); }
}
.dash-v2__period-label {
  flex: 1; /* ocupa o espaço entre as setas mesmo quando label é curto */
  text-align: center;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

/* Mobile: ambos ocupam 100% da largura (em vez de auto), em linhas separadas
   pelo flex-wrap do parent. Chips dividem espaço igualmente entre as abas
   pra ficar com leitura confortável; datepicker estica horizontalmente. */
@media (max-width: 640px) {
  .dash-v2__header-actions { width: 100%; }
  .dash-v2__period-chips,
  .dash-v2__period-shift {
    width: 100%;
    min-width: 0; /* libera o min-width: 220px do desktop */
  }
  .dash-v2__period-chip { flex: 1; text-align: center; }
}

/* States */
.dash-v2__state {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 80px 24px;
  gap: 12px;
  color: rgb(var(--slate-9));
}
.dash-v2__state--error {
  flex-direction: column;
  color: rgb(var(--ruby-10));
  i { width: 28px; height: 28px; }
}
.dash-v2__spinner {
  width: 18px; height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── KPIs (6 cards com barra colorida no topo) ─────────────────── */
.dash-v2__kpis {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 12px;
  margin-bottom: 20px;

  @media (max-width: 1280px) { grid-template-columns: repeat(3, minmax(0, 1fr)); }
  @media (max-width: 720px)  { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  @media (max-width: 480px)  { grid-template-columns: 1fr; }
}
.dash-v2__kpi {
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
  &--accent-ruby::before    { background: linear-gradient(90deg, rgb(var(--ruby-9)),     rgb(var(--ruby-7))); }
  &--accent-teal::before    { background: linear-gradient(90deg, rgb(var(--teal-9)),    rgb(var(--teal-7))); }
  &--accent-blue::before    { background: linear-gradient(90deg, rgb(var(--blue-9)),    rgb(var(--blue-7))); }
  &--accent-amber::before   { background: linear-gradient(90deg, rgb(var(--amber-9)),   rgb(var(--amber-7))); }
}
.dash-v2__kpi-label {
  font-size: 10px; font-weight: 600; letter-spacing: 0.06em;
  text-transform: uppercase; color: rgb(var(--slate-9));
}
.dash-v2__kpi-value {
  font-size: 24px; font-weight: 700;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  line-height: 1.1;
}
.dash-v2__kpi-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* ── Charts (2×2) ───────────────────────────────────────── */
.dash-v2__charts {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-bottom: 16px;
  @media (max-width: 900px) { grid-template-columns: 1fr; }
}
.dash-v2__chart-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 16px;
  display: flex; flex-direction: column; gap: 12px;
}
.dash-v2__chart-header {
  display: flex; flex-direction: column; gap: 2px;
}
.dash-v2__chart-title {
  margin: 0;
  font-size: 11px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.08em;
  color: rgb(var(--slate-10));
}
.dash-v2__chart-sub {
  margin: 0;
  font-size: 12px;
  color: rgb(var(--slate-9));
}
.dash-v2__chart-body {
  min-height: 260px;
}

/* ── Top procedimentos ───────────────────────────────────── */
.dash-v2__top-card {
  margin-bottom: 16px;
}
.dash-v2__top-empty {
  padding: 40px 16px;
  text-align: center;
  color: rgb(var(--slate-9));
  font-size: 13px;
}
/* Scroll horizontal — em telas estreitas (~< 600px) o conteúdo da
   tabela é mais largo que o card. Sem wrapper, vazava pra esquerda
   do parent grid. Com scroll dentro do card, fica contido. */
.dash-v2__top-scroll {
  width: 100%;
  overflow-x: auto;
  -webkit-overflow-scrolling: touch;
}
.dash-v2__top-table {
  width: 100%;
  min-width: 560px; /* garante leitura mínima — abaixo disso, scroll horizontal */
  border-collapse: collapse;
  font-size: 13px;

  thead th {
    /* Default = left. Colunas numéricas sobrescrevem com `&.modifier { text-align: right }`
       dentro do mesmo escopo, pra ganhar de `thead th` em especificidade. */
    text-align: left;
    padding: 8px 10px;
    font-size: 10px; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.05em;
    color: rgb(var(--slate-9));
    border-bottom: 1px solid rgb(var(--slate-4));

    &.dash-v2__top-th-qty,
    &.dash-v2__top-th-total,
    &.dash-v2__top-th-avg {
      text-align: right;
    }
  }
  tbody tr {
    border-bottom: 1px solid rgb(var(--slate-3));
    &:last-child { border-bottom: 0; }
  }
  td { padding: 10px; vertical-align: middle; }
}
.dash-v2__top-th-name, .dash-v2__top-td-name { min-width: 220px; }
.dash-v2__top-th-qty, .dash-v2__top-td-qty {
  width: 80px; text-align: right; font-variant-numeric: tabular-nums;
}
.dash-v2__top-th-total, .dash-v2__top-td-total {
  width: 140px; text-align: right; font-variant-numeric: tabular-nums;
  font-weight: 600; color: rgb(var(--slate-12));
}
.dash-v2__top-th-avg, .dash-v2__top-td-avg {
  width: 120px; text-align: right; font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-10));
}

/* Print: esconde chrome do app, foca no conteúdo */
@media print {
  .dash-v2__header-actions { display: none; }
}
</style>
