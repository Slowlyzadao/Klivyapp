<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import transactionsApi from '../api/accountTransactions';
import { downloadFinancialPdf } from '../api/pdfs';
import { useExportCsv } from '../composables/useExportCsv';
import { useFormatCurrency } from '../composables/useFormatCurrency';
import TransactionModal from '../components/TransactionModal.vue';
import ReceivePaymentModal from '../components/ReceivePaymentModal.vue';
import DateRangePicker from '../components/DateRangePicker.vue';
import '../financial.css';

const { formatCurrency } = useFormatCurrency();
const { exportReceivablesCsv } = useExportCsv();

const loading = ref(false);
const transactions = ref([]);
const meta = ref({ total_count: 0, total_amount: 0 });
const page = ref(1);
const search = ref('');
const statusFilter = ref('Todos');
const paymentFilter = ref('Todos');
const dateRange = ref([]);
const showStatusMenu = ref(false);
const showPaymentMenu = ref(false);

const statusOptions = [
  { value: 'Todos', label: 'Todos' },
  { value: 'Pendente', label: 'Pendente' },
  { value: 'Recebidos', label: 'Recebidos' },
  { value: 'Vencidos', label: 'Vencidos' },
];

const paymentOptions = [
  { value: 'Todos', label: 'Todos' },
  { value: 'PIX', label: 'PIX' },
  { value: 'Cartão de Crédito', label: 'Cartão de Crédito' },
  { value: 'Cartão de Débito', label: 'Cartão de Débito' },
  { value: 'Dinheiro', label: 'Dinheiro' },
  { value: 'Boleto', label: 'Boleto' },
  { value: 'Transferência', label: 'Transferência' },
];

// Transaction modal
const showModal = ref(false);
const editingTx = ref(null);
const modalMode = ref('create');

// Receive payment modal
const showReceiveModal = ref(false);
const receivingTx = ref(null);

const PAYMENT_METHOD_LABELS = {
  pix: 'PIX',
  dinheiro: 'Dinheiro',
  cartao_credito: 'Crédito',
  cartao_debito: 'Débito',
  transferencia: 'Transf.',
  boleto: 'Boleto',
  cheque: 'Cheque',
};

async function fetchData() {
  loading.value = true;
  try {
    const params = {
      entry_type: 'entrada',
      page: page.value,
      per_page: 20,
    };
    if (statusFilter.value !== 'Todos') {
      params.status_filter = statusFilter.value;
    }
    if (paymentFilter.value !== 'Todos') {
      params.payment_method_filter = paymentFilter.value;
    }
    if (dateRange.value.length >= 1 && dateRange.value[0]) {
      params.due_start = dateRange.value[0];
      params.due_end = dateRange.value[1] || dateRange.value[0];
    }
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

function onFilter() {
  page.value = 1;
  fetchData();
}

function clearDates() {
  dateRange.value = [];
  onFilter();
}

const setStatusFilter = val => {
  statusFilter.value = val;
  showStatusMenu.value = false;
  onFilter();
};

const setPaymentFilter = val => {
  paymentFilter.value = val;
  showPaymentMenu.value = false;
  onFilter();
};

const closeMenus = e => {
  if (!e.target.closest('.cf-status-wrap')) {
    showStatusMenu.value = false;
  }
  if (!e.target.closest('.cf-payment-wrap')) {
    showPaymentMenu.value = false;
  }
};

onMounted(() => {
  fetchData();
  document.addEventListener('click', closeMenus);
});

onUnmounted(() => {
  document.removeEventListener('click', closeMenus);
});

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
    recebido: 'financial-badge financial-badge--success',
    received: 'financial-badge financial-badge--success',
    pending: 'financial-badge financial-badge--warning',
    pendente: 'financial-badge financial-badge--warning',
    overdue: 'financial-badge financial-badge--danger',
  };
  return map[status] || 'financial-badge financial-badge--neutral';
}

function isOverdue(tx) {
  return (
    tx.status !== 'received' &&
    tx.status !== 'recebido' &&
    tx.due_date &&
    tx.due_date < new Date().toISOString().slice(0, 10)
  );
}

function resolvedStatus(tx) {
  if (tx.status === 'received' || tx.status === 'recebido') return 'received';
  if (isOverdue(tx)) return 'overdue';
  return 'pending';
}

