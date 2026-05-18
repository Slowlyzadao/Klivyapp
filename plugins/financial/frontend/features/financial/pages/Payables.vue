<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import transactionsApi from '../api/accountTransactions';
import { downloadFinancialPdf } from '../api/pdfs';
import { useExportCsv } from '../composables/useExportCsv';
import { useFormatCurrency } from '../composables/useFormatCurrency';
import { usePermissions } from 'dashboard/composables/usePermissions';
import TransactionModal from '../components/TransactionModal.vue';
import '../financial.css';

const { formatCurrency } = useFormatCurrency();
const { exportPayablesCsv } = useExportCsv();
const { can: klivyCan } = usePermissions();
const canCreateTransaction = computed(() =>
  klivyCan('financial', 'create_transaction')
);
const canEditTransaction = computed(() =>
  klivyCan('financial', 'edit_transaction')
);
const canExportData = computed(() => klivyCan('financial', 'export_data'));

const loading = ref(false);
const transactions = ref([]);
const meta = ref({ total_count: 0, total_amount: 0 });
const page = ref(1);
const search = ref('');
const statusFilter = ref('');
const overdueFilter = ref('');

// Transaction modal
const showModal = ref(false);
const editingTx = ref(null);
const modalMode = ref('create');

const statusOptions = [
  { value: '', label: 'FINANCIAL.PAYABLES.STATUS.ALL' },
  { value: 'pending', label: 'FINANCIAL.PAYABLES.STATUS.PENDING' },
  { value: 'paid', label: 'FINANCIAL.PAYABLES.STATUS.PAID' },
];

async function fetchData() {
  loading.value = true;
  try {
    const params = {
      entry_type: 'saida',
      page: page.value,
      per_page: 20,
    };
    if (statusFilter.value) params.status = statusFilter.value;
    if (overdueFilter.value) params.overdue = overdueFilter.value;
    if (search.value.trim()) params.q = search.value.trim();

    const { data } = await transactionsApi.list(params);
    transactions.value = data.transactions || [];
    meta.value = data.meta || { total_count: 0, total_amount: 0 };
  } catch {
    // silent
  } finally {
    loading.value = false;
  }
}

const showStatusMenu = ref(false);

const setStatusFilter = val => {
  statusFilter.value = val;
  showStatusMenu.value = false;
  onFilter();
};

const closeStatusMenu = e => {
  if (!e.target.closest('.cf-sort-wrap')) {
    showStatusMenu.value = false;
  }
};

onMounted(() => {
  fetchData();
  document.addEventListener('click', closeStatusMenu);
});

onUnmounted(() => {
  document.removeEventListener('click', closeStatusMenu);
});

function onFilter() {
  page.value = 1;
  fetchData();
}

function nextPage() {
  page.value += 1;
  fetchData();
}

function prevPage() {
  if (page.value > 1) {
    page.value -= 1;
    fetchData();
  }
}

const totalPages = computed(() => Math.ceil(meta.value.total_count / 20));

function statusBadgeClass(status) {
  const map = {
    paid: 'financial-badge financial-badge--success',
    pending: 'financial-badge financial-badge--warning',
    overdue: 'financial-badge financial-badge--danger',
  };
  return map[status] || 'financial-badge financial-badge--neutral';
}

function isOverdue(tx) {
  return (
    tx.status !== 'paid' &&
    tx.status !== 'pago' &&
    tx.due_date &&
    tx.due_date < new Date().toISOString().slice(0, 10)
  );
}

function resolvedStatus(tx) {
  if (tx.status === 'paid' || tx.status === 'pago') return 'paid';
  if (isOverdue(tx)) return 'overdue';
  return 'pending';
}

function formatDate(d) {
  if (!d) return '—';
  const [y, m, day] = d.split('-');
  return `${day}/${m}/${y}`;
}

// Modal actions
function openNewExpense() {
  editingTx.value = null;
  modalMode.value = 'create';
  showModal.value = true;
}

function openEditTx(tx) {
  editingTx.value = tx;
  modalMode.value = 'edit';
  showModal.value = true;
}

async function handleSave({ payload, id, isEditing }) {
  try {
    if (isEditing) {
      await transactionsApi.update(id, payload);
    } else {
      await transactionsApi.create(payload);
    }
    showModal.value = false;
    fetchData();
  } catch {
    // silent
  }
}

