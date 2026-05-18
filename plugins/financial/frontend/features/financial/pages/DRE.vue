<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import reportsAPI from '../api/reports';
import { downloadFinancialPdf } from '../api/pdfs';
import { useExportCsv } from '../composables/useExportCsv';
import { usePermissions } from 'dashboard/composables/usePermissions';
import MonthPicker from '../components/MonthPicker.vue';
import DatePicker from '../components/DatePicker.vue';
import '../financial.css';

const { t } = useI18n();
const { exportDreCsv } = useExportCsv();
const { can: klivyCan } = usePermissions();
const canExportData = computed(() => klivyCan('financial', 'export_data'));

// ── Helpers ─────────────────────────────────────────────────────────────────
function fmt(val) {
  if (val == null) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(val);
}

function variation(current, prior) {
  if (!prior || prior === 0) return null;
  return ((current - prior) / Math.abs(prior)) * 100;
}

function formatDate(str) {
  if (!str) return '';
  const [y, m, d] = str.split('-');
  return `${d}/${m}/${y}`;
}

function findPriorAmount(priorRows, categoryId) {
  return (priorRows ?? []).find(x => x.category_id === categoryId)?.amount ?? 0;
}

// ── Period selector ──────────────────────────────────────────────────────────
const periodType = ref('month');
const selectedDate = ref(new Date().toISOString().slice(0, 7));
const customStart = ref('');
const customEnd = ref('');

const periodOptions = [
  { value: 'month', label: () => t('FINANCIAL.DRE.PERIOD_MONTH') },
  { value: 'quarter', label: () => t('FINANCIAL.DRE.PERIOD_QUARTER') },
  { value: 'year', label: () => t('FINANCIAL.DRE.PERIOD_YEAR') },
  { value: 'custom', label: () => t('FINANCIAL.DRE.PERIOD_CUSTOM') },
];

// ── Data ─────────────────────────────────────────────────────────────────────
const loading = ref(false);
const data = ref(null);

const cur = computed(() => data.value?.current ?? null);
const pri = computed(() => data.value?.prior ?? null);

const periodLabel = computed(() => {
  if (!data.value) return '';
  const { start, end } = data.value.period;
  return `${formatDate(start)} — ${formatDate(end)}`;
});

const priorLabel = computed(() => {
  if (!data.value) return '';
  const { start, end } = data.value.prior_period;
  return `${formatDate(start)} — ${formatDate(end)}`;
});

// ── Fetch ─────────────────────────────────────────────────────────────────────
async function fetchDre() {
  loading.value = true;
  data.value = null;
  try {
    const params = { period: periodType.value };
    if (periodType.value === 'month' || periodType.value === 'quarter') {
      params.date = selectedDate.value;
    }
    if (periodType.value === 'year') {
      params.date = selectedDate.value.slice(0, 4);
    }
    if (periodType.value === 'custom') {
      params.start_date = customStart.value;
      params.end_date = customEnd.value;
    }
    const res = await reportsAPI.dre(params);
    data.value = res.data;
  } catch {
    data.value = null;
  } finally {
    loading.value = false;
  }
}

watch(periodType, () => {
  if (periodType.value !== 'custom') fetchDre();
});

onMounted(fetchDre);

