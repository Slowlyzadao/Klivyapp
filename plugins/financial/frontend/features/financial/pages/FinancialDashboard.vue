<script setup>
/* global axios */
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import draggable from 'vuedraggable';
import '../financial.css';
import dashboardAPI from '../api/dashboard';
import { useFinancialFilters } from '../composables/useFinancialFilters';
import { useFormatCurrency } from '../composables/useFormatCurrency';
import CashFlowChart from '../components/CashFlowChart.vue';
import RevenueGoalGauge from '../components/RevenueGoalGauge.vue';
import FinancialKpiCards from '../components/FinancialKpiCards.vue';
import CashFlowProjection from '../components/CashFlowProjection.vue';
import ReceivablesByWeek from '../components/ReceivablesByWeek.vue';
import DelinquencyAging from '../components/DelinquencyAging.vue';
import DelinquencyTrend from '../components/DelinquencyTrend.vue';
import DelinquencyByProfessional from '../components/DelinquencyByProfessional.vue';
import DreWaterfallChart from '../components/DreWaterfallChart.vue';
import AverageTicketTrend from '../components/AverageTicketTrend.vue';
import RevenueByProfessional from '../components/RevenueByProfessional.vue';
import RevenueComposition from '../components/RevenueComposition.vue';
import ExpensesByCategory from '../components/ExpensesByCategory.vue';
import FixedVsVariableCosts from '../components/FixedVsVariableCosts.vue';
import ConversionFunnel from '../components/ConversionFunnel.vue';
import AgendaHeatmap from '../components/AgendaHeatmap.vue';
import NewVsReturningPatients from '../components/NewVsReturningPatients.vue';

const store = useStore();
const { t } = useI18n();
const { period, dateRange, setPeriod } = useFinancialFilters();
const { formatCurrency } = useFormatCurrency();

const loading = ref(false);
const data = ref(null);

const periods = [
  { key: 'today', labelKey: 'FINANCIAL.PERIOD.TODAY' },
  { key: 'week', labelKey: 'FINANCIAL.PERIOD.WEEK' },
  { key: 'month', labelKey: 'FINANCIAL.PERIOD.MONTH' },
];

const DEFAULT_BLOCKS = [
  { id: 'receivables' },
  { id: 'payables' },
  { id: 'cash_flow_chart' },
  { id: 'revenue_goal' },
  { id: 'cash_flow_projection' },
  { id: 'receivables_by_week' },
  { id: 'delinquency_aging' },
  { id: 'delinquency_trend' },
  { id: 'delinquency_by_professional' },
  { id: 'dre_waterfall' },
  { id: 'ticket_trend' },
  { id: 'revenue_by_professional' },
  { id: 'revenue_composition' },
  { id: 'expenses_by_category_chart' },
  { id: 'cost_structure' },
  { id: 'conversion_funnel' },
  { id: 'agenda_heatmap' },
  { id: 'new_vs_returning' },
  { id: 'expenses' },
  { id: 'revenue' },
  { id: 'delinquency' },
  { id: 'bank_accounts' },
];

const uiSettings = computed(
  () => store.getters['auth/getCurrentUser']?.ui_settings || {}
);
const isCustomizing = ref(false);
const blocksOrder = ref([...DEFAULT_BLOCKS]);

const toggleCustomize = () => {
  isCustomizing.value = true;
};

const saveCustomization = async () => {
  try {
    const newSettings = {
      ...uiSettings.value,
      financial_dashboard_order: blocksOrder.value.map(b => b.id),
    };
    await store.dispatch('auth/updateProfile', {
      profile: { ui_settings: newSettings },
    });
  } catch (error) {
    // ignore
  } finally {
    isCustomizing.value = false;
  }
};

