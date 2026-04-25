<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import '../financial.css';
import commissionRulesApi from '../api/commissionRules';
import recurringExpensesApi from '../api/recurringExpenses';
import categoriesApi from '../api/categories';
import bankAccountsApi from '../api/bankAccounts';
import goalsApi from '../api/goals';

const { t } = useI18n();
const getters = useStoreGetters();
const agents = computed(() => getters['agents/getAgents'].value || []);

// ── Helper factories ─────────────────────────────────────────────────────
function emptyRuleForm() {
  return {
    professional_id: '',
    commission_type: 'percentage_received',
    value: '',
    financial_category_id: '',
    procedure_name: '',
    specialty: '',
    valid_from: '',
    valid_until: '',
    active: true,
    notes: '',
  };
}

function emptyExpForm() {
  return {
    description: '',
    amount: '',
    frequency: 'monthly',
    due_day: 1,
    competence_rule: 'same_month',
    payment_method: '',
    financial_category_id: '',
    bank_account_id: '',
    start_date: '',
    end_date: '',
    active: true,
    auto_confirm: false,
    notes: '',
  };
}

function emptyBankForm() {
  return {
    name: '',
    bank_name: '',
    bank_code: '',
    account_type: 'checking',
    initial_balance: 0,
    active: true,
  };
}

function emptyCatForm() {
  return {
    name: '',
    category_type: 'expense',
    cost_type: '',
    color: '#64748b',
    icon: '',
    is_default: false,
  };
}

// ── Tabs ─────────────────────────────────────────────────────────────────
const activeTab = ref('commissions');

const tabConfig = [
  {
    key: 'commissions',
    icon: 'i-lucide-percent',
    labelKey: 'FINANCIAL.SETTINGS.TAB_COMMISSIONS',
  },
  {
    key: 'recurring',
    icon: 'i-lucide-repeat',
    labelKey: 'FINANCIAL.SETTINGS.TAB_RECURRING',
  },
  {
    key: 'bank_accounts',
    icon: 'i-lucide-landmark',
    labelKey: 'FINANCIAL.SETTINGS.TAB_BANK_ACCOUNTS',
  },
  {
    key: 'categories',
    icon: 'i-lucide-tag',
    labelKey: 'FINANCIAL.SETTINGS.TAB_CATEGORIES',
  },
  {
    key: 'goals',
    icon: 'i-lucide-target',
    labelKey: 'FINANCIAL.SETTINGS.TAB_GOALS',
  },
];

// ── Shared ────────────────────────────────────────────────────────────────
const categories = ref([]);
const bankAccounts = ref([]);

// ── CommissionRules state ─────────────────────────────────────────────────
const rules = ref([]);
const rulesLoading = ref(false);
const ruleModal = ref(false);
const ruleEditing = ref(null);
const ruleSaving = ref(false);
const ruleForm = ref(emptyRuleForm());

// ── RecurringExpenses state ───────────────────────────────────────────────
const expenses = ref([]);
const expLoading = ref(false);
const expModal = ref(false);
const expEditing = ref(null);
const expSaving = ref(false);
const expForm = ref(emptyExpForm());

const formattedExpAmount = computed({
  get() {
    let val = expForm.value.amount || 0;
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(val);
  },
  set(newVal) {
    const digits = newVal.replace(/\D/g, '');
    expForm.value.amount = digits ? parseInt(digits, 10) / 100 : 0;
  },
});

// ── BankAccounts state ────────────────────────────────────────────────────
const bankLoading = ref(false);
const bankModal = ref(false);
const bankEditing = ref(null);
const bankSaving = ref(false);
const bankForm = ref(emptyBankForm());

const BRAZILIAN_BANKS = [
  { code: '001', name: 'Banco do Brasil', color: '#FFCC00' },
  { code: '341', name: 'Itaú', color: '#EC7000' },
  { code: '237', name: 'Bradesco', color: '#CC092F' },
  { code: '033', name: 'Santander', color: '#EC0000' },
  { code: '104', name: 'Caixa Econômica Federal', color: '#0066B3' },
  { code: '260', name: 'Nubank', color: '#820AD1' },
  { code: '077', name: 'Banco Inter', color: '#FF7A00' },
  { code: '336', name: 'C6 Bank', color: '#000000' },
  { code: '208', name: 'BTG Pactual', color: '#000000' },
  { code: '290', name: 'PagBank', color: '#FF6A00' },
  { code: '323', name: 'Mercado Pago', color: '#009EE3' },
  { code: '380', name: 'PicPay', color: '#21C25E' },
  { code: '735', name: 'Neon', color: '#00D4FF' },
  { code: '237', name: 'Next', color: '#00FF5F' },
  { code: '422', name: 'Safra', color: '#1C3F94' },
  { code: '756', name: 'Sicoob', color: '#00A859' },
  { code: '748', name: 'Sicredi', color: '#3FAE2A' },
  { code: '623', name: 'Banco Pan', color: '#E50019' },
  { code: '212', name: 'Banco Original', color: '#00A859' },
];
const showBankDropdown = ref(false);
const showDeleteBankModal = ref(false);
const bankToDelete = ref(null);

const filteredBanks = computed(() => {
  const nameQuery = (bankForm.value.bank_name || '').toLowerCase();
  const codeQuery = (bankForm.value.bank_code || '').toLowerCase();

  if (!nameQuery && !codeQuery) {
    return BRAZILIAN_BANKS;
  }

  return BRAZILIAN_BANKS.filter(b => {
    const matchName = nameQuery && b.name.toLowerCase().includes(nameQuery);
    const matchCode = codeQuery && b.code.includes(codeQuery);
    return Boolean(matchName || matchCode);
  });
});

function hideBankDropdown() {
  setTimeout(() => {
    showBankDropdown.value = false;
  }, 200);
}

const formattedInitialBalance = computed({
  get() {
    let val = bankForm.value.initial_balance || 0;
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(val);
  },
  set(newVal) {
    const digits = newVal.replace(/\D/g, '');
    bankForm.value.initial_balance = digits ? parseInt(digits, 10) / 100 : 0;
  },
});

function selectBank(b) {
  bankForm.value.bank_name = b.name;
  bankForm.value.bank_code = b.code;
  showBankDropdown.value = false;
}

// ── Categories state ──────────────────────────────────────────────────────
const catLoading = ref(false);
const catModal = ref(false);
const catEditing = ref(null);
const catSaving = ref(false);
const catForm = ref(emptyCatForm());

// ── Commission helpers ────────────────────────────────────────────────────
function ruleTypeBadgeClass(type) {
  return type === 'fixed_value' ? 'sets-badge--fixed' : 'sets-badge--pct';
}

