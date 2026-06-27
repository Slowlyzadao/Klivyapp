<script setup>
/**
 * Fluxo de Caixa — v2 (canon F-23).
 *
 * Ledger central de todas as movimentações financeiras (Financial::Entry):
 *   • Manuais (kind='manual_entry') — registradas via "Nova entrada/saída".
 *   • Automáticas — geradas por ReceivePayment (recibo), PayExpense (despesa),
 *     RefundPayment/ReverseExpense (estornos), CashRegister (sangria/suprimento).
 *
 * Diferença das outras telas v2:
 *   • A Receber → parcelas (Financial::Installment) com vencimento futuro.
 *   • A Pagar   → despesas (Financial::Expense) planejadas.
 *   • Fluxo     → entries (movimentação real de caixa) — tudo que JÁ
 *                 afetou saldo de conta bancária ou caixa físico.
 *
 * KPIs:
 *   1. Saldo atual da(s) conta(s) — soma dinâmica (initial + Σentradas - Σsaídas).
 *   2. Entradas no período (filtros aplicados).
 *   3. Saídas no período.
 *   4. Resultado líquido.
 *
 * Componentes globais: Badge, FormSelect, DatePickerBR, Pagination,
 * ProfessionalChip. Padrão visual = ReclassifyV2 + PayablesV2.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { vOnClickOutside } from '@vueuse/components';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import PaymentMethodBadge, {
  PAYMENT_KIND_OPTIONS,
} from '@plugins/beclinic_core/frontend/components/PaymentMethodBadge.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL, bankKindLabel } from '../composables/useMoney';
import { entryHasBreakdown, entryBreakdownTooltipLabel } from '../composables/useInstallmentBreakdown';
import ManualEntryModalV2 from '../components/ManualEntryModalV2.vue';
import TransferModalV2 from '../components/TransferModalV2.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FinSearchInput from '../components/FinSearchInput.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const entries = ref([]);
const meta = ref({});
const bankAccounts = ref([]);
const categories = ref([]);
const loading = ref(false);
const deletingId = ref(null);

const filters = ref({
  direction: '',
  bank_account_id: '',
  category_id: '',
  payment_method: '',
  uncategorized: false,
  q: '',
  from: '',
  to: '',
});

// Opções do filtro de forma de pagamento — reusa `PAYMENT_KIND_OPTIONS` do
// `PaymentMethodBadge` (single source of truth do design system, decisão
// 2026-05-28). Adiciona "Todas as formas" como entry vazio. Cada option ganha
// renderização premium via slot `#option`/`#selected` com <PaymentMethodBadge>.
const PAYMENT_METHOD_OPTIONS = [
  { value: '', label: 'Todas as formas' },
  ...PAYMENT_KIND_OPTIONS,
];
const currentPage = ref(1);
const perPage = ref(25);

// Modal de lançamento avulso reutilizado das telas A Receber / A Pagar.
const showEntryModal = ref(false);
const entryDirection = ref(null);

// Modal de transferência interna entre contas (canon §4.2).
const showTransferModal = ref(false);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const DIRECTION_CHIPS = [
  { key: 'all', label: 'Todos',    tone: 'blue',    direction: '', icon: 'i-lucide-list' },
  { key: 'in',  label: 'Entradas', tone: 'emerald', direction: 'in', icon: 'i-lucide-arrow-down-to-line' },
  { key: 'out', label: 'Saídas',   tone: 'ruby',    direction: 'out', icon: 'i-lucide-arrow-up-from-line' },
];

const activeChip = computed(
  () => DIRECTION_CHIPS.find(c => c.direction === filters.value.direction) || DIRECTION_CHIPS[0],
);

// Cor por tipo de categoria — espelha Badge global.
const KIND_VISUAL = {
  receita:        { color: '#10b981', hint: 'Receita' },
  despesa_fixa:   { color: '#dc2626', hint: 'Despesa fixa' },
  custo_variavel: { color: '#f59e0b', hint: 'Custo variável' },
  outra_despesa:  { color: '#64748b', hint: 'Outra despesa' },
};

const bankAccountOptions = computed(() => {
  const opts = [{ value: '', label: 'Todas as contas' }];
  bankAccounts.value.forEach(b =>
    opts.push({ value: b.id, label: `${b.name} · ${bankKindLabel(b.kind)}` }),
  );
  return opts;
});

const categoryOptions = computed(() => {
  const opts = [{ value: '', label: 'Todas as categorias' }];
  categories.value.forEach(c => {
    const v = KIND_VISUAL[c.kind] || { color: '#94a3b8', hint: c.kind };
    opts.push({ value: c.id, label: c.name, color: v.color, hint: v.hint });
  });
  return opts;
});

// Saldo total: soma dos saldos das contas filtradas (ou todas).
// Mantém o saldo "real-time" mesmo quando o usuário filtra a tabela por
// período — saldo é cumulativo, não respeita date range.
const totalBalanceCents = computed(() => {
  const list = filters.value.bank_account_id
    ? bankAccounts.value.filter(b => b.id === filters.value.bank_account_id)
    : bankAccounts.value;
  return list.reduce((acc, b) => acc + (b.current_balance_cents || 0), 0);
});

const periodInCents = computed(() => meta.value.total_in_cents || 0);
const periodOutCents = computed(() => meta.value.total_out_cents || 0);
const periodResultCents = computed(() => periodInCents.value - periodOutCents.value);

const hasFilter = computed(() =>
  filters.value.q
  || filters.value.from
  || filters.value.to
  || filters.value.direction
  || filters.value.bank_account_id
  || filters.value.category_id
  || filters.value.payment_method
  || filters.value.uncategorized,
);

// Painel lateral de filtros avançados (canon UX: chips + busca ficam
// inline; conta/categoria/datas/"sem categoria" entram no painel pra
// limpar ruído visual). Mesmo padrão do toggle de detalhes do contato.
const showFilterPanel = ref(false);

// Contador de filtros avançados ATIVOS — exibido como badge no botão.
// Direction (chips) e q (search) NÃO contam aqui porque ficam fora do painel.
const advancedFilterCount = computed(() => {
  let n = 0;
  if (filters.value.bank_account_id) n += 1;
  if (filters.value.category_id) n += 1;
  if (filters.value.payment_method) n += 1;
  if (filters.value.from) n += 1;
  if (filters.value.to) n += 1;
  if (filters.value.uncategorized) n += 1;
  return n;
});

function closeFilterPanel() {
  showFilterPanel.value = false;
}

async function load() {
  loading.value = true;
  try {
    const params = {
      page: currentPage.value,
      per_page: perPage.value,
    };
    if (filters.value.direction) params.direction = filters.value.direction;
    if (filters.value.bank_account_id) params.bank_account_id = filters.value.bank_account_id;
    if (filters.value.category_id) params.category_id = filters.value.category_id;
    if (filters.value.payment_method) params.payment_method = filters.value.payment_method;
    if (filters.value.uncategorized) params.uncategorized = 'true';
    if (filters.value.q) params.q = filters.value.q;
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;

    const { data } = await FinancialV2.entries.index(params);
    entries.value = data?.data || [];
    meta.value = data?.meta || {};
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[CashFlowV2] load error', err);
    notifyError('Falha ao carregar lançamentos do Fluxo de Caixa.');
  } finally {
    loading.value = false;
  }
}

async function loadBankAccounts() {
  try {
    const { data } = await FinancialV2.bankAccounts.index({ active: 'true' });
    bankAccounts.value = data?.data || [];
  } catch {
    bankAccounts.value = [];
  }
}

async function loadCategories() {
  try {
    const { data } = await FinancialV2.categories.index({ active: 'true' });
    categories.value = data?.data || [];
  } catch {
    categories.value = [];
  }
}

watch(filters, () => {
  currentPage.value = 1;
  load();
}, { deep: true });

watch([currentPage, perPage], load);

onMounted(() => {
  load();
  loadBankAccounts();
  loadCategories();
});

function openNewIn() {
  entryDirection.value = 'in';
  showEntryModal.value = true;
}

function openNewOut() {
  entryDirection.value = 'out';
  showEntryModal.value = true;
}

function onEntryConfirmed() {
  showEntryModal.value = false;
  load();
  loadBankAccounts(); // saldo mudou
}

// Modal de confirmação de exclusão. Substitui o `window.confirm()` nativo
// (regra do projeto: usar ConfirmDangerModal pra qualquer delete).
const showDeleteModal = ref(false);
const entryToDelete = ref(null);

function deleteEntry(entry) {
  if (!entry.editable) return;
  entryToDelete.value = entry;
  showDeleteModal.value = true;
}

async function confirmDeleteEntry() {
  const entry = entryToDelete.value;
  if (!entry) return;
  deletingId.value = entry.id;
  try {
    await FinancialV2.entries.destroy(entry.id);
    notifySuccess('Lançamento excluído.');
    showDeleteModal.value = false;
    entryToDelete.value = null;
    await load();
    await loadBankAccounts();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao excluir lançamento.');
  } finally {
    deletingId.value = null;
  }
}

function clearFilters() {
  filters.value = {
    direction: '',
    bank_account_id: '',
    category_id: '',
    payment_method: '',
    uncategorized: false,
    q: '',
    from: '',
    to: '',
  };
}

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

// Tom do badge por kind — ajuda a varrer a lista e identificar o tipo
// (receita = verde, despesa = vermelho, estorno = roxo, manual = azul, etc.).
const KIND_BADGE_TONE = {
  receita:         'emerald',
  despesa:         'ruby',
  transferencia:   'blue',
  sangria:         'amber',
  suprimento:      'amber',
  quebra_caixa:    'amber',
  estorno_receita: 'violet',
  estorno_despesa: 'violet',
  juros:           'amber',
  multa:           'ruby',
  desconto:        'slate',
  manual_entry:    'blue',
};

function kindBadge(entry) {
  return {
    label: entry.kind_label || entry.kind,
    color: KIND_BADGE_TONE[entry.kind] || 'slate',
  };
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Fluxo de Caixa</h1>
        <p class="finv2-page__subtitle">
          Todas as movimentações reais de caixa — recibos, despesas, estornos,
          sangrias e lançamentos avulsos. Saldo atualizado em tempo real.
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <BeclinicButton
          variant="faded"
          color="blue"
          icon="i-lucide-arrow-down-to-line"
          label="Nova entrada"
          size="sm"
          @click="openNewIn"
        />
        <BeclinicButton
          variant="faded"
          color="ruby"
          icon="i-lucide-arrow-up-from-line"
          label="Nova saída"
          size="sm"
          @click="openNewOut"
        />
        <BeclinicButton
          variant="faded"
          color="slate"
          icon="i-lucide-arrow-left-right"
          label="Transferência"
          size="sm"
          @click="showTransferModal = true"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- KPIs (carrossel horizontal no mobile via `.finv2-kpis` global) -->
      <div class="finv2-kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-wallet w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">
              {{ filters.bank_account_id ? 'Saldo da conta' : 'Saldo total' }}
            </span>
            <strong
              class="finv2-kpi__value"
              :class="totalBalanceCents >= 0 ? 'finv2-kpi__value--positive' : 'finv2-kpi__value--danger'"
            >
              {{ centsToBRL(totalBalanceCents) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--positive">
            <i class="i-lucide-trending-up w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Entradas no período</span>
            <strong class="finv2-kpi__value finv2-kpi__value--positive">
              {{ centsToBRL(periodInCents) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger">
            <i class="i-lucide-trending-down w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Saídas no período</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ centsToBRL(periodOutCents) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-scale w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Resultado líquido</span>
            <strong
              class="finv2-kpi__value"
              :class="periodResultCents >= 0 ? 'finv2-kpi__value--positive' : 'finv2-kpi__value--danger'"
            >
              {{ periodResultCents >= 0 ? '+' : '−' }} {{ centsToBRL(Math.abs(periodResultCents)) }}
            </strong>
          </div>
        </div>
      </div>

      <!-- Linha de filtros rápidos: chips + busca + toggle do painel. -->
      <div class="cf-v2__quick-filters">
        <div class="finv2-chips" role="tablist">
          <button
            v-for="chip in DIRECTION_CHIPS"
            :key="chip.key"
            type="button"
            class="finv2-chip"
            :class="[`finv2-chip--tone-${chip.tone}`, { 'finv2-chip--active': activeChip.key === chip.key }]"
            @click="filters.direction = chip.direction"
          >
            <i :class="chip.icon" class="w-3.5 h-3.5" />
            <span>{{ chip.label }}</span>
          </button>
        </div>
        <FinSearchInput
          v-model="filters.q"
          placeholder="Buscar descrição…"
          class="cf-v2__search"
        />
        <button
          type="button"
          class="cf-v2__filter-toggle"
          :class="{ 'cf-v2__filter-toggle--active': advancedFilterCount > 0 }"
          aria-label="Abrir filtros"
          @click="showFilterPanel = true"
        >
          <i class="i-lucide-sliders-horizontal w-3.5 h-3.5" />
          <span class="cf-v2__filter-toggle-label">Filtros</span>
          <span v-if="advancedFilterCount > 0" class="cf-v2__filter-count">
            {{ advancedFilterCount }}
          </span>
        </button>
      </div>

      <!-- Tabela desktop -->
      <div class="finv2-table-wrap finv2-hide-mobile">
        <table class="finv2-table">
          <thead>
            <tr>
              <th>Data</th>
              <th>Descrição</th>
              <th>Tipo</th>
              <th>Categoria</th>
              <th>Conta</th>
              <th>Paciente</th>
              <th class="finv2-table__th-num">Valor</th>
              <th class="cf-v2__th-actions">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="8">
                <div class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
              </td>
            </tr>
            <tr v-else-if="entries.length === 0">
              <td colspan="8">
                <div class="finv2-state">
                  <div class="finv2-state__icon-wrap"><i class="i-lucide-inbox w-7 h-7" /></div>
                  <p class="finv2-state__title">Nenhum lançamento encontrado</p>
                  <p class="finv2-state__hint">
                    Ajuste os filtros ou registre uma nova entrada/saída no header.
                  </p>
                </div>
              </td>
            </tr>
            <tr v-for="e in entries" v-else :key="e.id">
              <td class="finv2-table__td-date">{{ formatDateBR(e.cash_date) }}</td>
              <td>
                <div class="cf-v2__desc">
                  <strong>{{ e.description || '—' }}</strong>
                  <span v-if="e.source_label" class="cf-v2__source-hint">
                    via {{ e.source_label }}
                  </span>
                </div>
              </td>
              <td>
                <Badge
                  :label="kindBadge(e).label"
                  :color="kindBadge(e).color"
                  size="xs"
                />
              </td>
              <td>
                <Badge
                  v-if="e.category"
                  :label="e.category.name"
                  :color="e.category.kind === 'receita' ? 'emerald' : 'slate'"
                  size="xs"
                  variant="faded"
                />
                <span v-else class="cf-v2__no-category">
                  <i class="i-lucide-alert-circle w-3 h-3" /> Sem categoria
                </span>
              </td>
              <td class="finv2-table__td-muted">{{ e.bank_account?.name || '—' }}</td>
              <td>
                <ProfessionalChip
                  v-if="e.patient?.name"
                  :name="e.patient.name"
                  :avatar-url="e.patient.avatar_url || ''"
                  size="sm"
                />
                <span v-else class="finv2-table__td-muted">—</span>
              </td>
              <td
                class="finv2-table__td-num finv2-table__td-num--strong"
                :class="e.direction === 'in' ? 'cf-v2__amount--in' : 'cf-v2__amount--out'"
              >
                <span class="cf-v2__amount-wrap">
                  {{ e.direction === 'in' ? '+' : '−' }} {{ centsToBRL(e.amount_cents) }}
                  <!-- Ícone info — aparece quando o source teve juros/multa/
                       desconto/crédito aplicado. Tooltip mostra o breakdown
                       completo (valor original → modificadores → líquido). -->
                  <Tooltip
                    v-if="entryHasBreakdown(e)"
                    :label="entryBreakdownTooltipLabel(e)"
                    position="top"
                    multiline
                  >
                    <i class="i-lucide-info cf-v2__breakdown-icon" />
                  </Tooltip>
                </span>
              </td>
              <td class="cf-v2__td-actions">
                <Tooltip v-if="e.editable" label="Excluir lançamento">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    :is-loading="deletingId === e.id"
                    :disabled="deletingId === e.id"
                    @click="deleteEntry(e)"
                  />
                </Tooltip>
                <Tooltip v-else :label="'Lançamento automático — gerencie pela origem (' + (e.source_label || 'origem') + ')'">
                  <i class="i-lucide-lock w-3.5 h-3.5 cf-v2__locked-icon" />
                </Tooltip>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Cards mobile -->
      <div class="finv2-show-mobile">
        <div class="cf-v2__cards">
          <div v-if="loading" class="finv2-state">
            <div class="finv2-spinner" /><span>Carregando…</span>
          </div>
          <div v-else-if="entries.length === 0" class="finv2-state">
            <div class="finv2-state__icon-wrap"><i class="i-lucide-inbox w-7 h-7" /></div>
            <p class="finv2-state__title">Nenhum lançamento encontrado</p>
            <p class="finv2-state__hint">Ajuste os filtros ou registre uma nova entrada/saída.</p>
          </div>
          <article
            v-for="e in entries"
            v-else
            :key="e.id"
            class="cf-v2__card"
            :class="e.direction === 'in' ? 'cf-v2__card--in' : 'cf-v2__card--out'"
          >
          <header class="cf-v2__card-header">
            <div class="cf-v2__card-meta">
              <Badge
                :label="kindBadge(e).label"
                :color="kindBadge(e).color"
                size="xs"
              />
              <span class="cf-v2__card-date">{{ formatDateBR(e.cash_date) }}</span>
            </div>
            <strong
              class="cf-v2__card-amount"
              :class="e.direction === 'in' ? 'cf-v2__amount--in' : 'cf-v2__amount--out'"
            >
              {{ e.direction === 'in' ? '+' : '−' }} {{ centsToBRL(e.amount_cents) }}
              <Tooltip
                v-if="entryHasBreakdown(e)"
                :label="entryBreakdownTooltipLabel(e)"
                position="left"
                multiline
              >
                <i class="i-lucide-info cf-v2__breakdown-icon" />
              </Tooltip>
            </strong>
          </header>
          <p class="cf-v2__card-desc">
            <strong>{{ e.description || '—' }}</strong>
            <span v-if="e.source_label" class="cf-v2__source-hint">via {{ e.source_label }}</span>
          </p>
          <div class="cf-v2__card-footer">
            <span class="cf-v2__card-account">{{ e.bank_account?.name || '—' }}</span>
            <Badge
              v-if="e.category"
              :label="e.category.name"
              :color="e.category.kind === 'receita' ? 'emerald' : 'slate'"
              size="xs"
              variant="faded"
            />
            <span v-else class="cf-v2__no-category">
              <i class="i-lucide-alert-circle w-3 h-3" /> Sem categoria
            </span>
            <ProfessionalChip
              v-if="e.patient?.name"
              :name="e.patient.name"
              :avatar-url="e.patient.avatar_url || ''"
              size="sm"
            />
          </div>
          <footer v-if="e.editable" class="cf-v2__card-actions">
            <BeclinicButton
              size="xs"
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              label="Excluir"
              :is-loading="deletingId === e.id"
              :disabled="deletingId === e.id"
              @click="deleteEntry(e)"
            />
          </footer>
          </article>
        </div>
      </div>

      <!-- Paginação -->
      <Pagination
        v-model:current-page="currentPage"
        v-model:per-page="perPage"
        :total-count="meta.total || 0"
        item-label="lançamentos"
      />
    </div>

    <!-- Modal lançamento avulso -->
    <ManualEntryModalV2
      :show="showEntryModal"
      :direction="entryDirection"
      @close="showEntryModal = false"
      @confirm="onEntryConfirmed"
    />

    <!-- Modal transferência interna entre contas -->
    <TransferModalV2
      :show="showTransferModal"
      @close="showTransferModal = false"
      @confirm="load"
    />

    <!-- Modal de confirmação de exclusão -->
    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      title="Excluir lançamento?"
      :message="entryToDelete
        ? `O lançamento '${entryToDelete.description}' será removido e o saldo da conta reajustado. Esta ação não pode ser desfeita.`
        : ''"
      confirm-label="Excluir lançamento"
      :loading="deletingId === entryToDelete?.id"
      @confirm="confirmDeleteEntry"
    />

    <!-- Painel lateral de filtros avançados — mesmo padrão do toggle de
         detalhes do contato. Teleport pra `body` evita conflitos de
         z-index/overflow do layout do app. -->
    <Teleport to="body">
      <Transition
        enter-active-class="cf-v2__panel-enter-active"
        leave-active-class="cf-v2__panel-leave-active"
        enter-from-class="cf-v2__panel-enter-from"
        leave-to-class="cf-v2__panel-leave-to"
      >
        <div
          v-if="showFilterPanel"
          class="cf-v2__panel-backdrop"
          @click.self="closeFilterPanel"
        >
          <aside
            v-on-click-outside="[
              closeFilterPanel,
              {
                ignore: [
                  // FormSelect e DatePickerBR usam Teleport pra body — sem
                  // ignorar, clicar numa opção do dropdown fecha o painel.
                  '.ms-dropdown',
                  '.mx-datepicker-popup',
                  '.mx-datepicker-main',
                ],
              },
            ]"
            class="cf-v2__panel"
            role="dialog"
            aria-label="Filtros avançados"
          >
            <header class="cf-v2__panel-header">
              <div>
                <h2 class="cf-v2__panel-title">
                  <i class="i-lucide-sliders-horizontal w-4 h-4" /> Filtros
                </h2>
                <p v-if="advancedFilterCount > 0" class="cf-v2__panel-hint">
                  {{ advancedFilterCount }} filtro(s) ativo(s)
                </p>
              </div>
              <BeclinicButton
                size="sm"
                variant="ghost"
                color="slate"
                icon="i-lucide-x"
                @click="closeFilterPanel"
              />
            </header>
            <div class="cf-v2__panel-body">
              <label class="cf-v2__panel-field">
                <span class="cf-v2__panel-label">Conta</span>
                <FormSelect
                  v-model="filters.bank_account_id"
                  :options="bankAccountOptions"
                  placeholder="Todas as contas"
                  searchable
                  auto-searchable
                />
              </label>
              <label class="cf-v2__panel-field">
                <span class="cf-v2__panel-label">Categoria DRE</span>
                <FormSelect
                  v-model="filters.category_id"
                  :options="categoryOptions"
                  placeholder="Todas as categorias"
                  searchable
                  auto-searchable
                  clearable
                />
              </label>
              <label class="cf-v2__panel-field">
                <span class="cf-v2__panel-label">Forma de pagamento</span>
                <FormSelect
                  v-model="filters.payment_method"
                  :options="PAYMENT_METHOD_OPTIONS"
                  placeholder="Todas as formas"
                  clearable
                >
                  <!-- Slot premium: badge colorido em vez de texto puro. Para
                       a opção "Todas as formas" (value=''), cai no fallback de
                       label simples. -->
                  <template #selected="{ option }">
                    <PaymentMethodBadge
                      v-if="option?.value"
                      :kind="option.value"
                      size="md"
                      hide-installments
                    />
                    <span v-else class="cf-v2__panel-select-placeholder">
                      <i class="i-lucide-list w-3.5 h-3.5" />
                      {{ option?.label || 'Todas as formas' }}
                    </span>
                  </template>
                  <template #option="{ option }">
                    <PaymentMethodBadge
                      v-if="option.value"
                      :kind="option.value"
                      size="md"
                      hide-installments
                    />
                    <span v-else class="cf-v2__panel-select-placeholder">
                      <i class="i-lucide-list w-3.5 h-3.5" />
                      {{ option.label }}
                    </span>
                  </template>
                </FormSelect>
              </label>
              <div class="cf-v2__panel-row">
                <label class="cf-v2__panel-field">
                  <span class="cf-v2__panel-label">Data inicial</span>
                  <DatePickerBR v-model="filters.from" placeholder="dd/mm/aaaa" />
                </label>
                <label class="cf-v2__panel-field">
                  <span class="cf-v2__panel-label">Data final</span>
                  <DatePickerBR v-model="filters.to" placeholder="dd/mm/aaaa" :min="filters.from || null" />
                </label>
              </div>
              <div class="cf-v2__panel-toggle">
                <Checkbox v-model="filters.uncategorized" label="Só sem categoria" />
              </div>
            </div>
            <footer class="cf-v2__panel-footer">
              <BeclinicButton
                v-if="hasFilter"
                variant="ghost"
                color="slate"
                icon="i-lucide-x"
                label="Limpar filtros"
                size="sm"
                @click="clearFilters"
              />
              <BeclinicButton
                variant="solid"
                color="blue"
                icon="i-lucide-check"
                label="Aplicar e fechar"
                size="sm"
                @click="closeFilterPanel"
              />
            </footer>
          </aside>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped lang="scss">
/* Linha de filtros rápidos — chips à esquerda, busca crescível,
   botão "Filtros" à direita pra abrir o painel. */