const fetchDashboard = async () => {
  loading.value = true;
  try {
    const response = await dashboardAPI.get(dateRange.value);
    data.value = response.data;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
};

watch(dateRange, fetchDashboard, { deep: true });

// KPI helpers
const kpis = computed(() => {
  if (!data.value) return null;
  return {
    income: data.value.income ?? 0,
    expense: data.value.expense ?? 0,
    new_income: data.value.new_income ?? 0,
    net_profit: data.value.net_profit ?? 0,
    income_delta: data.value.income_delta ?? 0,
    expense_delta: data.value.expense_delta ?? 0,
    new_income_delta: data.value.new_income_delta ?? 0,
    profit_delta: data.value.profit_delta ?? 0,
  };
});

const receivables = computed(() => data.value?.receivables ?? {});
const payables = computed(() => data.value?.payables ?? {});
const delinquency = computed(() => data.value?.delinquency ?? {});
const bankAccounts = computed(() => data.value?.bank_accounts ?? []);
const expensesByCategory = computed(
  () => data.value?.expenses_by_category ?? []
);
const revenueByInsurance = computed(
  () => data.value?.revenue_by_insurance ?? []
);
// ── Dados dos 3 gráficos Chart.js (Onda 1) ─────────────────────
const cashFlowChartData = ref([]);
const cashFlowChartLoading = ref(false);
const cashFlowAlert = ref(null);

const revenueGoalData = ref({
  meta: 0,
  realizado: 0,
  percentual: 0,
  ritmo_ideal: 0,
  delta_ritmo: 0,
  dias_restantes: 0,
});
const revenueGoalLoading = ref(false);

const kpiData = ref({
  entradas_hoje: 0,
  entradas_variacao: 0,
  saidas_hoje: 0,
  saidas_variacao: 0,
  saldo_dia: 0,
  inadimplencia_total: 0,
  sparklines: { entradas: [], saidas: [], saldo: [], inadimplencia: [] },
});
const kpiLoading = ref(false);

const fetchCharts = async () => {
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;
  const base = `/api/v1/accounts/${accountId}/financial`;

  kpiLoading.value = true;
  try {
    const r = await axios.get(`${base}/dashboard/kpis`);
    kpiData.value = r.data;
  } catch {
    /* noop */
  } finally {
    kpiLoading.value = false;
  }

  cashFlowChartLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/cash_flow_chart`);
    cashFlowChartData.value = r.data.days ?? [];
  } catch {
    /* noop */
  } finally {
    cashFlowChartLoading.value = false;
  }

  revenueGoalLoading.value = true;
  try {
    const r = await axios.get(`${base}/dashboard/revenue_goal`);
    revenueGoalData.value = r.data;
  } catch {
    /* noop */
  } finally {
    revenueGoalLoading.value = false;
  }
};

// ── Onda 2 — Refs ─────────────────────────────────────────────────
const projectionData = ref({ atual: 0, projecao: [] });
const projectionLoading = ref(false);

const receivablesByWeekData = ref([]);
const receivablesByWeekLoading = ref(false);

const agingData = ref([]);
const agingLoading = ref(false);

const delinquencyTrendData = ref([]);
const delinquencyTrendLoading = ref(false);

const delinquencyProfData = ref([]);
const delinquencyProfLoading = ref(false);

const fetchCharts2 = async (horizon = 30) => {
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;
  const base = `/api/v1/accounts/${accountId}/financial`;

  projectionLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/cash_flow_projection`, {
      params: { horizon },
    });
    projectionData.value = r.data;
  } catch {
    /* noop */
  } finally {
    projectionLoading.value = false;
  }

  receivablesByWeekLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/receivables_forecast`);
    receivablesByWeekData.value = r.data;
  } catch {
    /* noop */
  } finally {
    receivablesByWeekLoading.value = false;
  }

  agingLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/delinquency_aging`);
    agingData.value = r.data;
  } catch {
    /* noop */
  } finally {
    agingLoading.value = false;
  }

  delinquencyTrendLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/delinquency_trend`);
    delinquencyTrendData.value = r.data;
  } catch {
    /* noop */
  } finally {
    delinquencyTrendLoading.value = false;
  }

  delinquencyProfLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/delinquency_by_professional`);
    delinquencyProfData.value = r.data;
  } catch {
    /* noop */
  } finally {
    delinquencyProfLoading.value = false;
  }
};

const onHorizonChange = h => fetchCharts2(h);