function ruleTypeLabel(type) {
  const map = {
    percentage_production: t('FINANCIAL.COMMISSIONS.TYPE_PCT_PROD'),
    percentage_received: t('FINANCIAL.COMMISSIONS.TYPE_PCT_REC'),
    fixed_value: t('FINANCIAL.COMMISSIONS.TYPE_FIXED'),
  };
  return map[type] || type;
}

function freqLabel(freq) {
  const map = {
    monthly: t('FINANCIAL.SETTINGS.FREQ_MONTHLY'),
    weekly: t('FINANCIAL.SETTINGS.FREQ_WEEKLY'),
    biweekly: t('FINANCIAL.SETTINGS.FREQ_BIWEEKLY'),
    quarterly: t('FINANCIAL.SETTINGS.FREQ_QUARTERLY'),
    yearly: t('FINANCIAL.SETTINGS.FREQ_YEARLY'),
  };
  return map[freq] || freq;
}

function formatCurrency(val) {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(val || 0);
}

function bankTypeLabel(type) {
  const map = {
    checking: t('FINANCIAL.SETTINGS.BANK_TYPE_CHECKING'),
    savings: t('FINANCIAL.SETTINGS.BANK_TYPE_SAVINGS'),
    cash: t('FINANCIAL.SETTINGS.BANK_TYPE_CASH'),
  };
  return map[type] || type;
}

function catTypeLabel(type) {
  return type === 'income'
    ? t('FINANCIAL.SETTINGS.CAT_TYPE_INCOME')
    : t('FINANCIAL.SETTINGS.CAT_TYPE_EXPENSE');
}

// ── CommissionRules actions ───────────────────────────────────────────────
async function loadRules() {
  rulesLoading.value = true;
  try {
    const { data } = await commissionRulesApi.list();
    rules.value = data;
  } finally {
    rulesLoading.value = false;
  }
}

function openRuleModal(rule = null) {
  ruleEditing.value = rule;
  ruleForm.value = rule ? { ...rule } : emptyRuleForm();
  ruleModal.value = true;
}

function closeRuleModal() {
  ruleModal.value = false;
  ruleEditing.value = null;
}

async function saveRule() {
  if (!ruleForm.value.professional_id || !ruleForm.value.value) return;
  ruleSaving.value = true;
  try {
    const payload = { ...ruleForm.value };
    if (ruleEditing.value) {
      const { data } = await commissionRulesApi.update(
        ruleEditing.value.id,
        payload
      );
      const idx = rules.value.findIndex(r => r.id === data.id);
      if (idx !== -1) rules.value[idx] = data;
    } else {
      const { data } = await commissionRulesApi.create(payload);
      rules.value.unshift(data);
    }
    closeRuleModal();
  } finally {
    ruleSaving.value = false;
  }
}

async function deleteRule(rule) {
  await commissionRulesApi.remove(rule.id);
  rules.value = rules.value.filter(r => r.id !== rule.id);
}

// ── RecurringExpenses actions ─────────────────────────────────────────────
async function loadExpenses() {
  expLoading.value = true;
  try {
    const { data } = await recurringExpensesApi.list();
    expenses.value = data;
  } finally {
    expLoading.value = false;
  }
}

function openExpModal(exp = null) {
  expEditing.value = exp;
  expForm.value = exp ? { ...exp } : emptyExpForm();
  expModal.value = true;
}

function closeExpModal() {
  expModal.value = false;
  expEditing.value = null;
}

async function saveExp() {
  if (
    !expForm.value.description ||
    !expForm.value.amount ||
    !expForm.value.frequency ||
    !expForm.value.due_day ||
    !expForm.value.start_date
  ) {
    useAlert(
      'Preencha todos os campos obrigatórios (Descrição, Valor, Frequência, Dia de Venc. e Data de Início).'
    );
    return;
  }
  expSaving.value = true;
  try {
    const payload = { ...expForm.value };
    if (expEditing.value) {
      const { data } = await recurringExpensesApi.update(
        expEditing.value.id,
        payload
      );
      const idx = expenses.value.findIndex(e => e.id === data.id);
      if (idx !== -1) expenses.value[idx] = data;
    } else {
      const { data } = await recurringExpensesApi.create(payload);
      expenses.value.unshift(data);
    }
    useAlert(
      t(
        'FINANCIAL.SETTINGS.SAVED_SUCCESS',
        'Despesa recorrente salva com sucesso.'
      )
    );
    closeExpModal();
  } catch (error) {
    if (error.response?.status === 422) {
      useAlert(
        error.response?.data?.error ||
          'Erro de validação. Verifique os dados inseridos.'
      );
    } else {
      useAlert('Ocorreu um erro inesperado ao salvar.');
    }
  } finally {
    expSaving.value = false;
  }
}

async function deleteExp(exp) {
  await recurringExpensesApi.remove(exp.id);
  expenses.value = expenses.value.filter(e => e.id !== exp.id);
}

// ── BankAccounts actions ─────────────────────────────────────────────────
async function loadBankAccounts() {
  bankLoading.value = true;
  try {
    const { data } = await bankAccountsApi.get();
    bankAccounts.value = data?.bank_accounts || data || [];
  } finally {
    bankLoading.value = false;
  }
}

function openBankModal(bank = null) {
  bankEditing.value = bank;
  bankForm.value = bank ? { ...bank } : emptyBankForm();
  bankModal.value = true;
}

function closeBankModal() {
  bankModal.value = false;
  bankEditing.value = null;
}

async function saveBank() {
  if (!bankForm.value.name) return;
  bankSaving.value = true;
  try {
    const payload = { ...bankForm.value };
    if (bankEditing.value) {
      const { data } = await bankAccountsApi.update(
        bankEditing.value.id,
        payload
      );
      const updatedItem = data.bank_account || data;
      const idx = bankAccounts.value.findIndex(b => b.id === updatedItem.id);
      if (idx !== -1) bankAccounts.value[idx] = updatedItem;
    } else {
      const { data } = await bankAccountsApi.create(payload);
      bankAccounts.value.unshift(data.bank_account || data);
    }
    closeBankModal();
  } finally {
    bankSaving.value = false;
  }
}

function openDeleteBankModal(bank) {
  bankToDelete.value = bank;
  showDeleteBankModal.value = true;
}

function closeDeleteBankModal() {
  showDeleteBankModal.value = false;
  bankToDelete.value = null;
}

async function deleteBank() {
  if (!bankToDelete.value) return;
  await bankAccountsApi.delete(bankToDelete.value.id);
  bankAccounts.value = bankAccounts.value.filter(
    b => b.id !== bankToDelete.value.id
  );
  closeDeleteBankModal();
}

// ── Categories actions ───────────────────────────────────────────────────
async function loadCategories() {
  catLoading.value = true;
  try {
    const { data } = await categoriesApi.get();
    categories.value = data?.categories || data || [];
  } finally {
    catLoading.value = false;
  }
}