function formatDate(d) {
  if (!d) return '—';
  const [y, m, day] = d.split('-');
  return `${day}/${m}/${y}`;
}

// Modal actions
function openNewEntry() {
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

function openReceive(tx) {
  receivingTx.value = tx;
  showReceiveModal.value = true;
}

async function handleReceiveConfirm({
  paymentMethod,
  paidAt,
  bankAccountId,
  proofFile,
}) {
  if (!receivingTx.value) return;
  try {
    const { data } = await transactionsApi.receive(receivingTx.value.id, {
      paymentMethod,
      paidAt,
      bankAccountId,
      proofFile,
    });
    // Atualiza a linha localmente para feedback imediato
    const idx = transactions.value.findIndex(
      t => t.id === receivingTx.value.id
    );
    if (idx !== -1) transactions.value[idx] = data.transaction;
    showReceiveModal.value = false;
    receivingTx.value = null;
    fetchData();
  } catch {
    // silent
  }
}

function exportPdf() {
  const params = {};
  if (dateRange.value.length >= 1 && dateRange.value[0]) {
    params.start_date = dateRange.value[0];
    params.end_date = dateRange.value[1] || dateRange.value[0];
  }
  downloadFinancialPdf('receivables', params);
}

function exportCsv() {
  exportReceivablesCsv(transactions.value, meta.value, dateRange.value);
}
</script>

<template>
  <div class="financial-page">
    <div class="financial-page__header">
      <div>
        <h1 class="financial-page__title">
          {{ $t('SIDEBAR.FINANCIAL_RECEIVABLES') }}
        </h1>
        <p class="financial-page__subtitle">
          {{ $t('FINANCIAL.RECEIVABLES.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-2">
        <button class="financial-btn btn-new-entry-rec" @click="openNewEntry">
          <span class="i-lucide-plus" />
          {{ $t('FINANCIAL.RECEIVABLES.NEW_ENTRY') }}
        </button>
        <button class="financial-btn financial-btn--pdf" @click="exportPdf">
          <span class="i-lucide-file-down" />
          Gerar PDF
        </button>
        <button
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
      <div class="financial-summary-card financial-summary-card--income">
        <span class="financial-summary-label"> TOTAL A RECEBER </span>
        <span class="financial-summary-value">
          {{ formatCurrency(meta.total_to_receive || 0) }}
        </span>
      </div>
      <div class="financial-summary-card">
        <span class="financial-summary-label"> RECEBIDO </span>
        <span class="financial-summary-value financial-summary-value--positive">
          {{ formatCurrency(meta.total_received || 0) }}
        </span>
      </div>
      <div class="financial-summary-card financial-summary-card--expense">
        <span class="financial-summary-label"> VENCIDO </span>
        <span class="financial-summary-value">
          {{ formatCurrency(meta.total_overdue || 0) }}
        </span>
      </div>
      <div class="financial-summary-card financial-summary-card--neutral">
        <span class="financial-summary-label"> TRANSAÇÕES </span>
        <span class="financial-summary-value">
          {{ meta.total_count || 0 }}
        </span>
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
          :placeholder="$t('FINANCIAL.RECEIVABLES.SEARCH_PLACEHOLDER')"
          @keydown.enter="onFilter"
        />
      </div>

      <!-- Rights -->
      <div class="financial-filters__right">
        <div class="flex items-center gap-2">
          <!-- Date Filter -->
          <div class="cf-date-wrap relative inline-block">
            <DateRangePicker
              v-model="dateRange"
              @update:model-value="onFilter"
            />
          </div>

          <!-- Status Filter -->
          <div class="cf-status-wrap relative inline-block">
            <button
              class="cf-sort-toggle"
              :class="{
                'cf-sort-toggle--active':
                  showStatusMenu || statusFilter !== 'Todos',
              }"
              @click="showStatusMenu = !showStatusMenu"
            >
              <span class="i-lucide-list-filter w-4 h-4 text-slate-500" />
            </button>
            <div
              v-if="showStatusMenu"
              class="cf-sort-dropdown right-0 min-w-[180px]"
            >
              <button
                v-for="opt in statusOptions"
                :key="opt.value"
                class="cf-sort-option"
                :class="{
                  'cf-sort-option--active': statusFilter === opt.value,
                }"
                @click="setStatusFilter(opt.value)"
              >
                {{ opt.label }}
              </button>
            </div>
          </div>

          <!-- Payment Filter -->
          <div class="cf-payment-wrap relative inline-block">
            <button
              class="cf-sort-toggle"
              :class="{
                'cf-sort-toggle--active':
                  showPaymentMenu || paymentFilter !== 'Todos',
              }"
              @click="showPaymentMenu = !showPaymentMenu"
            >
              <span class="i-lucide-credit-card w-4 h-4 text-slate-500" />
            </button>
            <div
              v-if="showPaymentMenu"
              class="cf-sort-dropdown right-0 min-w-[180px]"
            >
              <button
                v-for="opt in paymentOptions"
                :key="opt.value"
                class="cf-sort-option"
                :class="{
                  'cf-sort-option--active': paymentFilter === opt.value,
                }"
                @click="setPaymentFilter(opt.value)"
              >
                {{ opt.label }}
              </button>
            </div>
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
              <th>{{ $t('FINANCIAL.RECEIVABLES.TABLE.DESCRIPTION') }}</th>
              <th class="financial-table__col--number">
                {{ $t('FINANCIAL.RECEIVABLES.TABLE.AMOUNT') }}
              </th>
              <th>{{ $t('FINANCIAL.RECEIVABLES.TABLE.DUE_DATE') }}</th>
              <th>{{ $t('FINANCIAL.RECEIVABLES.TABLE.RECEIVED_AT') }}</th>
              <th>Forma</th>
              <th>{{ $t('FINANCIAL.RECEIVABLES.TABLE.STATUS') }}</th>
              <th class="financial-table__col--actions">
                {{ $t('FINANCIAL.RECEIVABLES.TABLE.ACTIONS') }}
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="tx in transactions" :key="tx.id">
              <td class="financial-table__description">
                <div class="font-medium text-slate-800 dark:text-slate-200">
                  {{ tx.patient_name || 'Sem paciente vinculado' }}
                </div>
                <div class="text-xs text-slate-500 dark:text-slate-400 mt-0.5">
                  {{ tx.description || '—' }}
                </div>
              </td>
              <td
                class="financial-table__col--number financial-table__col--income"
              >
                {{ formatCurrency(tx.amount) }}
              </td>
              <td :class="{ 'financial-table__col--danger': isOverdue(tx) }">
                {{ formatDate(tx.due_date) }}
              </td>
              <td>{{ formatDate(tx.received_at) }}</td>
              <td>
                <span
                  v-if="tx.payment_method"
                  class="financial-badge financial-badge--neutral financial-badge--sm"
                >
                  {{
                    PAYMENT_METHOD_LABELS[tx.payment_method] ||
                    tx.payment_method
                  }}
                </span>
                <span v-else>—</span>
              </td>
              <td>
                <span :class="statusBadgeClass(resolvedStatus(tx))">
                  {{
                    $t(
                      `FINANCIAL.RECEIVABLES.STATUS.${resolvedStatus(tx).toUpperCase()}`
                    )
                  }}
                </span>
              </td>
              <td class="financial-table__col--actions">
                <div class="financial-table__actions">
                  <button
                    v-if="tx.status !== 'received' && tx.status !== 'recebido'"
                    class="financial-action-btn financial-action-btn--success"
                    :title="$t('FINANCIAL.RECEIVABLES.RECEIVE')"
                    @click="openReceive(tx)"
                  >
                    <span class="i-lucide-check" />
                  </button>
                  <a
                    v-if="tx.proof_url"
                    :href="tx.proof_url"
                    target="_blank"
                    rel="noopener noreferrer"
                    class="financial-action-btn financial-action-btn--edit"
                  >
                    <span class="i-lucide-file-text" />
                  </a>
                  <button
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
            {{ $t('FINANCIAL.RECEIVABLES.EMPTY') }}
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
      entry-type="entrada"
      @close="showModal = false"
      @save="handleSave"
    />

    <!-- Receive Payment Modal -->
    <ReceivePaymentModal
      :show="showReceiveModal"
      :transaction="receivingTx"
      @close="showReceiveModal = false"
      @confirm="handleReceiveConfirm"
    />
  </div>
</template>