.cf-v2__quick-filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.cf-v2__search {
  flex: 1 1 240px;
  min-width: 0;
}
@media (max-width: 640px) {
  /* Mobile: chips ocupam linha inteira; search + botão Filtros dividem
     a linha de baixo (search cresce, botão fica icon-only). */
  .cf-v2__quick-filters > .finv2-chips { width: 100%; }
  .cf-v2__search { flex: 1 1 0; min-width: 0; }
}

.cf-v2__filter-toggle {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 14px;
  border-radius: 999px;
  border: 1px solid rgb(var(--slate-5));
  background: rgb(var(--slate-1));
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-11));
  cursor: pointer;
  flex-shrink: 0;
  transition: background 0.12s ease, border-color 0.12s ease, color 0.12s ease;
  &:hover {
    background: rgb(var(--slate-2));
    color: rgb(var(--slate-12));
  }
}
/* Mobile: vira ícone só (label some). Mantém badge contador visível
   pra usuário saber se há filtro ativo sem abrir o painel. */
@media (max-width: 640px) {
  .cf-v2__filter-toggle { padding: 8px 10px; }
  .cf-v2__filter-toggle-label { display: none; }
}
.cf-v2__filter-toggle--active {
  background: rgba(37, 99, 235, 0.10);
  border-color: rgba(37, 99, 235, 0.32);
  color: rgb(var(--blue-11));
  &:hover { background: rgba(37, 99, 235, 0.18); }
}
.cf-v2__filter-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 18px;
  height: 18px;
  padding: 0 5px;
  border-radius: 999px;
  background: rgb(var(--blue-9));
  color: #fff;
  font-size: 11px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}

