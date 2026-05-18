<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import reportsApi from '../api/reports';
import transactionsApi from '../api/accountTransactions';
import bankAccountsApi from '../api/bankAccounts';
import { downloadFinancialPdf } from '../api/pdfs';
import { useExportCsv } from '../composables/useExportCsv';
import { useFormatCurrency } from '../composables/useFormatCurrency';
import { usePermissions } from 'dashboard/composables/usePermissions';
import TransactionModal from '../components/TransactionModal.vue';
import DateRangePicker from '../components/DateRangePicker.vue';
import '../financial.css';

const { formatCurrency } = useFormatCurrency();
const { exportCashFlowCsv } = useExportCsv();
const { can: klivyCan } = usePermissions();
const canCreateTransaction = computed(() =>
  klivyCan('financial', 'create_transaction')
);
const canExportData = computed(() => klivyCan('financial', 'export_data'));

const dateRange = ref([]);

const loading = ref(false);
const daily = ref([]);
const totals = ref(null);
const banksTotalBalance = ref(0);
const bankAccounts = ref([]);

const sortOrder = ref('date');
const showSortMenu = ref(false);

const sortOptions = [
  { value: 'date', label: 'Padrão (Por Data)' },
  { value: 'income_desc', label: 'Maiores Entradas' },
  { value: 'income_asc', label: 'Menores Entradas' },
  { value: 'expense_desc', label: 'Maiores Saídas' },
  { value: 'expense_asc', label: 'Menores Saídas' },
  { value: 'balance_desc', label: 'Maior Saldo' },
  { value: 'balance_asc', label: 'Menor Saldo' },
];

const setSortOrder = val => {
  sortOrder.value = val;
  showSortMenu.value = false;
};

const closeSortMenu = e => {
  if (!e.target.closest('.cf-sort-wrap')) {
    showSortMenu.value = false;
  }
};

const sortedDaily = computed(() => {
  if (!daily.value || !daily.value.length) return [];
  const arr = [...daily.value];
  if (sortOrder.value === 'income_desc')
    return arr.sort((a, b) => b.entradas - a.entradas);
  if (sortOrder.value === 'income_asc')
    return arr.sort((a, b) => a.entradas - b.entradas);
  if (sortOrder.value === 'expense_desc')
    return arr.sort((a, b) => b.saidas - a.saidas);
  if (sortOrder.value === 'expense_asc')
    return arr.sort((a, b) => a.saidas - b.saidas);
  if (sortOrder.value === 'balance_desc')
    return arr.sort((a, b) => b.saldo - a.saldo);
  if (sortOrder.value === 'balance_asc')
    return arr.sort((a, b) => a.saldo - b.saldo);
  return arr;
});

// Transaction modal
const showModal = ref(false);
const modalEntryType = ref('entrada');

async function fetchData() {
  loading.value = true;
  try {
    const params = {};
    if (dateRange.value && dateRange.value.length >= 1 && dateRange.value[0]) {
      params.period = 'custom';
      params.start_date = dateRange.value[0];
      params.end_date = dateRange.value[1] || dateRange.value[0];
    } else {
      params.period = 'month';
    }

    const [cfRes, baRes] = await Promise.all([
      reportsApi.cashFlow(params),
      bankAccountsApi.get(),
    ]);
    daily.value = cfRes.data.daily || [];
    totals.value = cfRes.data.totals || null;
    banksTotalBalance.value = baRes.data?.total_balance || 0;
    bankAccounts.value = baRes.data?.bank_accounts || [];
  } catch {
    // silent
  } finally {
    loading.value = false;
  }
}

const chartWrap = ref(null);
const chartW = ref(800);
let resizeObserver = null;

function updateWidth() {
  if (chartWrap.value) {
    chartW.value = chartWrap.value.clientWidth || 800;
  }
}

// Watch the template ref — fires when the v-else-if renders the element
watch(chartWrap, el => {
  if (resizeObserver) {
    resizeObserver.disconnect();
    resizeObserver = null;
  }
  if (el) {
    updateWidth();
    resizeObserver = new ResizeObserver(updateWidth);
    resizeObserver.observe(el);
  }
});

onMounted(() => {
  fetchData();
  document.addEventListener('click', closeSortMenu);
});

onUnmounted(() => {
  if (resizeObserver) resizeObserver.disconnect();
  document.removeEventListener('click', closeSortMenu);
});

function onFilter() {
  fetchData();
}

function clearDates() {
  dateRange.value = [];
  fetchData();
}