function openCatModal(cat = null) {
  catEditing.value = cat;
  catForm.value = cat ? { ...cat } : emptyCatForm();
  catModal.value = true;
}

function closeCatModal() {
  catModal.value = false;
  catEditing.value = null;
}

async function saveCat() {
  if (!catForm.value.name) return;
  catSaving.value = true;
  try {
    const payload = { ...catForm.value };
    if (catEditing.value) {
      const { data } = await categoriesApi.update(catEditing.value.id, payload);
      const idx = categories.value.findIndex(c => c.id === data.id);
      if (idx !== -1) categories.value[idx] = data;
    } else {
      const { data } = await categoriesApi.create(payload);
      categories.value.unshift(data);
    }
    closeCatModal();
  } finally {
    catSaving.value = false;
  }
}

async function deleteCat(cat) {
  await categoriesApi.delete(cat.id);
  categories.value = categories.value.filter(c => c.id !== cat.id);
}

// ── Goals actions ────────────────────────────────────────────────────────
const goalsLoading = ref(false);
const goalsSaving = ref(false);
const goalsForm = ref({
  monthly_goal: 0,
  quarterly_goal: 0,
  annual_goal: 0,
});

const formattedMonthlyGoal = computed({
  get() {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(goalsForm.value.monthly_goal || 0);
  },
  set(newVal) {
    const digits = newVal.replace(/\D/g, '');
    goalsForm.value.monthly_goal = digits ? parseInt(digits, 10) / 100 : 0;
  },
});

const formattedQuarterlyGoal = computed({
  get() {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(goalsForm.value.quarterly_goal || 0);
  },
  set(newVal) {
    const digits = newVal.replace(/\D/g, '');
    goalsForm.value.quarterly_goal = digits ? parseInt(digits, 10) / 100 : 0;
  },
});

const formattedAnnualGoal = computed({
  get() {
    return new Intl.NumberFormat('pt-BR', {
      style: 'currency',
      currency: 'BRL',
    }).format(goalsForm.value.annual_goal || 0);
  },
  set(newVal) {
    const digits = newVal.replace(/\D/g, '');
    goalsForm.value.annual_goal = digits ? parseInt(digits, 10) / 100 : 0;
  },
});

async function loadGoals() {
  goalsLoading.value = true;
  try {
    const { data } = await goalsApi.get();
    goalsForm.value = { ...data };
  } finally {
    goalsLoading.value = false;
  }
}

async function saveGoals() {
  goalsSaving.value = true;
  try {
    const { data } = await goalsApi.update(goalsForm.value);
    goalsForm.value = { ...data };
    useAlert(t('FINANCIAL.SETTINGS.SAVED_SUCCESS', 'Salvo com sucesso.'));
  } catch (error) {
    useAlert(t('FINANCIAL.SETTINGS.ERROR_LOAD', 'Erro ao salvar.'));
  } finally {
    goalsSaving.value = false;
  }
}

// ── Goals Insights ────────────────────────────────────────────────────────
const formatGoalsCurrency = val =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(
    val
  );

const currentDate = new Date();
const currentMonthStr = currentDate.toLocaleString('pt-BR', { month: 'long' });
const daysInMonth = new Date(
  currentDate.getFullYear(),
  currentDate.getMonth() + 1,
  0
).getDate();
const businessDaysInMonth = Array.from(
  { length: daysInMonth },
  (_, i) => i + 1
).reduce((acc, d) => {
  const day = new Date(currentDate.getFullYear(), currentDate.getMonth(), d);
  return day.getDay() !== 0 && day.getDay() !== 6 ? acc + 1 : acc;
}, 0);

const dailyTargetAllDays = computed(() => {
  if (!goalsForm.value.monthly_goal) return formatGoalsCurrency(0);
  return formatGoalsCurrency(goalsForm.value.monthly_goal / daysInMonth);
});
const dailyTargetBusinessDays = computed(() => {
  if (!goalsForm.value.monthly_goal) return formatGoalsCurrency(0);
  return formatGoalsCurrency(
    goalsForm.value.monthly_goal / businessDaysInMonth
  );
});

// ── Init ──────────────────────────────────────────────────────────────────
onMounted(async () => {
  await Promise.all([
    loadRules(),
    loadExpenses(),
    loadBankAccounts(),
    loadCategories(),
    loadGoals(),
  ]);
});
</script>