// ── DRE row builder ──────────────────────────────────────────────────────────
const dreRows = computed(() => {
  if (!cur.value) return [];

  const c = cur.value;
  const p = pri.value ?? {};

  return [
    {
      key: 'receita_bruta',
      label: t('FINANCIAL.DRE.SECTION_INCOME'),
      currentVal: c.receita_bruta,
      priorVal: p.receita_bruta ?? 0,
      isSection: true,
      isPositive: true,
      children: (c.income_rows ?? []).map(r => ({
        key: `income_${r.category_id}`,
        label: r.category_name,
        color: r.color,
        currentVal: r.amount,
        priorVal: findPriorAmount(p.income_rows, r.category_id),
        isSection: false,
        isPositive: true,
      })),
    },
    {
      key: 'deducoes',
      label: t('FINANCIAL.DRE.SECTION_DEDUCTIONS'),
      currentVal: -c.deducoes,
      priorVal: -(p.deducoes ?? 0),
      isSection: true,
      isPositive: false,
      children: [],
    },
    {
      key: 'receita_liq',
      label: t('FINANCIAL.DRE.SECTION_NET_INCOME'),
      currentVal: c.receita_liq,
      priorVal: p.receita_liq ?? 0,
      isSection: true,
      isResult: true,
      isPositive: c.receita_liq >= 0,
      children: [],
    },
    {
      key: 'custos_var',
      label: t('FINANCIAL.DRE.SECTION_VARIABLE_COSTS'),
      currentVal: -c.custos_var,
      priorVal: -(p.custos_var ?? 0),
      isSection: true,
      isPositive: false,
      children: (c.expense_rows ?? [])
        .filter(r => r.cost_type === 'variavel')
        .map(r => ({
          key: `var_${r.category_id}`,
          label: r.category_name,
          color: r.color,
          currentVal: -r.amount,
          priorVal: -findPriorAmount(p.expense_rows, r.category_id),
          isSection: false,
          isPositive: false,
        })),
    },
    {
      key: 'margem_bruta',
      label: t('FINANCIAL.DRE.SECTION_GROSS_MARGIN'),
      currentVal: c.margem_bruta,
      priorVal: p.margem_bruta ?? 0,
      isSection: true,
      isResult: true,
      isPositive: c.margem_bruta >= 0,
      children: [],
    },
    {
      key: 'desp_fixas',
      label: t('FINANCIAL.DRE.SECTION_FIXED_EXPENSES'),
      currentVal: -c.desp_fixas,
      priorVal: -(p.desp_fixas ?? 0),
      isSection: true,
      isPositive: false,
      children: (c.expense_rows ?? [])
        .filter(r => r.cost_type === 'fixo')
        .map(r => ({
          key: `fix_${r.category_id}`,
          label: r.category_name,
          color: r.color,
          currentVal: -r.amount,
          priorVal: -findPriorAmount(p.expense_rows, r.category_id),
          isSection: false,
          isPositive: false,
        })),
    },
    {
      key: 'ebitda',
      label: t('FINANCIAL.DRE.SECTION_EBITDA'),
      currentVal: c.ebitda,
      priorVal: p.ebitda ?? 0,
      isSection: true,
      isResult: true,
      isPositive: c.ebitda >= 0,
      children: [],
    },
    {
      key: 'outras_desp',
      label: t('FINANCIAL.DRE.SECTION_OTHER_EXPENSES'),
      currentVal: -c.outras_desp,
      priorVal: -(p.outras_desp ?? 0),
      isSection: true,
      isPositive: false,
      children: (c.expense_rows ?? [])
        .filter(
          r => !r.cost_type || !['fixo', 'variavel'].includes(r.cost_type)
        )
        .map(r => ({
          key: `other_${r.category_id}`,
          label: r.category_name,
          color: r.color,
          currentVal: -r.amount,
          priorVal: -findPriorAmount(p.expense_rows, r.category_id),
          isSection: false,
          isPositive: false,
        })),
    },
    {
      key: 'lucro_liq',
      label: t('FINANCIAL.DRE.SECTION_NET_PROFIT'),
      currentVal: c.lucro_liq,
      priorVal: p.lucro_liq ?? 0,
      isSection: true,
      isResult: true,
      isNetProfit: true,
      isPositive: c.lucro_liq >= 0,
      children: [],
    },
  ];
});

// ── Expanded rows ─────────────────────────────────────────────────────────────
const expanded = ref(
  new Set(['receita_bruta', 'custos_var', 'desp_fixas', 'outras_desp'])
);

function toggleRow(key) {
  if (expanded.value.has(key)) expanded.value.delete(key);
  else expanded.value.add(key);
}

function rowClass(row) {
  return {
    'dre-row--result': row.isResult,
    'dre-row--section': !row.isResult,
    'dre-row--net-profit': !!row.isNetProfit,
  };
}

function valClass(val) {
  return val >= 0 ? 'dre-val--positive' : 'dre-val--negative';
}

function badgeClass(val, prior) {
  return variation(val, prior) >= 0 ? 'dre-badge--up' : 'dre-badge--down';
}

function trendIcon(val, prior) {
  return variation(val, prior) >= 0
    ? 'i-lucide-trending-up'
    : 'i-lucide-trending-down';
}

function trendLabel(val, prior) {
  const v = variation(val, prior);
  return v !== null ? `${Math.abs(v).toFixed(1)}%` : null;
}

function exportPdf() {
  downloadFinancialPdf('dre', { period: selectedDate.value });
}

function exportCsv() {
  exportDreCsv(dreRows.value, data.value, periodLabel.value, priorLabel.value);
}
</script>