// ── Onda 3 — Refs ─────────────────────────────────────────────────
const dreData = ref([]);
const dreLoading = ref(false);
const dreRegime = ref('caixa');

const ticketTrendData = ref([]);
const ticketTrendLoading = ref(false);

const revByProfData = ref([]);
const revByProfLoading = ref(false);

const revCompositionData = ref({ atual: {}, historico: [] });
const revCompositionLoading = ref(false);

const expByCategoryData = ref([]);
const expByCategoryLoading = ref(false);

const costStructureData = ref([]);
const costStructureLoading = ref(false);

const fetchCharts3 = async () => {
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;
  const base = `/api/v1/accounts/${accountId}/financial`;

  dreLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/dre_waterfall`, {
      params: { regime: dreRegime.value },
    });
    dreData.value = r.data;
  } catch {
    /* noop */
  } finally {
    dreLoading.value = false;
  }

  ticketTrendLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/ticket_trend`);
    ticketTrendData.value = r.data;
  } catch {
    /* noop */
  } finally {
    ticketTrendLoading.value = false;
  }

  revByProfLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/revenue_by_professional`);
    revByProfData.value = r.data;
  } catch {
    /* noop */
  } finally {
    revByProfLoading.value = false;
  }

  revCompositionLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/revenue_composition`);
    revCompositionData.value = r.data;
  } catch {
    /* noop */
  } finally {
    revCompositionLoading.value = false;
  }

  expByCategoryLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/expenses_by_category`);
    expByCategoryData.value = r.data;
  } catch {
    /* noop */
  } finally {
    expByCategoryLoading.value = false;
  }

  costStructureLoading.value = true;
  try {
    const r = await axios.get(`${base}/reports/cost_structure`);
    costStructureData.value = r.data;
  } catch {
    /* noop */
  } finally {
    costStructureLoading.value = false;
  }
};

const onDreRegimeChange = async r => {
  dreRegime.value = r;
  dreLoading.value = true;
  try {
    const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
    const res = await axios.get(
      `/api/v1/accounts/${accountId}/financial/reports/dre_waterfall`,
      { params: { regime: r } }
    );
    dreData.value = res.data;
  } catch {
    /* noop */
  } finally {
    dreLoading.value = false;
  }
};

// ── Onda 4 — Refs ─────────────────────────────────────────────────
const funnelData = ref({});
const funnelLoading = ref(false);

const heatmapData = ref({});
const heatmapLoading = ref(false);

const retentionData = ref({});
const retentionLoading = ref(false);

const fetchCharts4 = async () => {
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;
  const base = `/api/v1/accounts/${accountId}/financial/reports`;

  funnelLoading.value = true;
  try {
    const r = await axios.get(`${base}/conversion_funnel`);
    funnelData.value = r.data;
  } catch {
    /* noop */
  } finally {
    funnelLoading.value = false;
  }

  heatmapLoading.value = true;
  try {
    const r = await axios.get(`${base}/agenda_heatmap`);
    heatmapData.value = r.data;
  } catch {
    /* noop */
  } finally {
    heatmapLoading.value = false;
  }

  retentionLoading.value = true;
  try {
    const r = await axios.get(`${base}/patient_retention`);
    retentionData.value = r.data;
  } catch {
    /* noop */
  } finally {
    retentionLoading.value = false;
  }
};
// ──────────────────────────────────────────────────────────────────

onMounted(() => {
  const savedOrder = uiSettings.value.financial_dashboard_order;
  if (savedOrder && savedOrder.length) {
    blocksOrder.value = savedOrder
      .filter(id => id !== 'kpi_cards')
      .map(id => ({ id }));
  }
  fetchDashboard();
  fetchCharts();
  fetchCharts2();
  fetchCharts3();
  fetchCharts4();
});

const isBlockVisible = id => {
  if (isCustomizing.value) return true;
  const saved = uiSettings.value.financial_dashboard_hidden;
  if (saved && Array.isArray(saved)) return !saved.includes(id);
  return true;
};

const maxExpense = computed(() =>
  Math.max(...expensesByCategory.value.map(c => c.amount), 0)
);
const maxRevenue = computed(() =>
  Math.max(...revenueByInsurance.value.map(r => r.amount), 0)
);

const totalBankBalance = computed(() =>
  bankAccounts.value.reduce((s, a) => s + parseFloat(a.current_balance || 0), 0)
);

const receivablesTotal = computed(() => {
  const r = receivables.value;
  return (r.overdue || 0) + (r.pending || 0) + (r.due_today || 0);
});

const receivablesPercent = computed(() => {
  if (!receivablesTotal.value || !kpis.value) return 0;
  return Math.min(
    100,
    Math.round((receivables.value.overdue / receivablesTotal.value) * 100)
  );
});
</script>

<template>
  <div class="financial-page">
    <!-- Header -->
    <div class="financial-header">
      <h1 class="financial-header__title">
        {{ t('FINANCIAL.DASHBOARD.TITLE') }}
      </h1>
      <div class="financial-header__actions flex items-center gap-3">
        <button
          v-if="!isCustomizing"
          class="btn-secondary flex items-center gap-2"
          @click="toggleCustomize"
        >
          <i class="i-lucide-settings-2" />
          {{ t('FINANCIAL.DASHBOARD.CUSTOMIZE_DASHBOARD') }}
        </button>
        <button
          v-else
          class="financial-btn financial-btn--primary flex items-center gap-2"
          @click="saveCustomization"
        >
          <i class="i-lucide-save" />
          {{ t('FINANCIAL.DASHBOARD.SAVE_CUSTOMIZATION') }}
        </button>
        <div v-if="!isCustomizing" class="financial-period-selector">
          <button
            v-for="p in periods"
            :key="p.key"
            class="financial-period-btn"
            :class="[period === p.key && 'financial-period-btn--active']"
            @click="setPeriod(p.key)"
          >
            {{ t(p.labelKey) }}
          </button>
        </div>
      </div>
    </div>

    <!-- Standalone KPI Cards (Entradas Hoje) -->
    <div class="financial-standalone-kpi">
      <FinancialKpiCards :data="kpiData" :loading="kpiLoading" />
    </div>

    <!-- KPIs -->
    <div class="financial-kpi-grid">
      <!-- Receita Líquida -->
      <div class="financial-kpi-card">
        <span class="financial-kpi-card__label">{{
          t('FINANCIAL.DASHBOARD.NET_INCOME')
        }}</span>
        <template v-if="loading">
          <div class="financial-skeleton financial-skeleton--kpi" />
        </template>
        <template v-else>
          <span
            class="financial-kpi-card__value financial-kpi-card__value--income"
          >
            {{ kpis ? formatCurrency(kpis.income) : '—' }}
          </span>
        </template>
      </div>

      <!-- Saídas -->
      <div class="financial-kpi-card">
        <span class="financial-kpi-card__label">{{
          t('FINANCIAL.DASHBOARD.EXPENSES')
        }}</span>
        <template v-if="loading">
          <div class="financial-skeleton financial-skeleton--kpi" />
        </template>
        <template v-else>
          <span
            class="financial-kpi-card__value financial-kpi-card__value--expense"
          >
            {{ kpis ? formatCurrency(kpis.expense) : '—' }}
          </span>
        </template>
      </div>

      <!-- Novas Entradas -->
      <div class="financial-kpi-card">
        <span class="financial-kpi-card__label">{{
          t('FINANCIAL.DASHBOARD.NEW_ENTRIES')
        }}</span>
        <template v-if="loading">
          <div class="financial-skeleton financial-skeleton--kpi" />
        </template>
        <template v-else>
          <span class="financial-kpi-card__value">
            {{ kpis ? formatCurrency(kpis.new_income) : '—' }}
          </span>
        </template>
      </div>

      <!-- Lucro Líquido -->
      <div
        class="financial-kpi-card"
        :class="[
          kpis && kpis.net_profit < 0
            ? 'financial-kpi-card--profit-negative'
            : 'financial-kpi-card--profit',
        ]"
      >
        <span class="financial-kpi-card__label">{{
          t('FINANCIAL.DASHBOARD.NET_PROFIT')
        }}</span>
        <template v-if="loading">
          <div class="financial-skeleton financial-skeleton--kpi" />
        </template>
        <template v-else>
          <span
            class="financial-kpi-card__value financial-kpi-card__value--profit"
          >
            {{ kpis ? formatCurrency(kpis.net_profit) : '—' }}
          </span>
        </template>
      </div>

      <!-- Ticket Medio Geral -->
      <div class="financial-kpi-card financial-kpi-card--ticket">
        <span class="financial-kpi-card__label">{{
          t('FINANCIAL.DASHBOARD.AVERAGE_TICKET')
        }}</span>
        <template v-if="loading">
          <div class="financial-skeleton financial-skeleton--kpi" />
        </template>
        <template v-else>
          <span class="financial-kpi-card__value">
            {{ formatCurrency(data?.average_ticket ?? 0) }}
          </span>
        </template>
      </div>
    </div>



    <!-- Custom Blocks Grid -->
    <draggable
      v-model="blocksOrder"
      item-key="id"
      class="financial-blocks-grid"
      handle=".financial-drag-handle"
      ghost-class="financial-block--ghost"
      drag-class="financial-block--draggable"
      :animation="200"
      :disabled="!isCustomizing"
    >
      <template #item="{ element }">
        <div
          v-if="isBlockVisible(element.id)"
          class="financial-block"
        >
          <!-- Receivables -->
          <template v-if="element.id === 'receivables'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-arrow-down-circle financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.DASHBOARD.RECEIVABLES') }}
              </span>
              <router-link
                v-if="!isCustomizing"
                :to="{ name: 'financial_receivables' }"
                class="financial-block__link"
              >
                {{ t('FINANCIAL.DASHBOARD.VIEW_ALL') }}
              </router-link>
            </div>
            <template v-if="loading">
              <div class="financial-skeleton financial-skeleton--row" />
              <div class="financial-skeleton financial-skeleton--row-sm" />
            </template>
            <template v-else>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.OVERDUE')
                }}</span>
                <span
                  class="financial-block__row-value financial-block__row-value--overdue"
                  >{{ formatCurrency(receivables.overdue) }}</span
                >
              </div>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.UPCOMING')
                }}</span>
                <span class="financial-block__row-value">{{
                  formatCurrency(receivables.pending)
                }}</span>
              </div>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.DUE_TODAY')
                }}</span>
                <span
                  class="financial-block__row-value financial-block__row-value--today"
                  >{{ formatCurrency(receivables.due_today) }}</span
                >
              </div>
              <div v-if="receivablesPercent > 0" class="mt-2">
                <div class="financial-progress-label">
                  <!-- eslint-disable-next-line -->
                  <span>Inadimplência</span>
                  <!-- eslint-disable-next-line -->
                  <span>{{ receivablesPercent }}% vencidos</span>
                </div>
                <div class="financial-progress">
                  <div
                    class="financial-progress__fill financial-progress__fill--expense"
                    :style="{ width: `${receivablesPercent}%` }"
                  />
                </div>
              </div>
            </template>
          </template>

          <!-- Payables -->
          <template v-if="element.id === 'payables'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-arrow-up-circle financial-block__icon financial-block__icon--expense"
                />
                {{ t('FINANCIAL.DASHBOARD.PAYABLES') }}
              </span>
              <router-link
                v-if="!isCustomizing"
                :to="{ name: 'financial_payables' }"
                class="financial-block__link"
              >
                {{ t('FINANCIAL.DASHBOARD.VIEW_ALL') }}
              </router-link>
            </div>
            <template v-if="loading">
              <div class="financial-skeleton financial-skeleton--row" />
              <div class="financial-skeleton financial-skeleton--row-sm" />
            </template>
            <template v-else>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.OVERDUE_PAYABLES')
                }}</span>
                <span
                  class="financial-block__row-value financial-block__row-value--overdue"
                  >{{ formatCurrency(payables.overdue) }}</span
                >
              </div>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.UPCOMING_PAYABLES')
                }}</span>
                <span class="financial-block__row-value">{{
                  formatCurrency(payables.pending)
                }}</span>
              </div>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.DUE_TODAY_PAYABLES')
                }}</span>
                <span
                  class="financial-block__row-value financial-block__row-value--today"
                  >{{ formatCurrency(payables.due_today) }}</span
                >
              </div>
            </template>
          </template>


          <!-- Fluxo de Caixa Diário Chart.js (Gráfico #1) -->
          <template v-if="element.id === 'cash_flow_chart'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-bar-chart-3 financial-block__icon financial-block__icon--info"
                />
                {{ t('FINANCIAL.CHARTS.CASH_FLOW.TITLE') }}
              </span>
            </div>
            <CashFlowChart
              :data="cashFlowChartData"
              :loading="cashFlowChartLoading"
              @alert="cashFlowAlert = $event"
            />
          </template>

          <!-- Receita vs Meta Gauge (Gráfico #2) -->
          <template v-if="element.id === 'revenue_goal'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-target financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.CHARTS.REVENUE_GOAL.TITLE') }}
              </span>
            </div>
            <RevenueGoalGauge
              :data="revenueGoalData"
              :loading="revenueGoalLoading"
            />
          </template>

          <!-- Projeção de Caixa (Gráfico #4) -->
          <template v-if="element.id === 'cash_flow_projection'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-trending-up financial-block__icon financial-block__icon--info"
                />
                {{ t('FINANCIAL.CHARTS.PROJECTION.TITLE') }}
              </span>
            </div>
            <CashFlowProjection
              :data="projectionData"
              :loading="projectionLoading"
              @horizon-change="onHorizonChange"
            />
          </template>

          <!-- A Receber por Semana (Gráfico #5) -->
          <template v-if="element.id === 'receivables_by_week'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-calendar financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.CHARTS.RECEIVABLES.TITLE') }}
              </span>
            </div>
            <ReceivablesByWeek
              :data="receivablesByWeekData"
              :loading="receivablesByWeekLoading"
            />
          </template>

          <!-- Aging de Inadimplência (Gráfico #6) -->
          <template v-if="element.id === 'delinquency_aging'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-alert-circle financial-block__icon financial-block__icon--warning"
                />
                {{ t('FINANCIAL.CHARTS.AGING.TITLE') }}
              </span>
            </div>
            <DelinquencyAging :data="agingData" :loading="agingLoading" />
          </template>

          <!-- Evolução da Inadimplência (Gráfico #7) -->
          <template v-if="element.id === 'delinquency_trend'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-trending-down financial-block__icon financial-block__icon--warning"
                />
                {{ t('FINANCIAL.CHARTS.DELINQUENCY_TREND.TITLE') }}
              </span>
            </div>
            <DelinquencyTrend
              :data="delinquencyTrendData"
              :loading="delinquencyTrendLoading"
            />
          </template>

          <!-- Inadimplência por Profissional (Gráfico #8) -->
          <template v-if="element.id === 'delinquency_by_professional'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-users financial-block__icon financial-block__icon--warning"
                />
                {{ t('FINANCIAL.CHARTS.DELINQUENCY_PROF.TITLE') }}
              </span>
            </div>
            <DelinquencyByProfessional
              :data="delinquencyProfData"
              :loading="delinquencyProfLoading"
            />
          </template>

          <!-- DRE Waterfall (Gráfico #9) -->
          <template v-if="element.id === 'dre_waterfall'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-bar-chart-2 financial-block__icon financial-block__icon--info"
                />
                {{ t('FINANCIAL.CHARTS.DRE.TITLE') }}
              </span>
            </div>
            <DreWaterfallChart
              :data="dreData"
              :loading="dreLoading"
              :regime="dreRegime"
              @regime-change="onDreRegimeChange"
            />
          </template>

          <!-- Ticket Médio com Tendência (Gráfico #10) -->
          <template v-if="element.id === 'ticket_trend'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-ticket financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.CHARTS.TICKET.TITLE') }}
              </span>
            </div>
            <AverageTicketTrend
              :data="ticketTrendData"
              :loading="ticketTrendLoading"
            />
          </template>

          <!-- Receita por Profissional (Gráfico #11) -->
          <template v-if="element.id === 'revenue_by_professional'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-users financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.CHARTS.PROF_REVENUE.TITLE') }}
              </span>
            </div>
            <RevenueByProfessional
              :data="revByProfData"
              :loading="revByProfLoading"
            />
          </template>

          <!-- Composição de Receita (Gráfico #12) -->
          <template v-if="element.id === 'revenue_composition'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-pie-chart financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.CHARTS.COMPOSITION.TITLE') }}
              </span>
            </div>
            <RevenueComposition
              :data="revCompositionData"
              :loading="revCompositionLoading"
            />
          </template>

          <!-- Despesas por Categoria (Gráfico #13) -->
          <template v-if="element.id === 'expenses_by_category_chart'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-layers financial-block__icon financial-block__icon--expense"
                />
                {{ t('FINANCIAL.CHARTS.EXPENSES_CATEGORY.TITLE') }}
              </span>
            </div>
            <ExpensesByCategory
              :data="expByCategoryData"
              :loading="expByCategoryLoading"
            />
          </template>

          <!-- Fixo vs Variável (Gráfico #14) -->
          <template v-if="element.id === 'cost_structure'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-area-chart financial-block__icon financial-block__icon--expense"
                />
                {{ t('FINANCIAL.CHARTS.COST_STRUCTURE.TITLE') }}
              </span>
            </div>
            <FixedVsVariableCosts
              :data="costStructureData"
              :loading="costStructureLoading"
            />
          </template>

          <!-- Funil de Conversão (Gráfico #15) -->
          <template v-if="element.id === 'conversion_funnel'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-filter financial-block__icon financial-block__icon--info"
                />
                {{ t('FINANCIAL.CHARTS.FUNNEL.TITLE') }}
              </span>
            </div>
            <ConversionFunnel :data="funnelData" :loading="funnelLoading" />
          </template>

          <!-- Heatmap de Agenda (Gráfico #16) -->
          <template v-if="element.id === 'agenda_heatmap'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-calendar-days financial-block__icon financial-block__icon--info"
                />
                {{ t('FINANCIAL.CHARTS.HEATMAP.TITLE') }}
              </span>
            </div>
            <AgendaHeatmap :data="heatmapData" :loading="heatmapLoading" />
          </template>

          <!-- Novos vs Recorrentes (Gráfico #17) -->
          <template v-if="element.id === 'new_vs_returning'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-refresh-cw financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.CHARTS.RETENTION.TITLE') }}
              </span>
            </div>
            <NewVsReturningPatients
              :data="retentionData"
              :loading="retentionLoading"
            />
          </template>

          <!-- Delinquency -->
          <template v-if="element.id === 'delinquency'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-alert-triangle financial-block__icon financial-block__icon--warning"
                />
                {{ t('FINANCIAL.DASHBOARD.DELINQUENCY') }}
              </span>
            </div>
            <template v-if="loading">
              <div class="financial-skeleton financial-skeleton--row-lg" />
            </template>
            <template v-else>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.TOTAL_OVERDUE')
                }}</span>
                <span
                  class="financial-block__row-value financial-block__row-value--overdue"
                  >{{ formatCurrency(delinquency.total) }}</span
                >
              </div>
              <div class="financial-block__row">
                <span class="financial-block__row-label">{{
                  t('FINANCIAL.DASHBOARD.DELINQUENT_PATIENTS')
                }}</span>
                <span class="financial-block__row-value">{{
                  delinquency.count ?? 0
                }}</span>
              </div>
            </template>
          </template>

          <!-- Bank Accounts -->
          <template v-if="element.id === 'bank_accounts'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-landmark financial-block__icon financial-block__icon--info"
                />
                {{ t('FINANCIAL.DASHBOARD.BANK_ACCOUNTS') }}
              </span>
              <span
                v-if="!isCustomizing"
                class="financial-block__row-value financial-block__total-sm"
              >
                {{ formatCurrency(totalBankBalance) }}
              </span>
            </div>
            <template v-if="loading">
              <div class="financial-skeleton financial-skeleton--block" />
            </template>
            <div v-else class="financial-bank-accounts">
              <div
                v-for="account in bankAccounts"
                :key="account.id"
                class="financial-bank-account-item"
              >
                <span class="financial-bank-account-item__name">{{
                  account.name
                }}</span>
                <span class="financial-bank-account-item__balance">{{
                  formatCurrency(account.current_balance)
                }}</span>
              </div>
              <div v-if="!bankAccounts.length" class="financial-empty">
                <span class="financial-empty__text">{{
                  t('FINANCIAL.DASHBOARD.NO_ACCOUNTS')
                }}</span>
              </div>
            </div>
          </template>

          <!-- Expenses by category -->
          <template v-if="element.id === 'expenses'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-pie-chart financial-block__icon financial-block__icon--expense"
                />
                {{ t('FINANCIAL.DASHBOARD.EXPENSES_BY_CATEGORY') }}
              </span>
            </div>
            <template v-if="loading">
              <div class="financial-skeleton financial-skeleton--block" />
            </template>
            <template v-else>
              <div v-if="!expensesByCategory.length" class="financial-empty">
                {{ t('FINANCIAL.DASHBOARD.NO_DATA') }}
              </div>
              <div v-else class="financial-cat-list">
                <div
                  v-for="cat in expensesByCategory"
                  :key="cat.category_name"
                  class="financial-cat-item"
                >
                  <div class="financial-cat-item__top">
                    <span class="financial-cat-item__label">
                      <span
                        class="financial-category-dot"
                        :style="{ backgroundColor: cat.color }"
                      />
                      {{ cat.category_name }}
                    </span>
                    <span class="financial-cat-item__value">
                      {{ formatCurrency(cat.amount) }}
                    </span>
                  </div>
                  <div v-if="maxExpense > 0" class="financial-chart-bar">
                    <div
                      class="financial-chart-fill"
                      :style="{
                        backgroundColor: cat.color || 'var(--color-woot-500)',
                        width:
                          Math.max((cat.amount / maxExpense) * 100, 2) + '%',
                      }"
                    />
                  </div>
                </div>
              </div>
            </template>
          </template>

          <!-- Revenue by insurance -->
          <template v-if="element.id === 'revenue'">
            <div class="financial-block__header">
              <span class="financial-block__title">
                <i
                  v-if="isCustomizing"
                  class="i-lucide-grip-vertical financial-drag-handle"
                />
                <i
                  v-else
                  class="i-lucide-file-text financial-block__icon financial-block__icon--income"
                />
                {{ t('FINANCIAL.DASHBOARD.REVENUE_BY_INSURANCE') }}
              </span>
            </div>
            <template v-if="loading">
              <div class="financial-skeleton financial-skeleton--block" />
            </template>
            <template v-else>
              <div v-if="!revenueByInsurance.length" class="financial-empty">
                {{ t('FINANCIAL.DASHBOARD.NO_DATA') }}
              </div>
              <div v-else class="financial-insurance-list">
                <div
                  v-for="rev in revenueByInsurance"
                  :key="rev.label"
                  class="financial-insurance-item"
                >
                  <div class="financial-insurance-item__header">
                    <div class="financial-insurance-item__name">
                      <span class="financial-insurance-item__badge">
                        {{ rev.count }}
                      </span>
                      <span :title="rev.label">{{ rev.label }}</span>
                    </div>
                    <div class="financial-insurance-item__values">
                      <span class="financial-insurance-item__ticket">
                        {{ t('FINANCIAL.DASHBOARD.AVERAGE_TICKET') }}
                        {{
                          formatCurrency(
                            rev.count > 0 ? rev.amount / rev.count : 0
                          )
                        }}
                      </span>
                      <span class="financial-insurance-item__total">
                        {{ formatCurrency(rev.amount) }}
                      </span>
                    </div>
                  </div>
                  <div v-if="maxRevenue > 0" class="financial-chart-bar">
                    <div
                      class="financial-chart-fill financial-chart-fill--primary"
                      :style="{
                        width:
                          Math.max((rev.amount / maxRevenue) * 100, 2) + '%',
                      }"
                    />
                  </div>
                </div>
              </div>
            </template>
          </template>
        </div>
      </template>
    </draggable>
  </div>
</template>
