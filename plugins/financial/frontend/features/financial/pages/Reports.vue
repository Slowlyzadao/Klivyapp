<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from '../api/reports';
import { downloadFinancialPdf } from '../api/pdfs';
import { useExportCsv } from '../composables/useExportCsv';
import { usePermissions } from 'dashboard/composables/usePermissions';
import MonthPicker from '../components/MonthPicker.vue';
import DatePicker from '../components/DatePicker.vue';
import '../financial.css';

const { t } = useI18n();
const { exportReportsCsv } = useExportCsv();
const { can } = usePermissions();
const canExportData = computed(() => can('financial', 'export_data'));

/* ── Tabs ─────────────────────────────────────────────────────── */
const TABS = [
  'commissions',
  'expenses_by_category',
  'insurance',
  'average_ticket',
];
const activeTab = ref('commissions');

const TAB_ICONS = {
  commissions: 'i-lucide-percent',
  expenses_by_category: 'i-lucide-pie-chart',
  insurance: 'i-lucide-building-2',
  average_ticket: 'i-lucide-trending-up',
};

/* ── Shared period helpers ───────────────────────────────────── */
const PERIODS = ['month', 'quarter', 'year', 'custom'];

function buildPeriodParams(period, date, startDate, endDate) {
  const params = { period };
  if (period === 'custom') {
    params.start_date = startDate;
    params.end_date = endDate;
  } else {
    params.date = period === 'year' ? String(date).slice(0, 4) : date;
  }
  return params;
}

/* ── Agents list ─────────────────────────────────────────────── */
/* global axios */
const agents = ref([]);

async function loadAgents() {
  const accountId = window.location.pathname.match(/accounts\/(\d+)/)?.[1];
  if (!accountId) return;
  try {
    const { data } = await axios.get(`/api/v1/accounts/${accountId}/agents`);
    agents.value = data || [];
  } catch {
    // silent
  }
}

/* ── Helpers ─────────────────────────────────────────────────── */
function fmt(val) {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
  }).format(val || 0);
}

function fmtDate(str) {
  if (!str) return '—';
  const [y, m, d] = str.split('-');
  return `${d}/${m}/${y}`;
}

function typeBadgeClass(type) {
  return type === 'fixed_value'
    ? 'comm-type-badge--fixed'
    : 'comm-type-badge--pct';
}

function typeLabel(type) {
  const map = {
    percentage_production: t('FINANCIAL.COMMISSIONS.TYPE_PCT_PROD'),
    percentage_received: t('FINANCIAL.COMMISSIONS.TYPE_PCT_REC'),
    fixed_value: t('FINANCIAL.COMMISSIONS.TYPE_FIXED'),
  };
  return map[type] ?? type;
}

function pctOf(amount, total) {
  if (!total) return '0%';
  return `${((amount / total) * 100).toFixed(1)}%`;
}

function barWidth(amount, max) {
  return max > 0 ? `${(amount / max) * 100}%` : '0%';
}

/* ══════════════════════════════════════════════════════════════
   TAB 1 — COMMISSIONS
   ══════════════════════════════════════════════════════════════ */
const commPeriod = ref('month');
const commDate = ref(new Date().toISOString().slice(0, 7));
const commStartDate = ref('');
const commEndDate = ref('');
const selectedAgentId = ref('');
const commLoading = ref(false);
const commResult = ref(null);
const commError = ref('');

const commTransactions = computed(() => commResult.value?.transactions ?? []);
const commTotal = computed(() => commResult.value?.total_commission ?? 0);
const commCount = computed(() => commResult.value?.transaction_count ?? 0);
const commProfessional = computed(() => commResult.value?.professional ?? null);

async function fetchCommissions() {
  if (!selectedAgentId.value) {
    commError.value = t('FINANCIAL.COMMISSIONS.ERROR_NO_AGENT');
    return;
  }
  commLoading.value = true;
  commError.value = '';
  commResult.value = null;

  const params = {
    professional_id: selectedAgentId.value,
    ...buildPeriodParams(
      commPeriod.value,
      commDate.value,
      commStartDate.value,
      commEndDate.value
    ),
  };

  try {
    const { data } = await reportsAPI.commissions(params);
    commResult.value = data;
  } catch {
    commError.value = t('FINANCIAL.COMMISSIONS.ERROR_LOAD');
  } finally {
    commLoading.value = false;
  }
}