<template>
  <div class="financial-page">
    <!-- Header -->
    <div class="financial-page__header">
      <div>
        <h1 class="financial-page__title">
          <span class="i-lucide-settings" />
          {{ t('FINANCIAL.SETTINGS.TITLE') }}
        </h1>
        <p class="financial-page__subtitle">
          {{ t('FINANCIAL.SETTINGS.SUBTITLE') }}
        </p>
      </div>
    </div>

    <!-- Tabs -->
    <div class="sets-tabs">
      <button
        v-for="tab in tabConfig"
        :key="tab.key"
        class="sets-tab"
        :class="{ 'sets-tab--active': activeTab === tab.key }"
        @click="activeTab = tab.key"
      >
        <span :class="tab.icon" />
        {{ t(tab.labelKey) }}
      </button>
    </div>

    <!-- ═══════════════════════════════════════════════
         TAB: Metas de Receita
         ═══════════════════════════════════════════════ -->
    <div v-if="activeTab === 'goals'" class="sets-section-wrap">
      <div class="sets-section-header">
        <div>
          <p class="sets-section-title">
            {{ t('FINANCIAL.SETTINGS.GOALS_TITLE') }}
          </p>
          <p class="sets-section-desc">
            {{ t('FINANCIAL.SETTINGS.GOALS_DESC') }}
          </p>
        </div>
      </div>

      <div v-if="goalsLoading" class="goals-loading-state">
        <span class="i-lucide-loader-circle goals-loading-state__icon" />
        <span>{{ t('FINANCIAL.SETTINGS.LOADING') }}</span>
      </div>

      <div v-else class="goals-layout">
        <!-- ── Coluna Esquerda: Cards de meta ── -->
        <div class="goals-cards-col">
          <!-- Card Meta Mensal -->
          <div class="goals-goal-card goals-goal-card--monthly">
            <div class="goals-goal-card__header">
              <span
                class="goals-goal-card__icon-wrap goals-goal-card__icon-wrap--monthly"
              >
                <span class="i-lucide-calendar-days" />
              </span>
              <div>
                <p class="goals-goal-card__label">
                  {{ t('FINANCIAL.SETTINGS.MONTHLY_GOAL') }}
                </p>
                <p class="goals-goal-card__hint">
                  {{ t('FINANCIAL.SETTINGS.GOALS_HINT_MONTHLY') }}
                </p>
              </div>
            </div>
            <input
              v-model="formattedMonthlyGoal"
              type="text"
              class="goals-input"
              :placeholder="t('FINANCIAL.SETTINGS.GOALS_INPUT_PLACEHOLDER')"
            />
          </div>

          <!-- Card Meta Trimestral -->
          <div class="goals-goal-card goals-goal-card--quarterly">
            <div class="goals-goal-card__header">
              <span
                class="goals-goal-card__icon-wrap goals-goal-card__icon-wrap--quarterly"
              >
                <span class="i-lucide-chart-no-axes-column" />
              </span>
              <div>
                <p class="goals-goal-card__label">
                  {{ t('FINANCIAL.SETTINGS.QUARTERLY_GOAL') }}
                </p>
                <p class="goals-goal-card__hint">
                  {{ t('FINANCIAL.SETTINGS.GOALS_HINT_QUARTERLY') }}
                </p>
              </div>
            </div>
            <input
              v-model="formattedQuarterlyGoal"
              type="text"
              class="goals-input"
              :placeholder="t('FINANCIAL.SETTINGS.GOALS_INPUT_PLACEHOLDER')"
            />
          </div>

          <!-- Card Meta Anual -->
          <div class="goals-goal-card goals-goal-card--annual">
            <div class="goals-goal-card__header">
              <span
                class="goals-goal-card__icon-wrap goals-goal-card__icon-wrap--annual"
              >
                <span class="i-lucide-trophy" />
              </span>
              <div>
                <p class="goals-goal-card__label">
                  {{ t('FINANCIAL.SETTINGS.ANNUAL_GOAL') }}
                </p>
                <p class="goals-goal-card__hint">
                  {{ t('FINANCIAL.SETTINGS.GOALS_HINT_ANNUAL') }}
                </p>
              </div>
            </div>
            <input
              v-model="formattedAnnualGoal"
              type="text"
              class="goals-input"
              :placeholder="t('FINANCIAL.SETTINGS.GOALS_INPUT_PLACEHOLDER')"
            />
          </div>

          <!-- Botão Salvar -->
          <button
            class="sets-save-btn goals-save-btn"
            :disabled="goalsSaving"
            @click="saveGoals"
          >
            <span
              v-if="goalsSaving"
              class="i-lucide-loader-circle goals-save-btn__spinner"
            />
            <span v-else class="i-lucide-check" />
            {{
              goalsSaving
                ? t('FINANCIAL.SETTINGS.SAVING')
                : t('FINANCIAL.SETTINGS.SAVE')
            }}
          </button>
        </div>

        <!-- ── Coluna Direita: Painel de Projeção ── -->
        <div class="goals-insights-col">
          <!-- Cabeçalho da coluna -->
          <div class="goals-insights-header">
            <span class="i-lucide-zap goals-insights-header__icon" />
            <div>
              <p class="goals-insights-header__title">
                {{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_TITLE') }}
              </p>
              <p class="goals-insights-header__month">
                {{ currentMonthStr }}
              </p>
            </div>
          </div>

          <!-- Separator -->
          <div class="goals-insights-divider" />

          <!-- Projeção por dia corrido -->
          <div class="goals-pace-card">
            <div class="goals-pace-card__left">
              <span
                class="goals-pace-card__dot goals-pace-card__dot--neutral"
              />
              <div>
                <p class="goals-pace-card__type">
                  {{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_CONTINUOUS')
                  }}{{ daysInMonth
                  }}{{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_DAYS_SUFFIX') }}
                </p>
                <p class="goals-pace-card__desc">
                  {{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_PER_DAY') }}
                </p>
              </div>
            </div>
            <span
              class="goals-pace-card__value goals-pace-card__value--neutral"
            >
              {{ dailyTargetAllDays }}
            </span>
          </div>

          <!-- Projeção por dia útil -->
          <div class="goals-pace-card goals-pace-card--highlight">
            <div class="goals-pace-card__left">
              <span
                class="goals-pace-card__dot goals-pace-card__dot--highlight"
              />
              <div>
                <p class="goals-pace-card__type">
                  {{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_BUSINESS')
                  }}{{ businessDaysInMonth
                  }}{{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_DAYS_SUFFIX') }}
                </p>
                <p class="goals-pace-card__desc">
                  {{ t('FINANCIAL.SETTINGS.GOALS_INSIGHT_PER_BDAY') }}
                </p>
              </div>
            </div>
            <span
              class="goals-pace-card__value goals-pace-card__value--highlight"
            >
              {{ dailyTargetBusinessDays }}
            </span>
          </div>

          <!-- Info contextual -->
          <div class="goals-info-tip">
            <span class="i-lucide-info goals-info-tip__icon" />
            <p class="goals-info-tip__text">
              {{ t('FINANCIAL.SETTINGS.GOALS_TIP') }}
            </p>
          </div>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════
         TAB: Regras de Comissão
         ═══════════════════════════════════════════════ -->
    <div v-if="activeTab === 'commissions'" class="sets-section-wrap">
      <div class="sets-section-header">
        <div>
          <p class="sets-section-title">
            {{ t('FINANCIAL.SETTINGS.COMM_RULES_TITLE') }}
          </p>
          <p class="sets-section-desc">
            {{ t('FINANCIAL.SETTINGS.COMM_RULES_DESC') }}
          </p>
        </div>
        <button class="sets-add-btn" @click="openRuleModal()">
          <span class="i-lucide-plus" />
          {{ t('FINANCIAL.SETTINGS.ADD_RULE') }}
        </button>
      </div>

      <div class="sets-body">
        <div v-if="rulesLoading" class="fin-loading">
          {{ t('FINANCIAL.SETTINGS.LOADING') }}
        </div>

        <div v-else-if="rules.length === 0" class="sets-empty">
          <span class="sets-empty__icon i-lucide-percent" />
          <p class="sets-empty__text">
            {{ t('FINANCIAL.SETTINGS.COMM_EMPTY') }}
          </p>
        </div>

        <div v-else class="sets-table-wrap">
          <table class="sets-table">
            <thead>
              <tr>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_PROFESSIONAL') }}
                </th>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_TYPE') }}
                </th>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_VALUE') }}
                </th>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_SCOPE') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.COL_STATUS') }}
                </th>
                <th class="sets-table__th sets-table__th--right">
                  {{ t('FINANCIAL.SETTINGS.COL_ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="rule in rules" :key="rule.id" class="sets-row">
                <td class="sets-table__td">
                  <strong>{{
                    rule.professional_name || `#${rule.professional_id}`
                  }}</strong>
                </td>
                <td class="sets-table__td">
                  <span
                    class="sets-badge"
                    :class="ruleTypeBadgeClass(rule.commission_type)"
                  >
                    {{ ruleTypeLabel(rule.commission_type) }}
                  </span>
                </td>
                <td class="sets-table__td">
                  <span v-if="rule.commission_type === 'fixed_value'">
                    {{ formatCurrency(rule.value) }}
                  </span>
                  <span v-else>{{ rule.value }}%</span>
                </td>
                <td class="sets-table__td">
                  <span v-if="rule.procedure_name" class="fin-text-secondary">{{
                    rule.procedure_name
                  }}</span>
                  <span
                    v-else-if="rule.category_name"
                    class="fin-text-secondary"
                    >{{ rule.category_name }}</span>
                  <span v-else class="fin-text-muted">
                    {{ t('FINANCIAL.SETTINGS.SCOPE_GENERAL') }}
                  </span>
                </td>
                <td class="sets-table__td sets-table__td--center">
                  <span
                    class="sets-badge"
                    :class="
                      rule.active
                        ? 'sets-badge--active'
                        : 'sets-badge--inactive'
                    "
                  >
                    {{
                      rule.active
                        ? t('FINANCIAL.SETTINGS.ACTIVE')
                        : t('FINANCIAL.SETTINGS.INACTIVE')
                    }}
                  </span>
                </td>
                <td class="sets-table__td sets-table__td--right">
                  <div class="sets-actions">
                    <button
                      class="sets-btn sets-btn--edit"
                      :title="t('FINANCIAL.SETTINGS.EDIT')"
                      @click="openRuleModal(rule)"
                    >
                      <span class="i-lucide-pencil" />
                    </button>
                    <button
                      class="sets-btn sets-btn--delete"
                      :title="t('FINANCIAL.SETTINGS.DELETE')"
                      @click="deleteRule(rule)"
                    >
                      <span class="i-lucide-trash-2" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════
         TAB: Despesas Recorrentes
         ═══════════════════════════════════════════════ -->
    <div v-if="activeTab === 'recurring'" class="sets-section-wrap">
      <div class="sets-section-header">
        <div>
          <p class="sets-section-title">
            {{ t('FINANCIAL.SETTINGS.REC_TITLE') }}
          </p>
          <p class="sets-section-desc">
            {{ t('FINANCIAL.SETTINGS.REC_DESC') }}
          </p>
        </div>
        <button class="sets-add-btn" @click="openExpModal()">
          <span class="i-lucide-plus" />
          {{ t('FINANCIAL.SETTINGS.ADD_RECURRING') }}
        </button>
      </div>

      <div class="sets-body">
        <div v-if="expLoading" class="fin-loading">
          {{ t('FINANCIAL.SETTINGS.LOADING') }}
        </div>

        <div v-else-if="expenses.length === 0" class="sets-empty">
          <span class="sets-empty__icon i-lucide-repeat" />
          <p class="sets-empty__text">
            {{ t('FINANCIAL.SETTINGS.REC_EMPTY') }}
          </p>
        </div>

        <div v-else class="sets-table-wrap">
          <table class="sets-table">
            <thead>
              <tr>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_DESCRIPTION') }}
                </th>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_CATEGORY') }}
                </th>
                <th class="sets-table__th sets-table__th--right">
                  {{ t('FINANCIAL.SETTINGS.COL_AMOUNT') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.COL_FREQUENCY') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.COL_DUE_DAY') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.COL_STATUS') }}
                </th>
                <th class="sets-table__th sets-table__th--right">
                  {{ t('FINANCIAL.SETTINGS.COL_ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="exp in expenses" :key="exp.id" class="sets-row">
                <td class="sets-table__td">
                  <strong>{{ exp.description }}</strong>
                </td>
                <td class="sets-table__td fin-text-secondary">
                  {{ exp.category_name || '—' }}
                </td>
                <td class="sets-table__td sets-table__td--right">
                  <strong>{{ formatCurrency(exp.amount) }}</strong>
                </td>
                <td class="sets-table__td sets-table__td--center">
                  <span class="sets-badge sets-badge--pct">
                    {{ freqLabel(exp.frequency) }}
                  </span>
                </td>
                <td class="sets-table__td sets-table__td--center">
                  {{ t('FINANCIAL.SETTINGS.DAY') }} {{ exp.due_day }}
                </td>
                <td class="sets-table__td sets-table__td--center">
                  <span
                    class="sets-badge"
                    :class="
                      exp.active ? 'sets-badge--active' : 'sets-badge--inactive'
                    "
                  >
                    {{
                      exp.active
                        ? t('FINANCIAL.SETTINGS.ACTIVE')
                        : t('FINANCIAL.SETTINGS.INACTIVE')
                    }}
                  </span>
                </td>
                <td class="sets-table__td sets-table__td--right">
                  <div class="sets-actions">
                    <button
                      class="sets-btn sets-btn--edit"
                      :title="t('FINANCIAL.SETTINGS.EDIT')"
                      @click="openExpModal(exp)"
                    >
                      <span class="i-lucide-pencil" />
                    </button>
                    <button
                      class="sets-btn sets-btn--delete"
                      :title="t('FINANCIAL.SETTINGS.DELETE')"
                      @click="deleteExp(exp)"
                    >
                      <span class="i-lucide-trash-2" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════
         TAB: Contas Bancárias
         ═══════════════════════════════════════════════ -->
    <div v-if="activeTab === 'bank_accounts'" class="sets-section-wrap">
      <div class="sets-section-header">
        <div>
          <p class="sets-section-title">
            {{ t('FINANCIAL.SETTINGS.BANK_TITLE') }}
          </p>
          <p class="sets-section-desc">
            {{ t('FINANCIAL.SETTINGS.BANK_DESC') }}
          </p>
        </div>
        <button class="sets-add-btn" @click="openBankModal()">
          <span class="i-lucide-plus" />
          {{ t('FINANCIAL.SETTINGS.ADD_BANK') }}
        </button>
      </div>

      <div class="sets-body">
        <div v-if="bankLoading" class="fin-loading">
          {{ t('FINANCIAL.SETTINGS.LOADING') }}
        </div>

        <div v-else-if="bankAccounts.length === 0" class="sets-empty">
          <span class="sets-empty__icon i-lucide-landmark" />
          <p class="sets-empty__text">
            {{ t('FINANCIAL.SETTINGS.BANK_EMPTY') }}
          </p>
        </div>

        <div v-else class="sets-table-wrap">
          <table class="sets-table">
            <thead>
              <tr>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.BANK_NAME') }}
                </th>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_BANK') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.BANK_TYPE') }}
                </th>
                <th class="sets-table__th sets-table__th--right">
                  {{ t('FINANCIAL.SETTINGS.COL_BALANCE') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.COL_STATUS') }}
                </th>
                <th class="sets-table__th sets-table__th--right">
                  {{ t('FINANCIAL.SETTINGS.COL_ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="bank in bankAccounts" :key="bank.id" class="sets-row">
                <td class="sets-table__td">
                  <strong>{{ bank.name }}</strong>
                </td>
                <td class="sets-table__td fin-text-secondary">
                  {{ bank.bank_name || '—' }}
                </td>
                <td class="sets-table__td sets-table__td--center">
                  <span class="sets-badge sets-badge--pct">
                    {{ bankTypeLabel(bank.account_type) }}
                  </span>
                </td>
                <td class="sets-table__td sets-table__td--right">
                  <strong>{{ formatCurrency(bank.initial_balance) }}</strong>
                </td>
                <td class="sets-table__td sets-table__td--center">
                  <span
                    class="sets-badge"
                    :class="
                      bank.active !== false
                        ? 'sets-badge--active'
                        : 'sets-badge--inactive'
                    "
                  >
                    {{
                      bank.active !== false
                        ? t('FINANCIAL.SETTINGS.ACTIVE')
                        : t('FINANCIAL.SETTINGS.INACTIVE')
                    }}
                  </span>
                </td>
                <td class="sets-table__td sets-table__td--right">
                  <div class="sets-actions">
                    <button
                      class="sets-btn sets-btn--edit"
                      :title="t('FINANCIAL.SETTINGS.EDIT')"
                      @click="openBankModal(bank)"
                    >
                      <span class="i-lucide-pencil" />
                    </button>
                    <button
                      class="sets-btn sets-btn--delete"
                      :title="t('FINANCIAL.SETTINGS.DELETE')"
                      @click="openDeleteBankModal(bank)"
                    >
                      <span class="i-lucide-trash-2" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- ═══════════════════════════════════════════════
         TAB: Categorias Financeiras
         ═══════════════════════════════════════════════ -->
    <div v-if="activeTab === 'categories'" class="sets-section-wrap">
      <div class="sets-section-header">
        <div>
          <p class="sets-section-title">
            {{ t('FINANCIAL.SETTINGS.CAT_TITLE') }}
          </p>
          <p class="sets-section-desc">
            {{ t('FINANCIAL.SETTINGS.CAT_DESC') }}
          </p>
        </div>
        <button class="sets-add-btn" @click="openCatModal()">
          <span class="i-lucide-plus" />
          {{ t('FINANCIAL.SETTINGS.ADD_CATEGORY') }}
        </button>
      </div>

      <div class="sets-body">
        <div v-if="catLoading" class="fin-loading">
          {{ t('FINANCIAL.SETTINGS.LOADING') }}
        </div>

        <div v-else-if="categories.length === 0" class="sets-empty">
          <span class="sets-empty__icon i-lucide-tag" />
          <p class="sets-empty__text">
            {{ t('FINANCIAL.SETTINGS.CAT_EMPTY') }}
          </p>
        </div>

        <div v-else class="sets-table-wrap">
          <table class="sets-table">
            <thead>
              <tr>
                <th class="sets-table__th">
                  {{ t('FINANCIAL.SETTINGS.COL_NAME') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.COL_CAT_TYPE') }}
                </th>
                <th class="sets-table__th sets-table__th--center">
                  {{ t('FINANCIAL.SETTINGS.CAT_COST_TYPE') }}
                </th>
                <th class="sets-table__th sets-table__th--right">
                  {{ t('FINANCIAL.SETTINGS.COL_ACTIONS') }}
                </th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="cat in categories" :key="cat.id" class="sets-row">
                <td class="sets-table__td">
                  <div class="sets-cat-name">
                    <span
                      v-if="cat.color"
                      class="sets-cat-color"
                      :style="{ backgroundColor: cat.color }"
                    />
                    <strong>{{ cat.name }}</strong>
                  </div>
                </td>
                <td class="sets-table__td sets-table__td--center">
                  <span
                    class="sets-badge"
                    :class="
                      cat.category_type === 'income'
                        ? 'sets-badge--active'
                        : 'sets-badge--fixed'
                    "
                  >
                    {{ catTypeLabel(cat.category_type) }}
                  </span>
                </td>
                <td
                  class="sets-table__td sets-table__td--center fin-text-secondary"
                >
                  {{ cat.cost_type || '—' }}
                </td>
                <td class="sets-table__td sets-table__td--right">
                  <div class="sets-actions">
                    <button
                      class="sets-btn sets-btn--edit"
                      :title="t('FINANCIAL.SETTINGS.EDIT')"
                      @click="openCatModal(cat)"
                    >
                      <span class="i-lucide-pencil" />
                    </button>
                    <button
                      v-if="!cat.is_default"
                      class="sets-btn sets-btn--delete"
                      :title="t('FINANCIAL.SETTINGS.DELETE')"
                      @click="deleteCat(cat)"
                    >
                      <span class="i-lucide-trash-2" />
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <Teleport to="body">
      <!-- ═══════════════════════════════════════════════
         MODAL: CommissionRule
         ═══════════════════════════════════════════════ -->
      <div
        v-if="ruleModal"
        class="sets-modal-overlay"
        @click.self="closeRuleModal"
      >
        <div class="sets-modal">
          <p class="sets-modal__title">
            {{
              ruleEditing
                ? t('FINANCIAL.SETTINGS.EDIT_RULE')
                : t('FINANCIAL.SETTINGS.NEW_RULE')
            }}
          </p>

          <div class="sets-form">
            <div class="sets-field">
              <label class="sets-label">
                {{ t('FINANCIAL.COMMISSIONS.PROFESSIONAL') }}
              </label>
              <select v-model="ruleForm.professional_id" class="sets-select">
                <option value="">
                  {{ t('FINANCIAL.COMMISSIONS.SELECT_AGENT') }}
                </option>
                <option v-for="a in agents" :key="a.id" :value="a.id">
                  {{ a.name }}
                </option>
              </select>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.RULE_TYPE') }}
                </label>
                <select v-model="ruleForm.commission_type" class="sets-select">
                  <option value="percentage_received">
                    {{ t('FINANCIAL.COMMISSIONS.TYPE_PCT_REC') }}
                  </option>
                  <option value="percentage_production">
                    {{ t('FINANCIAL.COMMISSIONS.TYPE_PCT_PROD') }}
                  </option>
                  <option value="fixed_value">
                    {{ t('FINANCIAL.COMMISSIONS.TYPE_FIXED') }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{
                    ruleForm.commission_type === 'fixed_value'
                      ? t('FINANCIAL.SETTINGS.RULE_FIXED_VALUE')
                      : t('FINANCIAL.SETTINGS.RULE_PCT')
                  }}
                </label>
                <input
                  v-model="ruleForm.value"
                  type="number"
                  min="0"
                  step="0.01"
                  class="sets-input"
                />
              </div>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.SCOPE_CATEGORY') }}
                </label>
                <select
                  v-model="ruleForm.financial_category_id"
                  class="sets-select"
                >
                  <option value="">
                    {{ t('FINANCIAL.SETTINGS.SCOPE_ALL') }}
                  </option>
                  <option v-for="c in categories" :key="c.id" :value="c.id">
                    {{ c.name }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.SCOPE_PROCEDURE') }}
                </label>
                <input
                  v-model="ruleForm.procedure_name"
                  type="text"
                  class="sets-input"
                  :placeholder="t('FINANCIAL.SETTINGS.OPTIONAL')"
                />
              </div>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.VALID_FROM') }}
                </label>
                <input
                  v-model="ruleForm.valid_from"
                  type="date"
                  class="sets-input"
                />
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.VALID_UNTIL') }}
                </label>
                <input
                  v-model="ruleForm.valid_until"
                  type="date"
                  class="sets-input"
                />
              </div>
            </div>

            <div class="sets-field">
              <label class="sets-label">{{
                t('FINANCIAL.SETTINGS.NOTES')
              }}</label>
              <textarea v-model="ruleForm.notes" class="sets-textarea" />
            </div>

            <label class="sets-toggle-row">
              <input v-model="ruleForm.active" type="checkbox" />
              {{ t('FINANCIAL.SETTINGS.RULE_ACTIVE') }}
            </label>
          </div>

          <div class="sets-modal-footer">
            <button class="sets-cancel-btn" @click="closeRuleModal">
              {{ t('FINANCIAL.SETTINGS.CANCEL') }}
            </button>
            <button
              class="sets-save-btn"
              :disabled="ruleSaving"
              @click="saveRule"
            >
              {{
                ruleSaving
                  ? t('FINANCIAL.SETTINGS.SAVING')
                  : t('FINANCIAL.SETTINGS.SAVE')
              }}
            </button>
          </div>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════
         MODAL: RecurringExpense
         ═══════════════════════════════════════════════ -->
      <div
        v-if="expModal"
        class="sets-modal-overlay"
        @click.self="closeExpModal"
      >
        <div class="sets-modal">
          <p class="sets-modal__title">
            {{
              expEditing
                ? t('FINANCIAL.SETTINGS.EDIT_RECURRING')
                : t('FINANCIAL.SETTINGS.NEW_RECURRING')
            }}
          </p>

          <div class="sets-form">
            <div class="sets-field">
              <label class="sets-label">
                {{ t('FINANCIAL.SETTINGS.REC_DESCRIPTION') }}
              </label>
              <input
                v-model="expForm.description"
                type="text"
                class="sets-input"
                :placeholder="t('FINANCIAL.SETTINGS.REC_DESC_PLACEHOLDER')"
              />
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.COL_AMOUNT') }}
                </label>
                <input
                  v-model="formattedExpAmount"
                  type="text"
                  class="sets-input"
                />
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.COL_CATEGORY') }}
                </label>
                <select
                  v-model="expForm.financial_category_id"
                  class="sets-select"
                >
                  <option value="">
                    {{ t('FINANCIAL.SETTINGS.SCOPE_ALL') }}
                  </option>
                  <option v-for="c in categories" :key="c.id" :value="c.id">
                    {{ c.name }}
                  </option>
                </select>
              </div>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.COL_FREQUENCY') }}
                </label>
                <select v-model="expForm.frequency" class="sets-select">
                  <option value="monthly">
                    {{ t('FINANCIAL.SETTINGS.FREQ_MONTHLY') }}
                  </option>
                  <option value="weekly">
                    {{ t('FINANCIAL.SETTINGS.FREQ_WEEKLY') }}
                  </option>
                  <option value="biweekly">
                    {{ t('FINANCIAL.SETTINGS.FREQ_BIWEEKLY') }}
                  </option>
                  <option value="quarterly">
                    {{ t('FINANCIAL.SETTINGS.FREQ_QUARTERLY') }}
                  </option>
                  <option value="yearly">
                    {{ t('FINANCIAL.SETTINGS.FREQ_YEARLY') }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.COL_DUE_DAY') }}
                </label>
                <input
                  v-model="expForm.due_day"
                  type="number"
                  min="1"
                  max="31"
                  class="sets-input"
                />
              </div>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.COMPETENCE_RULE') }}
                </label>
                <select v-model="expForm.competence_rule" class="sets-select">
                  <option value="same_month">
                    {{ t('FINANCIAL.SETTINGS.COMP_SAME') }}
                  </option>
                  <option value="previous_month">
                    {{ t('FINANCIAL.SETTINGS.COMP_PREV') }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.PAYMENT_METHOD') }}
                </label>
                <select v-model="expForm.payment_method" class="sets-select">
                  <option value="">—</option>
                  <option value="dinheiro">
                    {{ t('FINANCIAL.CASH_REGISTER.PAYMENT_CASH') }}
                  </option>
                  <option value="pix">Pix</option>
                  <option value="cartao_credito">
                    {{ t('FINANCIAL.CASH_REGISTER.PAYMENT_CARD_CREDIT') }}
                  </option>
                  <option value="boleto">Boleto</option>
                  <option value="transferencia">
                    {{ t('FINANCIAL.CASH_REGISTER.PAYMENT_TRANSFER') }}
                  </option>
                </select>
              </div>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.BANK_ACCOUNT') }}
                </label>
                <select v-model="expForm.bank_account_id" class="sets-select">
                  <option value="">—</option>
                  <option v-for="b in bankAccounts" :key="b.id" :value="b.id">
                    {{ b.name }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.START_DATE') }}
                </label>
                <input
                  v-model="expForm.start_date"
                  type="date"
                  class="sets-input"
                />
              </div>
            </div>

            <div class="sets-field">
              <label class="sets-label">{{
                t('FINANCIAL.SETTINGS.NOTES')
              }}</label>
              <textarea v-model="expForm.notes" class="sets-textarea" />
            </div>

            <label class="sets-toggle-row">
              <input v-model="expForm.active" type="checkbox" />
              {{ t('FINANCIAL.SETTINGS.RULE_ACTIVE') }}
            </label>
            <label class="sets-toggle-row">
              <input v-model="expForm.auto_confirm" type="checkbox" />
              {{ t('FINANCIAL.SETTINGS.AUTO_CONFIRM') }}
            </label>
          </div>

          <div class="sets-modal-footer">
            <button class="sets-cancel-btn" @click="closeExpModal">
              {{ t('FINANCIAL.SETTINGS.CANCEL') }}
            </button>
            <button
              class="sets-save-btn"
              :disabled="expSaving"
              @click="saveExp"
            >
              {{
                expSaving
                  ? t('FINANCIAL.SETTINGS.SAVING')
                  : t('FINANCIAL.SETTINGS.SAVE')
              }}
            </button>
          </div>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════
         MODAL: BankAccount
         ═══════════════════════════════════════════════ -->
      <div
        v-if="bankModal"
        class="sets-modal-overlay"
        @click.self="closeBankModal"
      >
        <div class="sets-modal">
          <p class="sets-modal__title">
            {{
              bankEditing
                ? t('FINANCIAL.SETTINGS.EDIT_BANK')
                : t('FINANCIAL.SETTINGS.NEW_BANK')
            }}
          </p>

          <div class="sets-form">
            <div class="sets-field">
              <label class="sets-label">
                {{ t('FINANCIAL.SETTINGS.BANK_NAME') }}
              </label>
              <input
                v-model="bankForm.name"
                type="text"
                class="sets-input"
                :placeholder="t('FINANCIAL.SETTINGS.BANK_NAME_PLACEHOLDER')"
              />
            </div>

            <div class="sets-form-row sets-autocomplete-wrapper">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.BANK_CODE') }}
                </label>
                <input
                  v-model="bankForm.bank_code"
                  type="text"
                  class="sets-input"
                  @focus="showBankDropdown = true"
                  @blur="hideBankDropdown"
                />
              </div>

              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.BANK_BANK_NAME') }}
                </label>
                <input
                  v-model="bankForm.bank_name"
                  type="text"
                  class="sets-input"
                  @focus="showBankDropdown = true"
                  @blur="hideBankDropdown"
                />
              </div>

              <div
                v-if="showBankDropdown && filteredBanks.length"
                class="sets-autocomplete-menu"
              >
                <div
                  v-for="b in filteredBanks"
                  :key="b.code"
                  class="sets-autocomplete-item"
                  @click.prevent="selectBank(b)"
                >
                  <span
                    class="sets-autocomplete-color"
                    :style="{ backgroundColor: b.color }"
                  />
                  <span class="sets-autocomplete-code">{{ b.code }}</span>
                  <span class="sets-autocomplete-name">{{ b.name }}</span>
                </div>
              </div>
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.BANK_TYPE') }}
                </label>
                <select v-model="bankForm.account_type" class="sets-select">
                  <option value="checking">
                    {{ t('FINANCIAL.SETTINGS.BANK_TYPE_CHECKING') }}
                  </option>
                  <option value="savings">
                    {{ t('FINANCIAL.SETTINGS.BANK_TYPE_SAVINGS') }}
                  </option>
                  <option value="cash">
                    {{ t('FINANCIAL.SETTINGS.BANK_TYPE_CASH') }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.BANK_INITIAL_BALANCE') }}
                </label>
                <input
                  v-model="formattedInitialBalance"
                  type="text"
                  class="sets-input"
                />
              </div>
            </div>

            <label class="sets-toggle-row">
              <input v-model="bankForm.active" type="checkbox" />
              {{ t('FINANCIAL.SETTINGS.RULE_ACTIVE') }}
            </label>
          </div>

          <div class="sets-modal-footer">
            <button class="sets-cancel-btn" @click="closeBankModal">
              {{ t('FINANCIAL.SETTINGS.CANCEL') }}
            </button>
            <button
              class="sets-save-btn"
              :disabled="bankSaving"
              @click="saveBank"
            >
              {{
                bankSaving
                  ? t('FINANCIAL.SETTINGS.SAVING')
                  : t('FINANCIAL.SETTINGS.SAVE')
              }}
            </button>
          </div>
        </div>
      </div>

      <!-- ═══════════════════════════════════════════════
         MODAL: Category
         ═══════════════════════════════════════════════ -->
      <div
        v-if="catModal"
        class="sets-modal-overlay"
        @click.self="closeCatModal"
      >
        <div class="sets-modal">
          <p class="sets-modal__title">
            {{
              catEditing
                ? t('FINANCIAL.SETTINGS.EDIT_CATEGORY')
                : t('FINANCIAL.SETTINGS.NEW_CATEGORY')
            }}
          </p>

          <div class="sets-form">
            <div class="sets-field">
              <label class="sets-label">
                {{ t('FINANCIAL.SETTINGS.CAT_NAME') }}
              </label>
              <input
                v-model="catForm.name"
                type="text"
                class="sets-input"
                :placeholder="t('FINANCIAL.SETTINGS.CAT_NAME_PLACEHOLDER')"
              />
            </div>

            <div class="sets-form-row">
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.CAT_TYPE') }}
                </label>
                <select v-model="catForm.category_type" class="sets-select">
                  <option value="income">
                    {{ t('FINANCIAL.SETTINGS.CAT_TYPE_INCOME') }}
                  </option>
                  <option value="expense">
                    {{ t('FINANCIAL.SETTINGS.CAT_TYPE_EXPENSE') }}
                  </option>
                </select>
              </div>
              <div class="sets-field">
                <label class="sets-label">
                  {{ t('FINANCIAL.SETTINGS.CAT_COST_TYPE') }}
                </label>
                <select v-model="catForm.cost_type" class="sets-select">
                  <option value="">
                    {{ t('FINANCIAL.SETTINGS.CAT_COST_NONE') }}
                  </option>
                  <option value="fixo">
                    {{ t('FINANCIAL.SETTINGS.CAT_COST_FIXED') }}
                  </option>
                  <option value="variavel">
                    {{ t('FINANCIAL.SETTINGS.CAT_COST_VARIABLE') }}
                  </option>
                </select>
              </div>
            </div>

            <div class="sets-field">
              <label class="sets-label">{{
                t('FINANCIAL.SETTINGS.NOTES')
              }}</label>
              <input
                v-model="catForm.color"
                type="color"
                class="sets-input sets-color-input"
              />
            </div>
          </div>

          <div class="sets-modal-footer">
            <button class="sets-cancel-btn" @click="closeCatModal">
              {{ t('FINANCIAL.SETTINGS.CANCEL') }}
            </button>
            <button
              class="sets-save-btn"
              :disabled="catSaving"
              @click="saveCat"
            >
              {{
                catSaving
                  ? t('FINANCIAL.SETTINGS.SAVING')
                  : t('FINANCIAL.SETTINGS.SAVE')
              }}
            </button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>

  <!-- Modal: Confirmar Exclusão de Conta Bancária -->
  <woot-delete-modal
    v-model:show="showDeleteBankModal"
    :on-close="closeDeleteBankModal"
    :on-confirm="deleteBank"
    title="Excluir conta bancária"
    :message="`Tem certeza que deseja excluir a conta &quot;${bankToDelete?.name}&quot;?`"
    message-value="Esta ação irá desativar o acompanhamento financeiro desta conta e não pode ser desfeita."
    confirm-text="Sim, excluir"
    reject-text="Cancelar"
  />
</template>