// SVG Line chart helpers
const CHART_H = 280;
const CHART_PAD_LEFT = 60;
const CHART_PAD_RIGHT = 20;
const CHART_PAD_TOP = 20;
const CHART_PAD_BOT = 36;

const chartMax = computed(() => {
  if (!daily.value.length) return 1;
  const max = Math.max(
    ...daily.value.map(d => Math.max(d.entradas, d.saidas)),
    1
  );
  return max * 1.25; // 25% extra headroom to prevent bezier control points from cutting off
});

const chartInnerW = computed(
  () => chartW.value - CHART_PAD_LEFT - CHART_PAD_RIGHT
);
const chartInnerH = CHART_H - CHART_PAD_TOP - CHART_PAD_BOT;

function xPos(index) {
  const count = daily.value.length;
  if (count <= 1) return CHART_PAD_LEFT + chartInnerW.value / 2;
  return CHART_PAD_LEFT + (index / (count - 1)) * chartInnerW.value;
}

function yPos(value) {
  const ratio = Math.min(value / chartMax.value, 1);
  return CHART_PAD_TOP + chartInnerH - ratio * chartInnerH;
}

// Função helper para gerar curva Bezier suave (Catmull-Rom para Bezier)
function smoothPath(points) {
  if (points.length === 0) return '';
  if (points.length === 1) return `M ${points[0][0]},${points[0][1]}`;
  if (points.length === 2)
    return `M ${points[0][0]},${points[0][1]} L ${points[1][0]},${points[1][1]}`;

  const getControlPoint = (prev, curr, next) => {
    const tension = 0.2; // Tensão da curva (menor = mais tenso)
    const dX = next[0] - prev[0];
    const dY = next[1] - prev[1];
    return [curr[0] + dX * tension, curr[1] + dY * tension];
  };

  let path = `M ${points[0][0]},${points[0][1]}`;

  for (let i = 0; i < points.length - 1; i++) {
    const p0 = i > 0 ? points[i - 1] : points[0];
    const p1 = points[i];
    const p2 = points[i + 1];
    const p3 = i !== points.length - 2 ? points[i + 2] : p2;

    const cp1 = getControlPoint(p0, p1, p2);
    const cp2 = getControlPoint(p3, p2, p1);

    path += ` C ${cp1[0]},${cp1[1]} ${cp2[0]},${cp2[1]} ${p2[0]},${p2[1]}`;
  }

  return path;
}

const incomePoints = computed(() =>
  daily.value.map((d, i) => [xPos(i), yPos(d.entradas)])
);
const expensePoints = computed(() =>
  daily.value.map((d, i) => [xPos(i), yPos(d.saidas)])
);

const incomeLine = computed(() => smoothPath(incomePoints.value));
const expenseLine = computed(() => smoothPath(expensePoints.value));

const incomeArea = computed(() => {
  if (!daily.value.length) return '';
  const baseY = CHART_PAD_TOP + chartInnerH;
  const lastX = xPos(daily.value.length - 1);
  return `${incomeLine.value} L ${lastX},${baseY} L ${CHART_PAD_LEFT},${baseY} Z`;
});

const expenseArea = computed(() => {
  if (!daily.value.length) return '';
  const baseY = CHART_PAD_TOP + chartInnerH;
  const lastX = xPos(daily.value.length - 1);
  return `${expenseLine.value} L ${lastX},${baseY} L ${CHART_PAD_LEFT},${baseY} Z`;
});

const yTicks = computed(() => {
  const max = chartMax.value;
  const steps = 4;
  return Array.from({ length: steps + 1 }, (_, i) => {
    const val = (max / steps) * (steps - i);
    const y = CHART_PAD_TOP + (chartInnerH / steps) * i;
    return { y, val };
  });
});

const xLabels = computed(() => {
  const count = daily.value.length;
  if (!count) return [];
  const maxLabels = 10;
  const step = Math.ceil(count / maxLabels);
  return daily.value
    .map((d, i) => ({ x: xPos(i), label: d.label, i }))
    .filter(item => item.i % step === 0 || item.i === count - 1);
});

const tooltipIndex = ref(null);
const tooltipData = computed(() => {
  if (tooltipIndex.value === null || !daily.value[tooltipIndex.value])
    return null;
  const d = daily.value[tooltipIndex.value];
  return {
    x: xPos(tooltipIndex.value),
    yIncome: yPos(d.entradas),
    yExpense: yPos(d.saidas),
    entradas: d.entradas,
    saidas: d.saidas,
    saldo: d.entradas - d.saidas,
    label: d.label,
  };
});