function exportCommissionsCSV() {
  if (!selectedAgentId.value) return;
  exportReportsCsv('commissions', commResult.value, {
    period: commPeriod.value,
  });
}

function exportCommissionsPdf() {
  if (!selectedAgentId.value) return;
  downloadFinancialPdf('commissions', {
    professional_id: selectedAgentId.value,
    ...buildPeriodParams(
      commPeriod.value,
      commDate.value,
      commStartDate.value,
      commEndDate.value
    ),
  });
}

/* ══════════════════════════════════════════════════════════════
   TAB 2 — EXPENSES BY CATEGORY
   ══════════════════════════════════════════════════════════════ */
const expPeriod = ref('month');
const expDate = ref(new Date().toISOString().slice(0, 7));
const expStartDate = ref('');
const expEndDate = ref('');
const expLoading = ref(false);
const expResult = ref(null);

const expRows = computed(() => {
  if (!expResult.value) return [];
  return (expResult.value.expense_rows ?? [])
    .filter(r => r.amount > 0)
    .sort((a, b) => b.amount - a.amount);
});

const expTotal = computed(() =>
  expRows.value.reduce((s, r) => s + r.amount, 0)
);

const maxExpAmount = computed(() =>
  Math.max(...expRows.value.map(r => r.amount), 1)
);

async function fetchExpensesByCategory() {
  expLoading.value = true;
  expResult.value = null;

  const params = buildPeriodParams(
    expPeriod.value,
    expDate.value,
    expStartDate.value,
    expEndDate.value
  );

  try {
    const { data } = await reportsAPI.dre(params);
    expResult.value = data.current;
  } catch {
    // silent
  } finally {
    expLoading.value = false;
  }
}

/* ══════════════════════════════════════════════════════════════
   TAB 3 — INSURANCE (Faturamento por Convênio)
   ══════════════════════════════════════════════════════════════ */
const insPeriod = ref('month');
const insDate = ref(new Date().toISOString().slice(0, 7));
const insStartDate = ref('');
const insEndDate = ref('');
const insLoading = ref(false);
const insResult = ref(null);

const insRows = computed(() => insResult.value?.rows ?? []);
const insTotal = computed(() => insResult.value?.total ?? 0);
const insCount = computed(() => insResult.value?.count ?? 0);
const maxInsAmount = computed(() =>
  Math.max(...insRows.value.map(r => r.amount), 1)
);

async function fetchInsurance() {
  insLoading.value = true;
  insResult.value = null;
  const params = buildPeriodParams(
    insPeriod.value,
    insDate.value,
    insStartDate.value,
    insEndDate.value
  );
  try {
    const { data } = await reportsAPI.insurance(params);
    insResult.value = data;
  } catch {
    // silent
  } finally {
    insLoading.value = false;
  }
}

function exportInsuranceCSV() {
  exportReportsCsv('insurance', insResult.value, {});
}

function exportInsurancePdf() {
  downloadFinancialPdf(
    'insurance',
    buildPeriodParams(
      insPeriod.value,
      insDate.value,
      insStartDate.value,
      insEndDate.value
    )
  );
}

function exportExpensesPdf() {
  downloadFinancialPdf('expenses_by_category', {
    period: expDate.value,
  });
}

function exportExpensesCsv() {
  exportReportsCsv('expenses', expRows.value, {});
}

/* ══════════════════════════════════════════════════════════════
   TAB 4 — AVERAGE TICKET
   ══════════════════════════════════════════════════════════════ */
const tickPeriod = ref('month');
const tickDate = ref(new Date().toISOString().slice(0, 7));
const tickStartDate = ref('');
const tickEndDate = ref('');
const tickGroupBy = ref('professional');
const tickLoading = ref(false);
const tickResult = ref(null);

const tickRows = computed(() => tickResult.value?.rows ?? []);
const tickOverall = computed(() => tickResult.value?.overall ?? null);
const maxTicket = computed(() =>
  Math.max(...tickRows.value.map(r => r.ticket), 1)
);

async function fetchAverageTicket() {
  tickLoading.value = true;
  tickResult.value = null;
  const params = {
    group_by: tickGroupBy.value,
    ...buildPeriodParams(
      tickPeriod.value,
      tickDate.value,
      tickStartDate.value,
      tickEndDate.value
    ),
  };
  try {
    const { data } = await reportsAPI.averageTicket(params);
    tickResult.value = data;
  } catch {
    // silent
  } finally {
    tickLoading.value = false;
  }
}