/* ── Painel lateral de filtros (slide-in da direita) ─────────── */
.cf-v2__panel-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(15, 23, 42, 0.45);
  backdrop-filter: blur(2px);
  display: flex;
  justify-content: flex-end;
}
.cf-v2__panel {
  width: min(420px, 100%);
  height: 100%;
  background: rgb(var(--slate-1));
  border-left: 1px solid rgb(var(--slate-4));
  display: flex;
  flex-direction: column;
  box-shadow: -10px 0 25px -8px rgba(0, 0, 0, 0.15);
}
.cf-v2__panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.cf-v2__panel-title {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex;
  align-items: center;
  gap: 6px;
}
.cf-v2__panel-hint {
  margin: 4px 0 0;
  font-size: 12px;
  color: rgb(var(--blue-11));
  font-weight: 500;
}
.cf-v2__panel-body {
  flex: 1;
  overflow-y: auto;
  padding: 18px 20px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.cf-v2__panel-field {
  display: flex;
  flex-direction: column;
  gap: 5px;
  min-width: 0;
}
.cf-v2__panel-label {
  font-size: 12px;
  font-weight: 500;
  color: rgb(var(--slate-11));
}
/* "Todas as formas" — placeholder do select de forma de pagamento quando
   nenhum método específico está selecionado. Neutralidade visual pra contrastar
   com os badges coloridos das opções reais. */
.cf-v2__panel-select-placeholder {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  color: rgb(var(--slate-11));
}
.cf-v2__panel-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
@media (max-width: 480px) {
  .cf-v2__panel-row { grid-template-columns: 1fr; }
}
.cf-v2__panel-toggle {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  padding: 10px 12px;
  border-radius: 10px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  font-size: 13px;
  color: rgb(var(--slate-12));
  cursor: pointer;
  user-select: none;
  input { cursor: pointer; }
}
.cf-v2__panel-footer {
  display: flex;
  justify-content: space-between;
  gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
}

/* Transitions Vue (slide-in da direita + fade no backdrop). */
.cf-v2__panel-enter-active,
.cf-v2__panel-leave-active {
  transition: opacity 0.2s ease;
  .cf-v2__panel { transition: transform 0.25s ease; }
}
.cf-v2__panel-enter-from,
.cf-v2__panel-leave-to {
  opacity: 0;
  .cf-v2__panel { transform: translateX(100%); }
}

/* Tabela */
.cf-v2__th-actions { width: 80px; text-align: right; }
.cf-v2__td-actions {
  text-align: right;
  white-space: nowrap;
}
.cf-v2__locked-icon {
  color: rgb(var(--slate-9));
  display: inline-block;
  vertical-align: middle;
  margin-right: 6px;
}

.cf-v2__desc {
  display: flex;
  flex-direction: column;
  gap: 2px;
  strong { color: rgb(var(--slate-12)); }
}
.cf-v2__source-hint {
  font-size: 11.5px;
  color: rgb(var(--slate-9));
  font-weight: 400;
}

.cf-v2__no-category {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: rgb(var(--amber-11));
  font-weight: 500;
}

.cf-v2__amount--in  { color: #047857; }
.cf-v2__amount--out { color: #b91c1c; }
:root.dark .cf-v2__amount--in  { color: #6ee7b7; }
:root.dark .cf-v2__amount--out { color: #fca5a5; }

/* Wrap pro valor + ícone info ficarem alinhados na mesma linha (cell alinhada à direita) */
.cf-v2__amount-wrap {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  justify-content: flex-end;
}
.cf-v2__breakdown-icon {
  display: inline-block;
  width: 14px; height: 14px;
  color: rgb(var(--blue-10));
  opacity: 0.7;
  cursor: help;
  transition: opacity 0.12s ease;
  vertical-align: middle;

  &:hover { opacity: 1; }
}

/* Cards mobile */
.cf-v2__cards { display: flex; flex-direction: column; gap: 10px; }
.cf-v2__card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  border-left-width: 3px;
}
.cf-v2__card--in  { border-left-color: #10b981; }
.cf-v2__card--out { border-left-color: #dc2626; }

.cf-v2__card-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 8px;
}
.cf-v2__card-meta {
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.cf-v2__card-date {
  font-size: 12px;
  color: rgb(var(--slate-9));
}
.cf-v2__card-amount {
  font-size: 16px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.cf-v2__card-desc {
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 13.5px;
  color: rgb(var(--slate-12));
}

.cf-v2__card-footer {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: rgb(var(--slate-11));
}
.cf-v2__card-account {
  color: rgb(var(--slate-11));
  font-weight: 500;
}

.cf-v2__card-actions {
  display: flex;
  justify-content: flex-end;
  margin-top: 4px;
  padding-top: 8px;
  border-top: 1px dashed rgb(var(--slate-4));
}
</style>