async function markPaid(tx) {
  try {
    await transactionsApi.update(tx.id, {
      status: 'pago',
      paid_at: new Date().toISOString().slice(0, 10),
    });
    fetchData();
  } catch {
    // silent
  }
}

function exportPdf() {
  downloadFinancialPdf('payables');
}

function exportCsv() {
  exportPayablesCsv(transactions.value, meta.value, []);
}
</script>

<template>
  <div class="financial-page">
    <div class="financial-page__header">
      <div>
        <h1 class="financial-page__title">
          {{ $t('SIDEBAR.FINANCIAL_PAYABLES') }}
        </h1>
        <p class="financial-page__subtitle">
          {{ $t('FINANCIAL.PAYABLES.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button
          v-if="canCreateTransaction"
          class="financial-btn btn-new-expense-pay"
          @click="openNewExpense"
        >
          <span class="i-lucide-plus" />
          {{ $t('FINANCIAL.PAYABLES.NEW_EXPENSE') }}
        </button>
        <button
          v-if="canExportData"
          class="financial-btn financial-btn--pdf"
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

    <!-- Totals -->
    <div class="financial-grid financial-grid--4">
      <!-- Card 1: Total A Pagar -->
      <div class="financial-summary-card financial-summary-card--expense">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-arrow-up-circle cf-balance-icon" />
          {{ $t('FINANCIAL.PAYABLES.TOTAL') }}
        </span>
        <span class="financial-summary-value cf-expense-value">
          {{ formatCurrency(meta.total_amount || 0) }}
        </span>
        <span class="cf-balance-hint">Valor somado das saídas cadastradas</span>
      </div>

      <!-- Card 2: Total Recorrente -->
      <div class="financial-summary-card financial-summary-card--income">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-calendar-sync cf-balance-icon" />
          TOTAL RECORRENTE
        </span>
        <span class="financial-summary-value cf-income-value">
          {{ formatCurrency(meta.total_recurring || 0) }}
        </span>
        <span class="cf-balance-hint">Soma das despesas com recorrência</span>
      </div>

      <!-- Card 3: Próximos de Vencer -->
      <div class="financial-summary-card financial-summary-card--net">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-clock cf-balance-icon" />
          PRÓXIMOS A VENCER
        </span>
        <span class="financial-summary-value text-yellow-600">
          {{ formatCurrency(meta.total_upcoming || 0) }}
        </span>
        <span class="cf-balance-hint">
          {{ meta.count_upcoming || 0 }} despesa(s) vencendo em até 3 dias
        </span>
      </div>

      <!-- Card 4: Transações -->
      <div class="financial-summary-card">
        <span class="financial-summary-label cf-balance-label">
          <span class="i-lucide-receipt cf-balance-icon" />
          {{ $t('FINANCIAL.PAYABLES.COUNT') }}
        </span>
        <span class="financial-summary-value">
          {{ meta.total_count }}
        </span>
        <span class="cf-balance-hint">Total de faturas listadas</span>
      </div>
    </div>

    <!-- Filters -->
    <div class="financial-filters">
      <!-- Search -->
      <div class="financial-filters__left">
        <span class="i-lucide-search w-4 h-4 financial-search-icon" />
        <input
          v-model="search"
          type="text"
          class="financial-filters__search"
          :placeholder="$t('FINANCIAL.PAYABLES.SEARCH_PLACEHOLDER')"
          @keydown.enter="onFilter"
        />
      </div>

      <!-- Rights -->
      <div class="financial-filters__right">
        <label
          class="financial-filter-pill"
          :class="{ 'financial-filter-pill--active': overdueFilter === 'true' }"
        >
          <input
            v-model="overdueFilter"
            type="checkbox"
            true-value="true"
            false-value=""
            class="hidden"
            @change="onFilter"
          />
          {{ $t('FINANCIAL.PAYABLES.OVERDUE_ONLY') }}
        </label>

        <div class="financial-filters__divider" />

        <div class="cf-sort-wrap">
          <button
            class="cf-sort-toggle"
            :class="{ 'cf-sort-toggle--active': showStatusMenu }"
            @click="showStatusMenu = !showStatusMenu"
          >
            <span class="i-lucide-list-filter w-4 h-4" />
          </button>
          <div v-if="showStatusMenu" class="cf-sort-dropdown">
            <button
              v-for="opt in statusOptions"
              :key="opt.value"
              class="cf-sort-option"
              :class="{ 'cf-sort-option--active': statusFilter === opt.value }"
              @click="setStatusFilter(opt.value)"
            >
              {{ $t(opt.label) }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Table -->
    <div class="financial-section">
      <div
        v-if="loading"
        class="financial-skeleton financial-skeleton--table"
      />

      <template v-else>
        <table v-if="transactions.length" class="financial-table">
          <thead>
            <tr>
              <th>{{ $t('FINANCIAL.PAYABLES.TABLE.DESCRIPTION') }}</th>
              <th class="financial-table__col--number">
                {{ $t('FINANCIAL.PAYABLES.TABLE.AMOUNT') }}
              </th>
              <th>{{ $t('FINANCIAL.PAYABLES.TABLE.DUE_DATE') }}</th>
              <th>{{ $t('FINANCIAL.PAYABLES.TABLE.PAID_AT') }}</th>
              <th>{{ $t('FINANCIAL.PAYABLES.TABLE.STATUS') }}</th>
              <th>{{ $t('FINANCIAL.PAYABLES.TABLE.RECURRING') }}</th>
              <th class="financial-table__col--actions">
                {{ $t('FINANCIAL.PAYABLES.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="tx in transactions" :key="tx.id">
              <td class="financial-table__description">
                {{ tx.description || '—' }}
              </td>
              <td
                class="financial-table__col--number financial-table__col--expense"
              >
                {{ formatCurrency(tx.amount) }}
              </td>
              <td :class="{ 'financial-table__col--danger': isOverdue(tx) }">
                {{ formatDate(tx.due_date) }}
              </td>
              <td>{{ formatDate(tx.paid_at) }}</td>
              <td>
                <span :class="statusBadgeClass(resolvedStatus(tx))">
                  {{
                    $t(
                      `FINANCIAL.PAYABLES.STATUS.${resolvedStatus(tx).toUpperCase()}`
                    )
                  }}
                </span>
              </td>
              <td class="text-center">
                <span
                  class="financial-badge"
                  :class="
                    tx.recurring
                      ? 'financial-badge--success'
                      : 'financial-badge--neutral'
                  "
                >
                  {{
                    tx.recurring
                      ? $t('FINANCIAL.PAYABLES.RECURRING_YES')
                      : $t('FINANCIAL.PAYABLES.RECURRING_NO')
                  }}
                </span>
              </td>
              <td class="financial-table__col--actions">
                <div class="financial-table__actions">
                  <button
                    v-if="
                      canCreateTransaction &&
                      tx.status !== 'paid' &&
                      tx.status !== 'pago'
                    "
                    class="financial-action-btn financial-action-btn--success"
                    :title="$t('FINANCIAL.PAYABLES.PAY')"
                    @click="markPaid(tx)"
                  >
                    <span class="i-lucide-check" />
                  </button>
                  <button
                    v-if="canEditTransaction"
                    class="financial-action-btn financial-action-btn--edit"
                    :title="$t('FINANCIAL.SETTINGS.EDIT')"
                    @click="openEditTx(tx)"
                  >
                    <span class="i-lucide-pencil" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>

        <div v-else class="financial-empty-state">
          <span class="i-lucide-inbox financial-empty-state__icon" />
          <p class="financial-empty-state__text">
            {{ $t('FINANCIAL.PAYABLES.EMPTY') }}
          </p>
        </div>
      </template>
    </div>

    <!-- Pagination -->
    <div v-if="totalPages > 1" class="financial-pagination">
      <button
        class="financial-btn financial-btn--ghost"
        :disabled="page === 1"
        @click="prevPage"
      >
        ← {{ $t('FINANCIAL.PAGINATION.PREV') }}
      </button>
      <span class="financial-pagination__info">
        {{ page }} / {{ totalPages }}
      </span>
      <button
        class="financial-btn financial-btn--ghost"
        :disabled="page >= totalPages"
        @click="nextPage"
      >
        {{ $t('FINANCIAL.PAGINATION.NEXT') }} →
      </button>
    </div>

    <!-- Transaction Modal -->
    <TransactionModal
      :show="showModal"
      :transaction="editingTx"
      :mode="modalMode"
      entry-type="saida"
      @close="showModal = false"
      @save="handleSave"
    />
  </div>
</template>