const balanceIsPositive = computed(() => {
  if (!totals.value) return true;
  return totals.value.saldo >= 0;
});

// Saldo atual em caixa = saldo_inicial do período + entradas - saídas
// saldo_inicial já inclui: initial_balance das contas + movimentações antes do período
const saldoAtual = computed(() => {
  if (!totals.value) return banksTotalBalance.value;
  const si = totals.value.saldo_inicial ?? 0;
  return si + (totals.value.entradas ?? 0) - (totals.value.saidas ?? 0);
});

const saldoAtualIsPositive = computed(() => saldoAtual.value >= 0);

const showAccounts = ref(false);

const getBankColorClass = bankName => {
  if (!bankName) return 'cf-bank-card--default';
  const name = bankName.toLowerCase();
  if (name.includes('bradesco')) return 'cf-bank-card--bradesco';
  if (name.includes('itaú') || name.includes('itau'))
    return 'cf-bank-card--itau';
  if (name.includes('nubank')) return 'cf-bank-card--nubank';
  if (name.includes('inter')) return 'cf-bank-card--inter';
  if (name.includes('santander')) return 'cf-bank-card--santander';
  if (name.includes('banco do brasil') || name.includes('bb'))
    return 'cf-bank-card--bb';
  if (name.includes('caixa')) return 'cf-bank-card--caixa';
  return 'cf-bank-card--default';
};

function formatShort(val) {
  const n = parseFloat(val) || 0;
  if (Math.abs(n) >= 1000) return `R$ ${(n / 1000).toFixed(1)}k`;
  return `R$ ${n.toFixed(0)}`;
}

const saldoClass = computed(() => {
  if (!totals.value) return '';
  return totals.value.saldo >= 0
    ? 'financial-summary-value--positive'
    : 'financial-summary-value--negative';
});

// Modal actions
function openNewEntry() {
  modalEntryType.value = 'entrada';
  showModal.value = true;
}

function openNewExpense() {
  modalEntryType.value = 'saida';
  showModal.value = true;
}

function exportPdf() {
  const params = {};
  if (dateRange.value && dateRange.value.length >= 1 && dateRange.value[0]) {
    params.start_date = dateRange.value[0];
    params.end_date = dateRange.value[1] || dateRange.value[0];
  }
  downloadFinancialPdf('cash_flow', params);
}

function exportCsv() {
  exportCashFlowCsv(sortedDaily.value, totals.value, dateRange.value);
}

async function handleSave({ payload }) {
  try {
    await transactionsApi.create(payload);
    showModal.value = false;
    fetchData();
  } catch {
    // silent
  }
}
</script>