<template>
  <div class="financial-page">
    <!-- Header -->
    <div class="financial-header">
      <div>
        <h1 class="financial-title">{{ $t('FINANCIAL.DRE.TITLE') }}</h1>
        <p class="financial-subtitle">{{ $t('FINANCIAL.DRE.SUBTITLE') }}</p>
      </div>
      <button v-if="canExportData" class="dre-export-btn" @click="exportPdf">
        <i class="i-lucide-file-down" />
        Gerar PDF
      </button>
      <button
        v-if="canExportData"
        class="financial-btn--csv"
        title="Exportar para Google Sheets (CSV)"
        @click="exportCsv"
      >
        <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
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

    <!-- Filters -->
    <div class="dre-filters">
      <div class="dre-period-tabs">
        <button
          v-for="opt in periodOptions"
          :key="opt.value"
          class="dre-period-tab"
          :class="{ 'dre-period-tab--active': periodType === opt.value }"
          @click="periodType = opt.value"
        >
          {{ opt.label() }}
        </button>
      </div>

      <MonthPicker
        v-if="
          periodType === 'month' ||
          periodType === 'quarter' ||
          periodType === 'year'
        "
        v-model="selectedDate"
        @update:model-value="fetchDre"
      />

      <template v-else-if="periodType === 'custom'">
        <div class="dre-custom-range">
          <DatePicker v-model="customStart" />
          <span class="dre-range-sep">&#8594;</span>
          <DatePicker v-model="customEnd" />
          <button class="dre-apply-btn" @click="fetchDre">
            <i class="i-lucide-search" />
          </button>
        </div>
      </template>
    </div>

    <!-- Period label -->
    <div v-if="data" class="dre-period-label">
      <i class="i-lucide-calendar" />
      <span>{{ periodLabel }}</span>
      <span class="dre-prior-label">
        {{ $t('FINANCIAL.DRE.COMPARE_PRIOR') }}: {{ priorLabel }}
      </span>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="financial-loading">
      <i class="i-lucide-loader-2 financial-loading__spinner" />
      <p>{{ $t('FINANCIAL.DRE.LOADING') }}</p>
    </div>

    <!-- Empty -->
    <div v-else-if="!data && !loading" class="financial-coming-soon">
      <i class="i-lucide-bar-chart-2 financial-coming-soon__icon" />
      <p class="financial-coming-soon__desc">{{ $t('FINANCIAL.DRE.EMPTY') }}</p>
    </div>

    <!-- DRE Table -->
    <div v-else-if="data && cur" class="dre-table-wrap">
      <table class="dre-table">
        <thead>
          <tr class="dre-table__header">
            <th class="dre-table__th dre-table__th--desc">
              {{ $t('FINANCIAL.DRE.COL_DESCRIPTION') }}
            </th>
            <th class="dre-table__th dre-table__th--num">
              {{ $t('FINANCIAL.DRE.COL_CURRENT') }}
            </th>
            <th class="dre-table__th dre-table__th--num">
              {{ $t('FINANCIAL.DRE.COL_PRIOR') }}
            </th>
            <th class="dre-table__th dre-table__th--num">
              {{ $t('FINANCIAL.DRE.COL_VARIATION') }}
            </th>
          </tr>
        </thead>
        <tbody>
          <template v-for="row in dreRows" :key="row.key">
            <!-- Section row -->
            <tr
              class="dre-row"
              :class="rowClass(row)"
              @click="
                row.children && row.children.length
                  ? toggleRow(row.key)
                  : undefined
              "
            >
              <td class="dre-table__td dre-table__td--desc">
                <div class="dre-row__label">
                  <i
                    v-if="row.children && row.children.length"
                    class="dre-row__chevron"
                    :class="
                      expanded.has(row.key)
                        ? 'i-lucide-chevron-down'
                        : 'i-lucide-chevron-right'
                    "
                  />
                  <span v-else class="dre-row__chevron--spacer" />
                  <span>{{ row.label }}</span>
                </div>
              </td>
              <td
                class="dre-table__td dre-table__td--num"
                :class="valClass(row.currentVal)"
              >
                {{ fmt(Math.abs(row.currentVal)) }}
              </td>
              <td class="dre-table__td dre-table__td--num dre-val--muted">
                {{ fmt(Math.abs(row.priorVal)) }}
              </td>
              <td class="dre-table__td dre-table__td--num">
                <span
                  v-if="variation(row.currentVal, row.priorVal) !== null"
                  class="dre-badge"
                  :class="badgeClass(row.currentVal, row.priorVal)"
                >
                  <i :class="trendIcon(row.currentVal, row.priorVal)" />
                  {{ trendLabel(row.currentVal, row.priorVal) }}
                </span>
                <span v-else class="dre-val--muted">&#8212;</span>
              </td>
            </tr>

            <!-- Child rows -->
            <template
              v-if="
                row.children && row.children.length && expanded.has(row.key)
              "
            >
              <tr
                v-for="child in row.children"
                :key="child.key"
                class="dre-row dre-row--child"
              >
                <td class="dre-table__td dre-table__td--desc">
                  <div class="dre-row__label dre-row__label--indent">
                    <span
                      class="dre-cat-dot"
                      :style="{ background: child.color }"
                    />
                    <span>{{ child.label }}</span>
                  </div>
                </td>
                <td
                  class="dre-table__td dre-table__td--num"
                  :class="valClass(child.currentVal)"
                >
                  {{ fmt(Math.abs(child.currentVal)) }}
                </td>
                <td class="dre-table__td dre-table__td--num dre-val--muted">
                  {{ fmt(Math.abs(child.priorVal)) }}
                </td>
                <td class="dre-table__td dre-table__td--num">
                  <span
                    v-if="variation(child.currentVal, child.priorVal) !== null"
                    class="dre-badge dre-badge--sm"
                    :class="badgeClass(child.currentVal, child.priorVal)"
                  >
                    {{ trendLabel(child.currentVal, child.priorVal) }}
                  </span>
                  <span v-else class="dre-val--muted">&#8212;</span>
                </td>
              </tr>
            </template>
          </template>
        </tbody>
      </table>
    </div>
  </div>
</template>
