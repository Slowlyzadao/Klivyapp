<script setup>
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import cashRegistersAPI from '../api/cashRegisters';
import DatePicker from '../components/DatePicker.vue';
import '../financial.css';

const store = useStore();

const accountId = computed(() => store.getters.getCurrentAccountId);
const currentUser = computed(() => store.getters.getCurrentUser);

// ── Helpers ───────────────────────────────────────────────────────────────────
function formatMoneyInput(str) {
  if (!str) return '';
  const num = String(str).replace(/\D/g, '');
  if (!num) return '';
  return new Intl.NumberFormat('pt-BR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(Number(num) / 100);
}

function parseMoneyInput(str) {
  if (!str) return 0;
  const num = String(str).replace(/\D/g, '');
  return Number(num) / 100;
}

// ── State ─────────────────────────────────────────────────────────────────────
const selectedDate = ref(new Date().toISOString().slice(0, 10));
const register = ref(null);
const loading = ref(false);
const submitting = ref(false);

// Open form
const openingBalanceRaw = ref('');
const openingBalance = computed({
  get: () => formatMoneyInput(openingBalanceRaw.value),
  set: val => {
    openingBalanceRaw.value = val;
  },
});

// Entry form (sangria/suprimento)
const showEntryForm = ref(false);
const entryType = ref('withdrawal');
const entryAmountRaw = ref('');
const entryAmount = computed({
  get: () => formatMoneyInput(entryAmountRaw.value),
  set: val => {
    entryAmountRaw.value = val;
  },
});
const entryPaymentMethod = ref('cash');
const entryDescription = ref('');

// Close form
const showCloseForm = ref(false);
const declaredBalanceRaw = ref('');
const declaredBalance = computed({
  get: () => formatMoneyInput(declaredBalanceRaw.value),
  set: val => {
    declaredBalanceRaw.value = val;
  },
});
const closingNotes = ref('');
function fmt(val) {
  if (val == null) return 'R$ 0,00';
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(val);
}

function fmtDiff(val) {
  if (val == null) return '\u2014';
  return val >= 0 ? `+${fmt(val)}` : `-${fmt(Math.abs(val))}`;
}

const diffClass = computed(() => {
  if (!register.value?.difference) return 'cr-val--neutral';
  return register.value.difference >= 0
    ? 'cr-val--positive'
    : 'cr-val--negative';
});

const isOpen = computed(() => register.value?.status === 'open');
const isClosed = computed(() => register.value?.status === 'closed');

// ── Fetch ─────────────────────────────────────────────────────────────────────
async function fetchRegister() {
  loading.value = true;
  register.value = null;
  try {
    const res = await cashRegistersAPI.list(accountId.value, {
      date: selectedDate.value,
      operator_id: currentUser.value?.id,
    });
    if (res.data && res.data.length > 0) {
      const full = await cashRegistersAPI.show(accountId.value, res.data[0].id);
      register.value = full.data;
      if (full.data.calculated_balance != null) {
        declaredBalanceRaw.value = full.data.calculated_balance.toFixed(2);
      } else {
        declaredBalanceRaw.value = '';
      }
    }
  } catch {
    register.value = null;
  } finally {
    loading.value = false;
  }
}

// Only re-fetch when the date or account actually changes — not on every
// Vuex mutation (which caused WebSocket-triggered page flickers).
watch([accountId, selectedDate], ([newAccountId]) => {
  if (newAccountId) fetchRegister();
});
onMounted(() => {
  if (accountId.value) fetchRegister();
});

// ── History ───────────────────────────────────────────────────────────────────
const activeTab = ref('today'); // 'today' | 'history'
const history = ref([]);
const historyLoading = ref(false);

// Filter: default to current year-month (YYYY-MM)
const historyMonth = ref(new Date().toISOString().slice(0, 7));

// Set of expanded register_date strings ('YYYY-MM-DD')
const expandedDates = ref(new Set());

// Cache of full register data (with entries) keyed by register id
const registerCache = ref({});
const loadingDetail = ref(new Set());

// Registers filtered by selected month, sorted newest first
const filteredHistory = computed(() => {
  if (!historyMonth.value) return history.value;
  return history.value.filter(r =>
    r.register_date.startsWith(historyMonth.value)
  );
});

// Group filtered history by date → [{date, registers[]}]
const groupedHistory = computed(() => {
  const map = {};
  filteredHistory.value.forEach(r => {
    if (!map[r.register_date]) map[r.register_date] = [];
    map[r.register_date].push(r);
  });
  return Object.keys(map)
    .sort((a, b) => (a < b ? 1 : -1))
    .map(date => ({ date, registers: map[date] }));
});

async function fetchHistory() {
  historyLoading.value = true;
  try {
    const res = await cashRegistersAPI.list(accountId.value, {});
    history.value = res.data || [];
  } catch {
    history.value = [];
  } finally {
    historyLoading.value = false;
  }
}

async function toggleDate(date) {
  const next = new Set(expandedDates.value);
  if (next.has(date)) {
    next.delete(date);
    expandedDates.value = next;
    return;
  }
  next.add(date);
  expandedDates.value = next;

  // Fetch full detail (with entries) for each register on that date not yet cached
  const regs = groupedHistory.value.find(g => g.date === date)?.registers || [];
  await Promise.all(
    regs
      .filter(r => !registerCache.value[r.id])
      .map(async r => {
        const ld = new Set(loadingDetail.value);
        ld.add(r.id);
        loadingDetail.value = ld;
        try {
          const full = await cashRegistersAPI.show(accountId.value, r.id);
          registerCache.value = { ...registerCache.value, [r.id]: full.data };
        } finally {
          const ld2 = new Set(loadingDetail.value);
          ld2.delete(r.id);
          loadingDetail.value = ld2;
        }
      })
  );
}

function switchTab(tab) {
  activeTab.value = tab;
  if (tab === 'history' && history.value.length === 0) fetchHistory();
}

// ── Open register ─────────────────────────────────────────────────────────────
async function openRegister() {
  submitting.value = true;
  try {
    const res = await cashRegistersAPI.create(accountId.value, {
      register_date: selectedDate.value,
      opening_balance: parseMoneyInput(openingBalanceRaw.value),
      operator_id: currentUser.value?.id,
    });
    register.value = res.data;
  } finally {
    submitting.value = false;
  }
}

// ── Add entry ─────────────────────────────────────────────────────────────────
async function addEntry() {
  if (!entryAmount.value) return;
  submitting.value = true;
  try {
    const res = await cashRegistersAPI.update(
      accountId.value,
      register.value.id,
      {
        entry_type: entryType.value,
        amount: parseMoneyInput(entryAmountRaw.value),
        payment_method: entryPaymentMethod.value,
        description: entryDescription.value,
      }
    );
    register.value = res.data;
    // Keep the declared balance in sync so the close form always pre-fills
    // with the latest calculated balance, preventing stale-value differences.
    if (res.data.calculated_balance != null) {
      declaredBalanceRaw.value = res.data.calculated_balance.toFixed(2);
    }
    entryAmountRaw.value = '';
    entryDescription.value = '';
    showEntryForm.value = false;
  } finally {
    submitting.value = false;
  }
}

// ── Close register ────────────────────────────────────────────────────────────
async function closeRegister() {
  submitting.value = true;
  try {
    const res = await cashRegistersAPI.update(
      accountId.value,
      register.value.id,
      {
        close: 'true',
        declared_balance: parseMoneyInput(declaredBalanceRaw.value),
        closing_notes: closingNotes.value,
      }
    );
    register.value = res.data;
    showCloseForm.value = false;
  } finally {
    submitting.value = false;
  }
}

// ── Reopen register ───────────────────────────────────────────────────────────
async function reopenRegister() {
  submitting.value = true;
  try {
    const res = await cashRegistersAPI.update(
      accountId.value,
      register.value.id,
      { reopen: 'true' }
    );
    register.value = res.data;
  } finally {
    submitting.value = false;
  }
}

const paymentMethods = [
  { value: 'cash', labelKey: 'PAYMENT_CASH' },
  { value: 'pix', labelKey: 'PAYMENT_PIX' },
  { value: 'card_credit', labelKey: 'PAYMENT_CARD_CREDIT' },
  { value: 'card_debit', labelKey: 'PAYMENT_CARD_DEBIT' },
  { value: 'transfer', labelKey: 'PAYMENT_TRANSFER' },
];
</script>

<template>
  <div class="financial-page">
    <!-- Header -->
    <div class="financial-header">
      <div>
        <h1 class="financial-title">
          {{ $t('FINANCIAL.CASH_REGISTER.TITLE') }}
        </h1>
        <p class="financial-subtitle">
          {{ $t('FINANCIAL.CASH_REGISTER.SUBTITLE') }}
        </p>
      </div>
      <div class="cr-date-wrap">
        <label class="cr-label">{{
          $t('FINANCIAL.CASH_REGISTER.DATE_LABEL')
        }}</label>
        <DatePicker v-model="selectedDate" />
      </div>
    </div>

    <!-- Tabs -->
    <div class="fin-tabs">
      <button
        class="fin-tab"
        :class="{ 'fin-tab--active': activeTab === 'today' }"
        @click="switchTab('today')"
      >
        <i class="i-lucide-calculator" />
        {{ $t('FINANCIAL.CASH_REGISTER.TAB_TODAY') }}
      </button>
      <button
        class="fin-tab"
        :class="{ 'fin-tab--active': activeTab === 'history' }"
        @click="switchTab('history')"
      >
        <i class="i-lucide-history" />
        {{ $t('FINANCIAL.CASH_REGISTER.TAB_HISTORY') }}
      </button>
    </div>

    <!-- Loading -->
    <div v-if="activeTab === 'today'">
      <div v-if="loading" class="financial-loading">
        <i class="i-lucide-loader-2 financial-loading__spinner" />
        <p>{{ $t('FINANCIAL.CASH_REGISTER.LOADING') }}</p>
      </div>

      <!-- No register found → open -->
      <div v-else-if="!register" class="cr-empty-state">
        <div class="cr-empty-state__icon-wrap">
          <i class="i-lucide-calculator cr-empty-state__icon" />
        </div>
        <p class="cr-empty-state__title">
          {{ $t('FINANCIAL.CASH_REGISTER.NO_REGISTER') }}
        </p>
        <p class="cr-empty-state__hint">
          {{ $t('FINANCIAL.CASH_REGISTER.CREATE_FIRST') }}
        </p>

        <div class="cr-open-form">
          <label class="cr-label">{{
            $t('FINANCIAL.CASH_REGISTER.OPENING_BALANCE')
          }}</label>
          <div class="cr-money-input-group">
            <span class="cr-money-input-prefix">{{
              $t('FINANCIAL.CASH_REGISTER.CURRENCY_SYMBOL') || 'R$'
            }}</span>
            <input
              v-model="openingBalance"
              type="text"
              class="cr-money-input"
              :placeholder="
                $t('FINANCIAL.CASH_REGISTER.OPENING_BALANCE_PLACEHOLDER')
              "
            />
          </div>
          <button
            class="cr-btn cr-btn--primary"
            :disabled="submitting"
            @click="openRegister"
          >
            <i class="i-lucide-calculator" />
            {{ $t('FINANCIAL.CASH_REGISTER.OPEN') }}
          </button>
        </div>
      </div>

      <!-- Register found -->
      <template v-else>
        <!-- Status badge -->
        <div class="cr-status-bar">
          <span
            class="cr-status-badge"
            :class="
              isOpen ? 'cr-status-badge--open' : 'cr-status-badge--closed'
            "
          >
            <i :class="isOpen ? 'i-lucide-lock-open' : 'i-lucide-lock'" />
            {{
              isOpen
                ? $t('FINANCIAL.CASH_REGISTER.STATUS_OPEN')
                : $t('FINANCIAL.CASH_REGISTER.STATUS_CLOSED')
            }}
          </span>
          <span class="cr-status-bar__operator">
            <i class="i-lucide-user" />
            {{ register.operator_name }}
          </span>
        </div>

        <!-- KPI cards -->
        <div class="cr-kpi-grid">
          <div class="cr-kpi-card">
            <span class="cr-kpi-card__label">{{
              $t('FINANCIAL.CASH_REGISTER.OPENING_BALANCE')
            }}</span>
            <span class="cr-kpi-card__value">{{
              fmt(register.opening_balance)
            }}</span>
          </div>
          <div class="cr-kpi-card cr-kpi-card--positive">
            <span class="cr-kpi-card__label">{{
              $t('FINANCIAL.CASH_REGISTER.SUPPLEMENTS')
            }}</span>
            <span class="cr-kpi-card__value cr-val--positive">{{
              fmt(register.supplements)
            }}</span>
          </div>
          <div class="cr-kpi-card cr-kpi-card--negative">
            <span class="cr-kpi-card__label">{{
              $t('FINANCIAL.CASH_REGISTER.WITHDRAWALS')
            }}</span>
            <span class="cr-kpi-card__value cr-val--negative">{{
              fmt(register.withdrawals)
            }}</span>
          </div>
          <div class="cr-kpi-card cr-kpi-card--highlight">
            <span class="cr-kpi-card__label">{{
              $t('FINANCIAL.CASH_REGISTER.CALCULATED')
            }}</span>
            <span class="cr-kpi-card__value">{{
              fmt(register.calculated_balance)
            }}</span>
          </div>
          <template v-if="isClosed">
            <div class="cr-kpi-card">
              <span class="cr-kpi-card__label">{{
                $t('FINANCIAL.CASH_REGISTER.DECLARED_BALANCE')
              }}</span>
              <span class="cr-kpi-card__value">{{
                fmt(register.declared_balance)
              }}</span>
            </div>
            <div class="cr-kpi-card">
              <span class="cr-kpi-card__label">{{
                $t('FINANCIAL.CASH_REGISTER.DIFFERENCE')
              }}</span>
              <span class="cr-kpi-card__value" :class="diffClass">
                {{ fmtDiff(register.difference) }}
              </span>
            </div>
          </template>
        </div>

        <!-- Action buttons (only when open) -->
        <div v-if="isOpen" class="cr-actions">
          <button
            class="cr-btn cr-btn--secondary"
            @click="
              () => {
                showEntryForm = !showEntryForm;
                entryType = 'supplement';
              }
            "
          >
            <i class="i-lucide-plus-circle" />
            {{ $t('FINANCIAL.CASH_REGISTER.SUPPLEMENT') }}
          </button>
          <button
            class="cr-btn cr-btn--warning"
            @click="
              () => {
                showEntryForm = !showEntryForm;
                entryType = 'withdrawal';
              }
            "
          >
            <i class="i-lucide-minus-circle" />
            {{ $t('FINANCIAL.CASH_REGISTER.WITHDRAWAL') }}
          </button>
          <button
            class="cr-btn cr-btn--danger"
            @click="showCloseForm = !showCloseForm"
          >
            <i class="i-lucide-lock" />
            {{ $t('FINANCIAL.CASH_REGISTER.CLOSE') }}
          </button>
        </div>

        <!-- Action buttons (only when closed) -->
        <div v-if="isClosed" class="cr-actions">
          <button
            class="cr-btn cr-btn--secondary"
            :disabled="submitting"
            @click="reopenRegister"
          >
            <i class="i-lucide-rotate-ccw" />
            {{ $t('FINANCIAL.CASH_REGISTER.REOPEN') }}
          </button>
          <button
            class="cr-btn cr-btn--primary"
            @click="
              () => {
                register = null;
                openingBalanceRaw = '';
              }
            "
          >
            <i class="i-lucide-calculator" />
            {{ $t('FINANCIAL.CASH_REGISTER.OPEN_NEW') }}
          </button>
        </div>

        <!-- Entry form -->
        <div v-if="showEntryForm && isOpen" class="cr-form-panel">
          <h3 class="cr-form-panel__title">
            {{
              entryType === 'supplement'
                ? $t('FINANCIAL.CASH_REGISTER.SUPPLEMENT')
                : $t('FINANCIAL.CASH_REGISTER.WITHDRAWAL')
            }}
          </h3>
          <div class="cr-form-row">
            <div class="cr-form-field">
              <label class="cr-label">{{
                $t('FINANCIAL.CASH_REGISTER.SUPPLEMENT_AMOUNT')
              }}</label>
              <div class="cr-money-input-group">
                <span class="cr-money-input-prefix">{{
                  $t('FINANCIAL.CASH_REGISTER.CURRENCY_SYMBOL') || 'R$'
                }}</span>
                <input
                  v-model="entryAmount"
                  type="text"
                  class="cr-money-input"
                />
              </div>
            </div>
            <div class="cr-form-field">
              <label class="cr-label">{{
                $t('FINANCIAL.CASH_REGISTER.OPERATOR_LABEL')
              }}</label>
              <select v-model="entryPaymentMethod" class="dre-date-input">
                <option
                  v-for="pm in paymentMethods"
                  :key="pm.value"
                  :value="pm.value"
                >
                  {{ $t(`FINANCIAL.CASH_REGISTER.${pm.labelKey}`) }}
                </option>
              </select>
            </div>
          </div>
          <div class="cr-form-field cr-form-field--full">
            <label class="cr-label">{{
              $t('FINANCIAL.CASH_REGISTER.SUPPLEMENT_DESCRIPTION')
            }}</label>
            <input
              v-model="entryDescription"
              type="text"
              class="dre-date-input"
            />
          </div>
          <div class="cr-form-actions">
            <button class="cr-btn cr-btn--ghost" @click="showEntryForm = false">
              {{ $t('FINANCIAL.CASH_REGISTER.CANCEL') }}
            </button>
            <button
              class="cr-btn cr-btn--primary"
              :disabled="submitting || !entryAmount"
              @click="addEntry"
            >
              {{
                submitting
                  ? $t('FINANCIAL.SETTINGS.SAVING')
                  : $t('FINANCIAL.CASH_REGISTER.CONFIRM')
              }}
            </button>
          </div>
        </div>

        <!-- Close form -->
        <div
          v-if="showCloseForm && isOpen"
          class="cr-form-panel cr-form-panel--close"
        >
          <h3 class="cr-form-panel__title">
            {{ $t('FINANCIAL.CASH_REGISTER.CONFIRM_CLOSE') }}
          </h3>
          <div class="cr-close-summary">
            <div class="cr-close-summary__row">
              <span>{{ $t('FINANCIAL.CASH_REGISTER.CALCULATED') }}</span>
              <strong>{{ fmt(register.calculated_balance) }}</strong>
            </div>
          </div>
          <div class="cr-form-field">
            <label class="cr-label">{{
              $t('FINANCIAL.CASH_REGISTER.DECLARED_BALANCE')
            }}</label>
            <div class="cr-money-input-group">
              <span class="cr-money-input-prefix">{{
                $t('FINANCIAL.CASH_REGISTER.CURRENCY_SYMBOL') || 'R$'
              }}</span>
              <input
                v-model="declaredBalance"
                type="text"
                class="cr-money-input"
              />
            </div>
          </div>
          <div class="cr-form-field">
            <label class="cr-label">{{
              $t('FINANCIAL.CASH_REGISTER.CLOSING_NOTES')
            }}</label>
            <textarea v-model="closingNotes" class="cr-textarea" rows="2" />
          </div>
          <div class="cr-form-actions">
            <button class="cr-btn cr-btn--ghost" @click="showCloseForm = false">
              {{ $t('FINANCIAL.CASH_REGISTER.CANCEL') }}
            </button>
            <button
              class="cr-btn cr-btn--danger"
              :disabled="submitting"
              @click="closeRegister"
            >
              <i class="i-lucide-lock" />
              {{ $t('FINANCIAL.CASH_REGISTER.CLOSE') }}
            </button>
          </div>
        </div>

        <!-- Entries list -->
        <div
          v-if="register.entries && register.entries.length"
          class="cr-entries"
        >
          <h3 class="cr-entries__title">
            {{ $t('FINANCIAL.CASH_REGISTER.ENTRIES') }}
          </h3>

          <div class="rep-card">
            <div class="rep-table-wrap">
              <table class="rep-table">
                <thead>
                  <tr>
                    <th class="rep-th">
                      {{ $t('FINANCIAL.REPORTS.TYPE', 'TIPO') }}
                    </th>
                    <th class="rep-th">
                      {{ $t('FINANCIAL.REPORTS.DESCRIPTION', 'DESCRIÇÃO') }}
                    </th>
                    <th class="rep-th">
                      {{ $t('FINANCIAL.REPORTS.DATE', 'DATA/HORA') }}
                    </th>
                    <th class="rep-th rep-th--num">
                      {{ $t('FINANCIAL.REPORTS.AMOUNT', 'VALOR') }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="entry in register.entries"
                    :key="entry.id"
                    class="rep-row"
                  >
                    <td class="rep-td">
                      <span
                        class="rep-badge"
                        :class="
                          entry.entry_type === 'supplement'
                            ? 'rep-badge--success'
                            : 'rep-badge--danger'
                        "
                      >
                        <i
                          :class="
                            entry.entry_type === 'supplement'
                              ? 'i-lucide-arrow-up-circle'
                              : 'i-lucide-arrow-down-circle'
                          "
                          class="fin-mr-1"
                        />
                        {{
                          $t(
                            `FINANCIAL.CASH_REGISTER.ENTRY_${entry.entry_type.toUpperCase()}`
                          )
                        }}
                      </span>
                    </td>
                    <td class="rep-td">{{ entry.description || '\u2014' }}</td>
                    <td class="rep-td fin-text-secondary">
                      {{
                        entry.created_at
                          ? new Date(entry.created_at).toLocaleString([], {
                              hour: '2-digit',
                              minute: '2-digit',
                              day: '2-digit',
                              month: '2-digit',
                            })
                          : '—'
                      }}
                    </td>
                    <td
                      class="rep-td rep-td--num"
                      :class="
                        entry.entry_type === 'supplement'
                          ? 'cr-val--positive'
                          : 'cr-val--negative'
                      "
                    >
                      {{
                        entry.entry_type === 'supplement' ? '\u002B' : '\u2212'
                      }}
                      {{ fmt(entry.amount) }}
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>

        <!-- Closing notes (when closed) -->
        <div v-if="isClosed && register.closing_notes" class="cr-closing-notes">
          <i class="i-lucide-message-square" />
          <p>{{ register.closing_notes }}</p>
        </div>
      </template>
    </div>
    <!-- end today tab -->

    <!-- History tab -->
    <div v-if="activeTab === 'history'" class="cr-history">
      <!-- Month filter bar -->
      <div class="cr-history-filter">
        <label class="cr-label">
          {{ $t('FINANCIAL.CASH_REGISTER.HISTORY_FILTER_MONTH') }}
        </label>
        <input
          v-model="historyMonth"
          type="month"
          class="dre-date-input cr-history-filter__input"
        />
        <button class="cr-btn cr-btn--ghost" @click="fetchHistory">
          <i class="i-lucide-refresh-cw" />
        </button>
      </div>

      <div v-if="historyLoading" class="financial-loading">
        <i class="i-lucide-loader-2 financial-loading__spinner" />
        <p>{{ $t('FINANCIAL.CASH_REGISTER.LOADING') }}</p>
      </div>

      <div v-else-if="groupedHistory.length === 0" class="cr-empty-state">
        <div class="cr-empty-state__icon-wrap">
          <i class="i-lucide-history cr-empty-state__icon" />
        </div>
        <p class="cr-empty-state__title">
          {{ $t('FINANCIAL.CASH_REGISTER.HISTORY_EMPTY') }}
        </p>
      </div>

      <!-- Accordion grouped by date -->
      <div v-else class="cr-history-list">
        <div
          v-for="group in groupedHistory"
          :key="group.date"
          class="cr-history-day"
        >
          <!-- Collapsed header row -->
          <button
            class="cr-history-day__header"
            :class="{
              'cr-history-day__header--open': expandedDates.has(group.date),
            }"
            @click="toggleDate(group.date)"
          >
            <i
              :class="
                expandedDates.has(group.date)
                  ? 'i-lucide-chevron-down'
                  : 'i-lucide-chevron-right'
              "
              class="cr-history-day__chevron"
            />
            <span class="cr-history-day__date">
              {{
                new Date(group.date + 'T00:00:00').toLocaleDateString('pt-BR', {
                  weekday: 'short',
                  day: '2-digit',
                  month: '2-digit',
                  year: 'numeric',
                })
              }}
            </span>
            <span class="cr-history-day__meta">
              <span class="cr-history-day__badge">
                {{ group.registers.length }}
                {{
                  group.registers.length === 1
                    ? $t('FINANCIAL.CASH_REGISTER.HISTORY_REGISTER_SINGULAR')
                    : $t('FINANCIAL.CASH_REGISTER.HISTORY_REGISTER_PLURAL')
                }}
              </span>
              <span class="cr-history-day__sum cr-val--positive">
                {{
                  fmt(
                    group.registers.reduce(
                      (s, r) => s + (r.supplements || 0),
                      0
                    )
                  )
                }}
                <em>{{ $t('FINANCIAL.CASH_REGISTER.SUPPLEMENTS') }}</em>
              </span>
              <span class="cr-history-day__sum cr-val--negative">
                {{
                  fmt(
                    group.registers.reduce(
                      (s, r) => s + (r.withdrawals || 0),
                      0
                    )
                  )
                }}
                <em>{{ $t('FINANCIAL.CASH_REGISTER.WITHDRAWALS') }}</em>
              </span>
              <span class="cr-history-day__sum">
                {{
                  fmt(
                    group.registers.reduce(
                      (s, r) => s + (r.calculated_balance || 0),
                      0
                    )
                  )
                }}
                <em>{{ $t('FINANCIAL.CASH_REGISTER.CALCULATED') }}</em>
              </span>
            </span>
          </button>

          <!-- Expanded body: one card per register -->
          <div
            v-if="expandedDates.has(group.date)"
            class="cr-history-day__body"
          >
            <div
              v-for="reg in group.registers"
              :key="reg.id"
              class="cr-history-reg"
            >
              <!-- Register header -->
              <div class="cr-history-reg__header">
                <span class="cr-history-reg__op">
                  <i class="i-lucide-user" />
                  {{ reg.operator_name || '\u2014' }}
                </span>
                <span
                  class="rep-badge"
                  :class="
                    reg.status === 'open'
                      ? 'rep-badge--success'
                      : 'rep-badge--neutral'
                  "
                >
                  <i
                    :class="
                      reg.status === 'open'
                        ? 'i-lucide-lock-open'
                        : 'i-lucide-lock'
                    "
                  />
                  {{
                    reg.status === 'open'
                      ? $t('FINANCIAL.CASH_REGISTER.STATUS_OPEN')
                      : $t('FINANCIAL.CASH_REGISTER.STATUS_CLOSED')
                  }}
                </span>
                <span class="cr-history-reg__kpi">
                  <em>{{ $t('FINANCIAL.CASH_REGISTER.OPENING_BALANCE') }}</em>
                  {{ fmt(reg.opening_balance) }}
                </span>
                <span class="cr-history-reg__kpi cr-val--positive">
                  <em>{{ $t('FINANCIAL.CASH_REGISTER.SUPPLEMENTS') }}</em>
                  {{ fmt(reg.supplements) }}
                </span>
                <span class="cr-history-reg__kpi cr-val--negative">
                  <em>{{ $t('FINANCIAL.CASH_REGISTER.WITHDRAWALS') }}</em>
                  {{ fmt(reg.withdrawals) }}
                </span>
                <span class="cr-history-reg__kpi">
                  <em>{{ $t('FINANCIAL.CASH_REGISTER.CALCULATED') }}</em>
                  {{ fmt(reg.calculated_balance) }}
                </span>
                <span
                  class="cr-history-reg__kpi"
                  :class="
                    reg.difference == null
                      ? ''
                      : reg.difference >= 0
                        ? 'cr-val--positive'
                        : 'cr-val--negative'
                  "
                >
                  <em>{{ $t('FINANCIAL.CASH_REGISTER.DIFFERENCE') }}</em>
                  {{
                    reg.difference != null ? fmtDiff(reg.difference) : '\u2014'
                  }}
                </span>
              </div>

              <!-- Loading spinner for entries -->
              <div
                v-if="loadingDetail.has(reg.id)"
                class="cr-history-reg__loading"
              >
                <i class="i-lucide-loader-2 financial-loading__spinner" />
              </div>

              <!-- Entries table -->
              <table
                v-else-if="registerCache[reg.id]?.entries?.length"
                class="cr-history-entries"
              >
                <thead>
                  <tr>
                    <th>
                      {{ $t('FINANCIAL.CASH_REGISTER.ENTRY_TYPE_LABEL') }}
                    </th>
                    <th>
                      {{ $t('FINANCIAL.CASH_REGISTER.SUPPLEMENT_DESCRIPTION') }}
                    </th>
                    <th>{{ $t('FINANCIAL.CASH_REGISTER.DATE_TIME') }}</th>
                    <th class="rep-th--num">
                      {{ $t('FINANCIAL.CASH_REGISTER.AMOUNT') }}
                    </th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="e in registerCache[reg.id].entries"
                    :key="e.id"
                    class="rep-row"
                  >
                    <td>
                      <span
                        class="rep-badge"
                        :class="
                          e.entry_type === 'supplement'
                            ? 'rep-badge--success'
                            : 'rep-badge--danger'
                        "
                      >
                        {{
                          e.entry_type === 'supplement'
                            ? $t('FINANCIAL.CASH_REGISTER.SUPPLEMENT')
                            : $t('FINANCIAL.CASH_REGISTER.WITHDRAWAL')
                        }}
                      </span>
                    </td>
                    <td>{{ e.description || '\u2014' }}</td>
                    <td>
                      {{
                        new Date(e.created_at).toLocaleTimeString('pt-BR', {
                          hour: '2-digit',
                          minute: '2-digit',
                        })
                      }}
                    </td>
                    <td
                      class="rep-td--num"
                      :class="
                        e.entry_type === 'supplement'
                          ? 'cr-val--positive'
                          : 'cr-val--negative'
                      "
                    >
                      {{ e.entry_type === 'supplement' ? '\u002B' : '\u2212' }}
                      {{ fmt(e.amount) }}
                    </td>
                  </tr>
                </tbody>
              </table>

              <p
                v-else-if="registerCache[reg.id]"
                class="cr-history-reg__no-entries"
              >
                {{ $t('FINANCIAL.CASH_REGISTER.NO_ENTRIES') }}
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