<template>
  <div class="financial-page">
    <div class="financial-page__header">
      <div>
        <h1 class="financial-page__title">
          {{ $t('SIDEBAR.FINANCIAL_CASH_FLOW') }}
        </h1>
        <p class="financial-page__subtitle">
          {{ $t('FINANCIAL.CASH_FLOW.SUBTITLE') }}
        </p>
      </div>
      <div class="financial-header-actions">
        <button
          v-if="canCreateTransaction"
          class="financial-btn btn-new-entry-cf"
          @click="openNewEntry"
        >
          <span class="i-lucide-arrow-down-circle" />
          {{ $t('FINANCIAL.CASH_FLOW.NEW_ENTRY') }}
        </button>
        <button
          v-if="canCreateTransaction"
          class="financial-btn btn-new-expense-cf"
          @click="openNewExpense"
        >
          <span class="i-lucide-arrow-up-circle" />
          {{ $t('FINANCIAL.CASH_FLOW.NEW_EXPENSE') }}
        </button>
        <button
          v-if="canExportData"
          class="financial-btn financial-btn--pdf"
          title="Exportar PDF"
          @click="exportPdf"
        >
          <span class="i-lucide-file-down" />
          Gerar PDF
        </button>
        <button
          v-if="canExportData"
          class="financial-btn--csv"
          title="Exportar para Google Sheets (CSV)"
          @click="exportCsv"
        >
          <!-- Google Sheets icon -->
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
        <div class="financial-period-selector">
          <DateRangePicker
            v-model="dateRange"
            @update:model-value="onFilter"
            @clear="clearDates"
          />
        </div>
      </div>
    </div>

    <!-- KPI Summary -->
    <div v-if="loading" class="financial-grid financial-grid--4">
      <div
        v-for="n in 3"
        :key="n"
        class="financial-skeleton financial-skeleton--card"
      />
    </div>

    <div v-else-if="totals" class="financial-grid financial-grid--4">
      <div class="financial-summary-card financial-summary-card--income">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-arrow-down-circle cf-balance-icon" />
          {{ $t('FINANCIAL.CASH_FLOW.TOTAL_IN') }}
        </span>
        <span class="financial-summary-value cf-income-value">
          {{ formatCurrency(totals.entradas) }}
        </span>
        <span class="cf-balance-hint">Total de dinheiro que entrou na clínica</span>
      </div>
      <div class="financial-summary-card financial-summary-card--expense">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-arrow-up-circle cf-balance-icon" />
          {{ $t('FINANCIAL.CASH_FLOW.TOTAL_OUT') }}
        </span>
        <span class="financial-summary-value cf-expense-value">
          {{ formatCurrency(totals.saidas) }}
        </span>
        <span class="cf-balance-hint">Total de dinheiro que saiu</span>
      </div>
      <div class="financial-summary-card financial-summary-card--net">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-wallet cf-balance-icon" />
          {{ $t('FINANCIAL.CASH_FLOW.NET_BALANCE') }}
        </span>
        <span class="financial-summary-value" :class="saldoClass">
          {{ formatCurrency(totals.saldo) }}
        </span>
        <span class="cf-balance-hint">O que sobrou em caixa</span>
      </div>
      <!-- Saldo em Caixa: patrimônio acumulado real nas contas bancárias -->
      <div class="financial-summary-card cf-balance-card">
        <div class="cf-balance-header">
          <span class="financial-summary-label cf-balance-label">
            <span class="i-lucide-landmark cf-balance-icon" />
            Saldo em Caixa
          </span>
          <button
            class="cf-accounts-toggle-green"
            type="button"
            :title="showAccounts ? 'Ocultar contas' : 'Ver contas'"
            @click="showAccounts = !showAccounts"
          >
            <span
              :class="showAccounts ? 'i-lucide-eye-off' : 'i-lucide-eye'"
              class="cf-accounts-icon"
            />
          </button>
        </div>
        <span
          class="financial-summary-value"
          :class="
            saldoAtualIsPositive
              ? 'financial-summary-value--positive'
              : 'financial-summary-value--negative'
          "
        >
          {{ formatCurrency(saldoAtual) }}
        </span>
        <span class="cf-balance-hint">Patrimônio acumulado nas contas</span>
      </div>
    </div>

    <!-- Expandable: Saldo por conta bancária (Cards) -->
    <div
      v-show="showAccounts && bankAccounts.length"
      class="cf-accounts-cards-panel"
    >
      <div class="cf-accounts-cards-grid">
        <div
          v-for="ba in bankAccounts"
          :key="ba.id"
          class="cf-bank-card"
          :class="getBankColorClass(ba.bank_name)"
        >
          <div class="cf-bank-card__header">
            <div class="cf-bank-card__icon-wrap">
              <span class="i-lucide-landmark" />
            </div>
            <div class="cf-bank-card__info">
              <span class="cf-bank-card__name" :title="ba.name">{{
                ba.name
              }}</span>
              <span
                class="cf-bank-card__bank"
                :title="ba.bank_name || 'Agência/Conta indisponível'"
                >{{ ba.bank_name || 'Conta' }}</span>
            </div>
          </div>
          <div class="cf-bank-card__footer">
            <span class="cf-bank-card__label">Saldo atual</span>
            <span
              class="cf-bank-card__balance"
              :class="
                ba.current_balance < 0 ? 'cf-bank-card__balance--neg' : ''
              "
            >
              {{ formatCurrency(ba.current_balance) }}
            </span>
          </div>
        </div>
      </div>
    </div>

    <!-- Line Chart -->
    <div class="financial-section">
      <div class="cf-chart-header">
        <h2 class="financial-section__title">
          {{ $t('FINANCIAL.CASH_FLOW.CHART_TITLE') }}
        </h2>
        <div
          v-if="!loading && daily.length"
          class="cf-status-pill"
          :class="
            balanceIsPositive ? 'cf-status-pill--pos' : 'cf-status-pill--neg'
          "
        >
          <span
            :class="
              balanceIsPositive
                ? 'i-lucide-trending-up'
                : 'i-lucide-trending-down'
            "
            class="cf-status-icon"
          />
          {{
            balanceIsPositive
              ? $t('FINANCIAL.CHARTS.CASH_FLOW.BALANCE_POSITIVE')
              : $t('FINANCIAL.CHARTS.CASH_FLOW.BALANCE_NEGATIVE')
          }}
        </div>
      </div>

      <div
        v-if="loading"
        class="financial-skeleton financial-skeleton--chart"
      />

      <div v-else-if="daily.length" ref="chartWrap" class="cf-line-chart-wrap">
        <!-- SVG Chart -->
        <svg
          class="cf-svg"
          :viewBox="`0 0 ${chartW} 280`"
          @mouseleave="tooltipIndex = null"
        >
          <defs>
            <linearGradient id="incomeGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="#16a34a" stop-opacity="0.18" />
              <stop offset="100%" stop-color="#16a34a" stop-opacity="0" />
            </linearGradient>
            <linearGradient id="expenseGrad" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stop-color="#dc2626" stop-opacity="0.14" />
              <stop offset="100%" stop-color="#dc2626" stop-opacity="0" />
            </linearGradient>
          </defs>

          <!-- Y grid lines + tick labels -->
          <g v-for="tick in yTicks" :key="tick.y">
            <line
              :x1="0"
              :y1="tick.y"
              :x2="chartW"
              :y2="tick.y"
              class="cf-grid-line"
            />
            <text
              :x="0"
              :y="tick.y - 8"
              class="cf-tick-label cf-tick-label--y"
              text-anchor="start"
            >
              {{ formatShort(tick.val) }}
            </text>
          </g>

          <!-- X axis labels -->
          <text
            v-for="lbl in xLabels"
            :key="lbl.i"
            :x="lbl.x"
            y="270"
            class="cf-tick-label"
            :text-anchor="
              lbl.i === 0
                ? 'start'
                : lbl.i === daily.length - 1
                  ? 'end'
                  : 'middle'
            "
          >
            {{ lbl.label }}
          </text>

          <!-- Area fills -->
          <path :d="incomeArea" fill="url(#incomeGrad)" />
          <path :d="expenseArea" fill="url(#expenseGrad)" />

          <!-- Lines -->
          <path
            :d="incomeLine"
            fill="none"
            stroke="#16a34a"
            stroke-width="2.5"
            stroke-linejoin="round"
            stroke-linecap="round"
          />
          <path
            :d="expenseLine"
            fill="none"
            stroke="#dc2626"
            stroke-width="2.5"
            stroke-linejoin="round"
            stroke-linecap="round"
          />

          <!-- Hover hit areas (invisible rects per data point) -->
          <rect
            v-for="(d, i) in daily"
            :key="d.date"
            :x="
              xPos(i) -
              (daily.length > 1
                ? (chartW - (CHART_PAD_LEFT + CHART_PAD_RIGHT)) /
                  (daily.length - 1) /
                  2
                : 40)
            "
            y="0"
            :width="
              daily.length > 1
                ? (chartW - (CHART_PAD_LEFT + CHART_PAD_RIGHT)) /
                  (daily.length - 1)
                : 80
            "
            height="280"
            fill="transparent"
            @mouseenter="tooltipIndex = i"
          />

          <!-- Crosshair + dots on hover -->
          <g v-if="tooltipData">
            <line
              :x1="tooltipData.x"
              y1="20"
              :x2="tooltipData.x"
              :y2="244"
              stroke-dasharray="4,4"
              class="cf-crosshair"
            />
            <circle
              :cx="tooltipData.x"
              :cy="tooltipData.yIncome"
              r="5"
              fill="#16a34a"
              stroke="white"
              stroke-width="2"
            />
            <circle
              :cx="tooltipData.x"
              :cy="tooltipData.yExpense"
              r="5"
              fill="#dc2626"
              stroke="white"
              stroke-width="2"
            />
          </g>
        </svg>

        <!-- Tooltip flutuante -->
        <div
          v-if="tooltipData"
          class="cf-tooltip"
          :style="{
            left: `calc(${Math.min(100, Math.max(0, (tooltipData.x / chartW) * 100))}% - 80px)`,
          }"
        >
          <div class="cf-tooltip__date">{{ tooltipData.label }}</div>
          <div class="cf-tooltip__row cf-tooltip__row--income">
            <span class="cf-tooltip__dot cf-tooltip__dot--income" />
            {{ $t('FINANCIAL.CASH_FLOW.LEGEND_IN') }}:
            {{ formatCurrency(tooltipData.entradas) }}
          </div>
          <div class="cf-tooltip__row cf-tooltip__row--expense">
            <span class="cf-tooltip__dot cf-tooltip__dot--expense" />
            {{ $t('FINANCIAL.CASH_FLOW.LEGEND_OUT') }}:
            {{ formatCurrency(tooltipData.saidas) }}
          </div>
          <div class="cf-tooltip__divider" />
          <div
            class="cf-tooltip__balance"
            :class="
              tooltipData.saldo >= 0
                ? 'cf-tooltip__balance--pos'
                : 'cf-tooltip__balance--neg'
            "
          >
            {{ $t('FINANCIAL.CHARTS.CASH_FLOW.BALANCE') }}:
            {{ formatCurrency(tooltipData.saldo) }}
          </div>
        </div>

        <!-- Legenda -->
        <div class="cf-legend">
          <span class="cf-legend__item">
            <span class="cf-legend__dot cf-legend__dot--income" />
            <span class="cf-legend__line cf-legend__line--income" />
            {{ $t('FINANCIAL.CASH_FLOW.LEGEND_IN') }}
          </span>
          <span class="cf-legend__item">
            <span class="cf-legend__dot cf-legend__dot--expense" />
            <span class="cf-legend__line cf-legend__line--expense" />
            {{ $t('FINANCIAL.CASH_FLOW.LEGEND_OUT') }}
          </span>
          <span class="cf-legend__hint">
            <span class="i-lucide-info cf-hint-icon" />
            {{ $t('FINANCIAL.CHARTS.CASH_FLOW.LEGEND_HINT') }}
          </span>
        </div>
      </div>

      <div v-else class="financial-empty-state">
        <span class="i-lucide-line-chart financial-empty-state__icon" />
        <p class="financial-empty-state__text">
          {{ $t('FINANCIAL.CASH_FLOW.EMPTY') }}
        </p>
      </div>
    </div>

    <!-- Daily Table -->
    <div class="financial-section">
      <div class="cf-daily-details-header">
        <h2 class="financial-section__title">
          {{ $t('FINANCIAL.CASH_FLOW.TABLE_TITLE') }}
        </h2>

        <div class="cf-sort-wrap">
          <button
            class="cf-sort-toggle"
            :class="{ 'cf-sort-toggle--active': showSortMenu }"
            title="Ordenar"
            @click="showSortMenu = !showSortMenu"
          >
            <i class="i-lucide-arrow-up-down w-4 h-4" />
          </button>

          <div v-if="showSortMenu" class="cf-sort-dropdown">
            <button
              v-for="opt in sortOptions"
              :key="opt.value"
              class="cf-sort-option"
              :class="{ 'cf-sort-option--active': sortOrder === opt.value }"
              @click="setSortOrder(opt.value)"
            >
              {{ opt.label }}
            </button>
          </div>
        </div>
      </div>

      <div
        v-if="loading"
        class="financial-skeleton financial-skeleton--table"
      />

      <table
        v-else-if="daily.length"
        class="financial-table financial-table--fixed financial-table--striped"
      >
        <thead>
          <tr>
            <th>{{ $t('FINANCIAL.CASH_FLOW.TABLE_DATE') }}</th>
            <th class="financial-table__col--number">
              {{ $t('FINANCIAL.CASH_FLOW.TABLE_IN') }}
            </th>
            <th class="financial-table__col--number">
              {{ $t('FINANCIAL.CASH_FLOW.TABLE_OUT') }}
            </th>
            <th class="financial-table__col--number">
              {{ $t('FINANCIAL.CASH_FLOW.TABLE_BALANCE') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="day in sortedDaily" :key="day.date">
            <td>{{ day.label }}</td>
            <td
              class="financial-table__col--number financial-table__col--income"
            >
              {{ formatCurrency(day.entradas) }}
            </td>
            <td
              class="financial-table__col--number financial-table__col--expense"
            >
              {{ formatCurrency(day.saidas) }}
            </td>
            <td
              class="financial-table__col--number"
              :class="
                day.saldo >= 0
                  ? 'financial-table__col--positive'
                  : 'financial-table__col--negative'
              "
            >
              {{ formatCurrency(day.saldo) }}
            </td>
          </tr>
        </tbody>
      </table>

      <div v-else class="financial-empty-state">
        <p class="financial-empty-state__text">
          {{ $t('FINANCIAL.CASH_FLOW.EMPTY') }}
        </p>
      </div>
    </div>

    <!-- Transaction Modal -->
    <TransactionModal
      :show="showModal"
      :entry-type="modalEntryType"
      mode="create"
      @close="showModal = false"
      @save="handleSave"
    />
  </div>
</template>