function exportTicketPdf() {
  downloadFinancialPdf('average_ticket', {
    group_by: tickGroupBy.value,
    ...buildPeriodParams(
      tickPeriod.value,
      tickDate.value,
      tickStartDate.value,
      tickEndDate.value
    ),
  });
}

function exportTicketCsv() {
  exportReportsCsv(
    'ticket',
    {
      items: tickRows.value,
      overall: tickOverall.value,
    },
    { groupBy: tickGroupBy.value }
  );
}

/* ── Init ────────────────────────────────────────────────────── */
onMounted(() => {
  loadAgents();
  fetchExpensesByCategory();
  fetchInsurance();
  fetchAverageTicket();
});
</script>

<template>
  <div class="financial-page">
    <!-- Page header -->
    <div class="financial-header">
      <div>
        <h1 class="financial-title">
          {{ t('FINANCIAL.REPORTS.TITLE') }}
        </h1>
        <p class="financial-subtitle">
          {{ t('FINANCIAL.REPORTS.SUBTITLE') }}
        </p>
      </div>
    </div>

    <!-- Tab bar -->
    <div class="w-full flex justify-start">
      <div class="rep-tabs">
        <button
          v-for="tab in TABS"
          :key="tab"
          class="rep-tab"
          :class="{ 'rep-tab--active': activeTab === tab }"
          @click="activeTab = tab"
        >
          <i :class="TAB_ICONS[tab]" />
          {{ t(`FINANCIAL.REPORTS.TAB_${tab.toUpperCase()}`) }}
        </button>
      </div>
    </div>

    <!-- ══════════════════════════════════════════════════════════
       TAB: COMMISSIONS
       ══════════════════════════════════════════════════════════ -->
    <template v-if="activeTab === 'commissions'">
      <!-- Filters -->
      <div class="rep-filters">
        <div class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.COMMISSIONS.PROFESSIONAL') }}
          </span>
          <select v-model="selectedAgentId" class="rep-select">
            <option value="">
              {{ t('FINANCIAL.COMMISSIONS.SELECT_AGENT') }}
            </option>
            <option v-for="agent in agents" :key="agent.id" :value="agent.id">
              {{ agent.name }}
            </option>
          </select>
        </div>

        <div class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.COMMISSIONS.PERIOD') }}
          </span>
          <div class="rep-period-tabs">
            <button
              v-for="p in PERIODS"
              :key="p"
              class="rep-period-tab"
              :class="{ 'rep-period-tab--active': commPeriod === p }"
              @click="commPeriod = p"
            >
              {{ t(`FINANCIAL.COMMISSIONS.PERIOD_${p.toUpperCase()}`) }}
            </button>
          </div>
        </div>

        <div v-if="commPeriod !== 'custom'" class="rep-filter-group">
          <span class="rep-filter-label">
            {{
              commPeriod === 'year'
                ? t('FINANCIAL.COMMISSIONS.YEAR')
                : t('FINANCIAL.COMMISSIONS.MONTH')
            }}
          </span>
          <MonthPicker v-model="commDate" />
        </div>

        <template v-if="commPeriod === 'custom'">
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.START_DATE') }}
            </span>
            <DatePicker v-model="commStartDate" />
          </div>
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.END_DATE') }}
            </span>
            <DatePicker v-model="commEndDate" />
          </div>
        </template>

        <div class="rep-filter-actions">
          <button
            class="rep-apply-btn"
            :disabled="commLoading || !selectedAgentId"
            @click="fetchCommissions"
          >
            <i class="i-lucide-search" />
            {{ t('FINANCIAL.COMMISSIONS.SEARCH') }}
          </button>
          <button
            v-if="commResult && canExportData"
            class="financial-btn--csv"
            :title="t('FINANCIAL.REPORTS.EXPORT_CSV')"
            @click="exportCommissionsCSV"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <rect width="24" height="24" rx="3" fill="#1e7e34" />
              <rect x="4" y="6" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="11" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="16" width="10" height="2" rx="1" fill="white" />
              <rect
                x="8"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
              <rect
                x="14"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
            </svg>
          </button>
          <button
            v-if="commResult && canExportData"
            class="rep-export-btn"
            @click="exportCommissionsPdf"
          >
            <i class="i-lucide-file-down" />
            Gerar PDF
          </button>
        </div>
      </div>

      <p v-if="commError" class="financial-empty__text">
        {{ commError }}
      </p>

      <div v-if="commLoading" class="financial-loading">
        <i class="i-lucide-loader-2 financial-loading__spinner" />
        {{ t('FINANCIAL.COMMISSIONS.LOADING') }}
      </div>

      <div
        v-else-if="!commResult && !commLoading"
        class="financial-empty rep-empty-min"
      >
        <i class="i-lucide-percent financial-empty__icon" />
        <p class="financial-empty__text">
          {{ t('FINANCIAL.COMMISSIONS.EMPTY_PROMPT') }}
        </p>
      </div>

      <template v-else-if="commResult">
        <div class="comm-summary">
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.COMMISSIONS.PROFESSIONAL') }}
            </span>
            <span class="comm-kpi__value">
              {{ commProfessional?.name ?? '—' }}
            </span>
          </div>
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.COMMISSIONS.TRANSACTIONS') }}
            </span>
            <span class="comm-kpi__value">{{ commCount }}</span>
          </div>
          <div class="comm-kpi comm-kpi--total">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.COMMISSIONS.TOTAL') }}
            </span>
            <span class="comm-kpi__value comm-kpi__value--profit">
              {{ fmt(commTotal) }}
            </span>
          </div>
        </div>

        <div v-if="commTransactions.length" class="rep-card">
          <div class="rep-table-wrap">
            <table class="rep-table">
              <thead>
                <tr>
                  <th class="rep-th">
                    {{ t('FINANCIAL.COMMISSIONS.COL_DESCRIPTION') }}
                  </th>
                  <th class="rep-th">
                    {{ t('FINANCIAL.COMMISSIONS.COL_CATEGORY') }}
                  </th>
                  <th class="rep-th">
                    {{ t('FINANCIAL.COMMISSIONS.COL_RECEIVED_AT') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.COMMISSIONS.COL_AMOUNT') }}
                  </th>
                  <th class="rep-th">
                    {{ t('FINANCIAL.COMMISSIONS.COL_RULE') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.COMMISSIONS.COL_COMMISSION') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="tx in commTransactions"
                  :key="tx.transaction_id"
                  class="rep-row"
                >
                  <td class="rep-td">{{ tx.description || '—' }}</td>
                  <td class="rep-td fin-text-secondary">
                    {{ tx.category_name || '—' }}
                  </td>
                  <td class="rep-td fin-text-secondary">
                    {{ fmtDate(tx.received_at) }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ fmt(tx.amount) }}
                  </td>
                  <td class="rep-td">
                    <span
                      class="comm-type-badge"
                      :class="typeBadgeClass(tx.rule_type)"
                    >
                      {{ typeLabel(tx.rule_type) }}
                      <span v-if="tx.rule_type !== 'fixed_value'">
                        {{ tx.rule_value }}%
                      </span>
                      <span v-else>{{ fmt(tx.rule_value) }}</span>
                    </span>
                  </td>
                  <td class="rep-td rep-td--num comm-val--positive">
                    {{ fmt(tx.commission_amount) }}
                  </td>
                </tr>
                <tr class="rep-row rep-row--total">
                  <td class="rep-td" colspan="5">
                    {{ t('FINANCIAL.COMMISSIONS.TOTAL') }}
                  </td>
                  <td class="rep-td rep-td--num comm-val--positive">
                    {{ fmt(commTotal) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div v-else class="financial-empty">
          <i class="i-lucide-search-x financial-empty__icon" />
          <p class="financial-empty__text">
            {{ t('FINANCIAL.COMMISSIONS.EMPTY') }}
          </p>
        </div>
      </template>
    </template>

    <!-- ══════════════════════════════════════════════════════════
       TAB: EXPENSES BY CATEGORY
       ══════════════════════════════════════════════════════════ -->
    <template v-if="activeTab === 'expenses_by_category'">
      <div class="rep-filters">
        <div class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.REPORTS.PERIOD') }}
          </span>
          <div class="rep-period-tabs">
            <button
              v-for="p in PERIODS"
              :key="p"
              class="rep-period-tab"
              :class="{ 'rep-period-tab--active': expPeriod === p }"
              @click="expPeriod = p"
            >
              {{ t(`FINANCIAL.COMMISSIONS.PERIOD_${p.toUpperCase()}`) }}
            </button>
          </div>
        </div>

        <div v-if="expPeriod !== 'custom'" class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.COMMISSIONS.MONTH') }}
          </span>
          <MonthPicker v-model="expDate" />
        </div>

        <template v-if="expPeriod === 'custom'">
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.START_DATE') }}
            </span>
            <DatePicker v-model="expStartDate" />
          </div>
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.END_DATE') }}
            </span>
            <DatePicker v-model="expEndDate" />
          </div>
        </template>

        <div class="rep-filter-actions">
          <button
            class="rep-apply-btn"
            :disabled="expLoading"
            @click="fetchExpensesByCategory"
          >
            <i class="i-lucide-search" />
            {{ t('FINANCIAL.COMMISSIONS.SEARCH') }}
          </button>
          <button
            v-if="expResult && canExportData"
            class="rep-export-btn"
            @click="exportExpensesPdf"
          >
            <i class="i-lucide-file-down" />
            Gerar PDF
          </button>
          <button
            v-if="expResult && canExportData"
            class="financial-btn--csv"
            title="Exportar para Google Sheets (CSV)"
            @click="exportExpensesCsv"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <rect width="24" height="24" rx="3" fill="#1e7e34" />
              <rect x="4" y="6" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="11" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="16" width="10" height="2" rx="1" fill="white" />
              <rect
                x="8"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
              <rect
                x="14"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
            </svg>
          </button>
        </div>
      </div>

      <div v-if="expLoading" class="financial-loading">
        <i class="i-lucide-loader-2 financial-loading__spinner" />
        {{ t('FINANCIAL.REPORTS.LOADING') }}
      </div>

      <template v-else-if="expResult">
        <div class="exp-cat-chart-block">
          <p class="exp-cat-chart-block__title">
            {{ t('FINANCIAL.REPORTS.EXP_CAT_CHART_TITLE') }}
          </p>

          <div v-if="expRows.length" class="exp-cat-bar-list">
            <div
              v-for="row in expRows"
              :key="row.category_id"
              class="exp-cat-bar-row"
            >
              <div class="exp-cat-bar-row__header">
                <span class="exp-cat-bar-row__name">
                  <span
                    class="rep-color-dot"
                    :style="{ background: row.color }"
                  />
                  <span class="rep-name-text">{{ row.category_name }}</span>
                </span>
                <div class="exp-cat-bar-row__values">
                  <span class="exp-cat-bar-row__amount">{{
                    fmt(row.amount)
                  }}</span>
                  <span class="exp-cat-bar-row__pct">
                    {{ pctOf(row.amount, expTotal) }}
                  </span>
                </div>
              </div>
              <div class="exp-cat-track">
                <div
                  class="exp-cat-fill"
                  :style="{
                    width: barWidth(row.amount, maxExpAmount),
                    background: row.color,
                  }"
                />
              </div>
            </div>
          </div>

          <div v-else class="financial-empty">
            <i class="i-lucide-search-x financial-empty__icon" />
            <p class="financial-empty__text">
              {{ t('FINANCIAL.REPORTS.EMPTY') }}
            </p>
          </div>
        </div>

        <div v-if="expRows.length" class="rep-card">
          <div class="rep-table-wrap">
            <table class="rep-table">
              <thead>
                <tr>
                  <th class="rep-th">
                    {{ t('FINANCIAL.REPORTS.EXP_COL_CATEGORY') }}
                  </th>
                  <th class="rep-th">
                    {{ t('FINANCIAL.REPORTS.EXP_COL_TYPE') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.EXP_COL_AMOUNT') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.EXP_COL_PCT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in expRows"
                  :key="row.category_id"
                  class="rep-row"
                >
                  <td class="rep-td">
                    <span class="fin-flex-center fin-gap-sm">
                      <span
                        class="rep-color-dot"
                        :style="{ background: row.color }"
                      />
                      <span class="rep-name-text">{{ row.category_name }}</span>
                    </span>
                  </td>
                  <td class="rep-td fin-text-secondary">
                    {{ row.cost_type || '—' }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ fmt(row.amount) }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ pctOf(row.amount, expTotal) }}
                  </td>
                </tr>
                <tr class="rep-row rep-row--total">
                  <td class="rep-td" colspan="2">
                    {{ t('FINANCIAL.REPORTS.TOTAL') }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ fmt(expTotal) }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ t('FINANCIAL.REPORTS.PCT_TOTAL') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>

      <div v-else class="financial-empty">
        <i class="i-lucide-pie-chart financial-empty__icon" />
        <p class="financial-empty__text">
          {{ t('FINANCIAL.REPORTS.EMPTY') }}
        </p>
      </div>
    </template>

    <!-- ══════════════════════════════════════════════════════════
       TAB: INSURANCE — Faturamento por Convênio
       ══════════════════════════════════════════════════════════ -->
    <template v-if="activeTab === 'insurance'">
      <div class="rep-filters">
        <div class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.REPORTS.PERIOD') }}
          </span>
          <div class="rep-period-tabs">
            <button
              v-for="p in PERIODS"
              :key="p"
              class="rep-period-tab"
              :class="{ 'rep-period-tab--active': insPeriod === p }"
              @click="insPeriod = p"
            >
              {{ t(`FINANCIAL.COMMISSIONS.PERIOD_${p.toUpperCase()}`) }}
            </button>
          </div>
        </div>

        <div v-if="insPeriod !== 'custom'" class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.COMMISSIONS.MONTH') }}
          </span>
          <MonthPicker v-model="insDate" />
        </div>

        <template v-if="insPeriod === 'custom'">
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.START_DATE') }}
            </span>
            <DatePicker v-model="insStartDate" />
          </div>
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.END_DATE') }}
            </span>
            <DatePicker v-model="insEndDate" />
          </div>
        </template>

        <div class="rep-filter-actions">
          <button
            class="rep-apply-btn"
            :disabled="insLoading"
            @click="fetchInsurance"
          >
            <i class="i-lucide-search" />
            {{ t('FINANCIAL.COMMISSIONS.SEARCH') }}
          </button>
          <button
            v-if="insResult && canExportData"
            class="financial-btn--csv"
            :title="t('FINANCIAL.REPORTS.EXPORT_CSV')"
            @click="exportInsuranceCSV"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <rect width="24" height="24" rx="3" fill="#1e7e34" />
              <rect x="4" y="6" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="11" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="16" width="10" height="2" rx="1" fill="white" />
              <rect
                x="8"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
              <rect
                x="14"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
            </svg>
          </button>
          <button
            v-if="insResult && canExportData"
            class="rep-export-btn"
            @click="exportInsurancePdf"
          >
            <i class="i-lucide-file-down" />
            Gerar PDF
          </button>
        </div>
      </div>

      <div v-if="insLoading" class="financial-loading">
        <i class="i-lucide-loader-2 financial-loading__spinner" />
        {{ t('FINANCIAL.REPORTS.LOADING') }}
      </div>

      <template v-else-if="insResult">
        <!-- KPI cards -->
        <div class="comm-summary">
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.REPORTS.INS_TOTAL_RECEITAS') }}
            </span>
            <span class="comm-kpi__value comm-kpi__value--profit">
              {{ fmt(insTotal) }}
            </span>
          </div>
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.REPORTS.INS_TOTAL_ATENDIMENTOS') }}
            </span>
            <span class="comm-kpi__value">{{ insCount }}</span>
          </div>
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.REPORTS.INS_TICKET_MEDIO') }}
            </span>
            <span class="comm-kpi__value">
              {{ insCount > 0 ? fmt(insTotal / insCount) : '—' }}
            </span>
          </div>
        </div>

        <!-- Bar list -->
        <div v-if="insRows.length" class="exp-cat-chart-block">
          <p class="exp-cat-chart-block__title">
            {{ t('FINANCIAL.REPORTS.INS_CHART_TITLE') }}
          </p>
          <div class="exp-cat-bar-list">
            <div
              v-for="(row, idx) in insRows"
              :key="idx"
              class="exp-cat-bar-row"
            >
              <div class="exp-cat-bar-row__header">
                <span class="exp-cat-bar-row__name">
                  <span class="rep-color-dot rep-ins-dot" />
                  <span class="rep-name-text">{{ row.label }}</span>
                </span>
                <div class="exp-cat-bar-row__values">
                  <span class="exp-cat-bar-row__amount">
                    {{ fmt(row.amount) }}
                  </span>
                  <span class="exp-cat-bar-row__pct">
                    {{ pctOf(row.amount, insTotal) }}
                    ({{ row.count }})
                  </span>
                </div>
              </div>
              <div class="exp-cat-track">
                <div
                  class="exp-cat-fill rep-ins-fill"
                  :style="{ width: barWidth(row.amount, maxInsAmount) }"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Table -->
        <div v-if="insRows.length" class="rep-card">
          <div class="rep-table-wrap">
            <table class="rep-table">
              <thead>
                <tr>
                  <th class="rep-th">
                    {{ t('FINANCIAL.REPORTS.INS_COL_CONVENIO') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.INS_COL_ATENDIMENTOS') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.INS_COL_TOTAL') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.INS_COL_TICKET') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.EXP_COL_PCT') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(row, idx) in insRows" :key="idx" class="rep-row">
                  <td class="rep-td">
                    <span class="fin-flex-center fin-gap-sm">
                      <span class="rep-color-dot rep-ins-dot" />
                      <span class="rep-name-text">{{ row.label }}</span>
                    </span>
                  </td>
                  <td class="rep-td rep-td--num fin-text-secondary">
                    {{ row.count }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ fmt(row.amount) }}
                  </td>
                  <td class="rep-td rep-td--num fin-text-secondary">
                    {{ row.count > 0 ? fmt(row.amount / row.count) : '—' }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ pctOf(row.amount, insTotal) }}
                  </td>
                </tr>
                <tr class="rep-row rep-row--total">
                  <td class="rep-td">
                    {{ t('FINANCIAL.REPORTS.TOTAL') }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ insCount }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ fmt(insTotal) }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ insCount > 0 ? fmt(insTotal / insCount) : '—' }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ t('FINANCIAL.REPORTS.PCT_TOTAL') }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>

      <div v-else class="financial-empty">
        <i class="i-lucide-building-2 financial-empty__icon" />
        <p class="financial-empty__text">
          {{ t('FINANCIAL.REPORTS.EMPTY') }}
        </p>
      </div>
    </template>

    <!-- ══════════════════════════════════════════════════════════
       TAB: AVERAGE TICKET — Ticket Médio
       ══════════════════════════════════════════════════════════ -->
    <template v-if="activeTab === 'average_ticket'">
      <div class="rep-filters">
        <div class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.REPORTS.PERIOD') }}
          </span>
          <div class="rep-period-tabs">
            <button
              v-for="p in PERIODS"
              :key="p"
              class="rep-period-tab"
              :class="{ 'rep-period-tab--active': tickPeriod === p }"
              @click="tickPeriod = p"
            >
              {{ t(`FINANCIAL.COMMISSIONS.PERIOD_${p.toUpperCase()}`) }}
            </button>
          </div>
        </div>

        <!-- Group by toggle -->
        <div class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.REPORTS.TICK_GROUP_BY') }}
          </span>
          <div class="rep-period-tabs">
            <button
              class="rep-period-tab"
              :class="{
                'rep-period-tab--active': tickGroupBy === 'professional',
              }"
              @click="tickGroupBy = 'professional'"
            >
              {{ t('FINANCIAL.REPORTS.TICK_BY_PROFESSIONAL') }}
            </button>
            <button
              class="rep-period-tab"
              :class="{ 'rep-period-tab--active': tickGroupBy === 'month' }"
              @click="tickGroupBy = 'month'"
            >
              {{ t('FINANCIAL.REPORTS.TICK_BY_MONTH') }}
            </button>
          </div>
        </div>

        <div v-if="tickPeriod !== 'custom'" class="rep-filter-group">
          <span class="rep-filter-label">
            {{ t('FINANCIAL.COMMISSIONS.MONTH') }}
          </span>
          <MonthPicker v-model="tickDate" />
        </div>

        <template v-if="tickPeriod === 'custom'">
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.START_DATE') }}
            </span>
            <DatePicker v-model="tickStartDate" />
          </div>
          <div class="rep-filter-group">
            <span class="rep-filter-label">
              {{ t('FINANCIAL.COMMISSIONS.END_DATE') }}
            </span>
            <DatePicker v-model="tickEndDate" />
          </div>
        </template>

        <div class="rep-filter-actions">
          <button
            class="rep-apply-btn"
            :disabled="tickLoading"
            @click="fetchAverageTicket"
          >
            <i class="i-lucide-search" />
            {{ t('FINANCIAL.COMMISSIONS.SEARCH') }}
          </button>
          <button
            v-if="tickResult && canExportData"
            class="rep-export-btn"
            @click="exportTicketPdf"
          >
            <i class="i-lucide-file-down" />
            Gerar PDF
          </button>
          <button
            v-if="tickResult && canExportData"
            class="financial-btn--csv"
            title="Exportar para Google Sheets (CSV)"
            @click="exportTicketCsv"
          >
            <svg
              viewBox="0 0 24 24"
              fill="none"
              xmlns="http://www.w3.org/2000/svg"
            >
              <rect width="24" height="24" rx="3" fill="#1e7e34" />
              <rect x="4" y="6" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="11" width="16" height="2" rx="1" fill="white" />
              <rect x="4" y="16" width="10" height="2" rx="1" fill="white" />
              <rect
                x="8"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
              <rect
                x="14"
                y="4"
                width="2"
                height="16"
                rx="1"
                fill="rgba(255,255,255,0.4)"
              />
            </svg>
          </button>
        </div>
      </div>

      <div v-if="tickLoading" class="financial-loading">
        <i class="i-lucide-loader-2 financial-loading__spinner" />
        {{ t('FINANCIAL.REPORTS.LOADING') }}
      </div>

      <template v-else-if="tickResult">
        <!-- Overall KPIs -->
        <div v-if="tickOverall" class="comm-summary">
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.REPORTS.TICK_TOTAL_TXNS') }}
            </span>
            <span class="comm-kpi__value">{{ tickOverall.count }}</span>
          </div>
          <div class="comm-kpi">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.REPORTS.TICK_TOTAL_REVENUE') }}
            </span>
            <span class="comm-kpi__value comm-kpi__value--profit">
              {{ fmt(tickOverall.total) }}
            </span>
          </div>
          <div class="comm-kpi comm-kpi--total">
            <span class="comm-kpi__label">
              {{ t('FINANCIAL.REPORTS.TICK_OVERALL_TICKET') }}
            </span>
            <span class="comm-kpi__value comm-kpi__value--profit">
              {{ fmt(tickOverall.ticket) }}
            </span>
          </div>
        </div>

        <!-- Bar list -->
        <div v-if="tickRows.length" class="exp-cat-chart-block">
          <p class="exp-cat-chart-block__title">
            {{
              tickGroupBy === 'professional'
                ? t('FINANCIAL.REPORTS.TICK_CHART_BY_PROF')
                : t('FINANCIAL.REPORTS.TICK_CHART_BY_MONTH')
            }}
          </p>
          <div class="exp-cat-bar-list">
            <div
              v-for="(row, idx) in tickRows"
              :key="idx"
              class="exp-cat-bar-row"
            >
              <div class="exp-cat-bar-row__header">
                <span class="exp-cat-bar-row__name">
                  <span class="rep-color-dot rep-tick-dot" />
                  {{
                    tickGroupBy === 'professional'
                      ? row.professional_name
                      : row.label
                  }}
                </span>
                <div class="exp-cat-bar-row__values">
                  <span class="exp-cat-bar-row__amount rep-tick-value">
                    {{ fmt(row.ticket) }}
                  </span>
                  <span class="exp-cat-bar-row__pct">
                    {{ row.count }}
                    {{ t('FINANCIAL.REPORTS.TICK_TXNS') }}
                  </span>
                </div>
              </div>
              <div class="exp-cat-track">
                <div
                  class="exp-cat-fill rep-tick-fill"
                  :style="{ width: barWidth(row.ticket, maxTicket) }"
                />
              </div>
            </div>
          </div>
        </div>

        <!-- Table -->
        <div v-if="tickRows.length" class="rep-card">
          <div class="rep-table-wrap">
            <table class="rep-table">
              <thead>
                <tr>
                  <th class="rep-th">
                    {{
                      tickGroupBy === 'professional'
                        ? t('FINANCIAL.COMMISSIONS.COL_PROFESSIONAL')
                        : t('FINANCIAL.REPORTS.TICK_COL_MONTH')
                    }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.TICK_COL_TXNS') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.TICK_COL_TOTAL') }}
                  </th>
                  <th class="rep-th rep-th--num">
                    {{ t('FINANCIAL.REPORTS.TICK_COL_TICKET') }}
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="(row, idx) in tickRows" :key="idx" class="rep-row">
                  <td class="rep-td">
                    <span class="fin-flex-center fin-gap-sm">
                      <span class="rep-color-dot rep-tick-dot" />
                      {{
                        tickGroupBy === 'professional'
                          ? row.professional_name
                          : row.label
                      }}
                    </span>
                  </td>
                  <td class="rep-td rep-td--num fin-text-secondary">
                    {{ row.count }}
                  </td>
                  <td class="rep-td rep-td--num">
                    {{ fmt(row.total) }}
                  </td>
                  <td class="rep-td rep-td--num rep-tick-value">
                    {{ fmt(row.ticket) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </template>

      <div v-else class="financial-empty">
        <i class="i-lucide-trending-up financial-empty__icon" />
        <p class="financial-empty__text">
          {{ t('FINANCIAL.REPORTS.EMPTY') }}
        </p>
      </div>
    </template>
  </div>
</template>
