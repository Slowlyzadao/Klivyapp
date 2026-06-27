<script setup>
/**
 * A Pagar — v2 (canon Financial::*).
 *
 * Lista despesas (Financial::Expense) com:
 *   • Chips de status com paleta Badge (faded/active solid).
 *   • Filtro default 'open' (pendente + vencido).
 *   • Ações inline: Pagar, Estornar.
 *   • Paginação 10/página (server-side).
 *   • Mobile: tabela vira cards stacked.
 *   • Componentes globais: Badge, FormSelect, DatePickerBR, Checkbox, Pagination.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import PayExpenseModalV2 from '../components/PayExpenseModalV2.vue';
import ManualEntryModalV2 from '../components/ManualEntryModalV2.vue';
import ReverseExpenseModalV2 from '../components/ReverseExpenseModalV2.vue';
import FinSearchInput from '../components/FinSearchInput.vue';
// Carrega o CSS global pra ativar `.finv2-page` (scroll + position absolute).
import '@plugins/financial/frontend/styles/financial.scss';

// Removido chip 'Pendente' (2026-05-23) — redundante com 'Em aberto' (que já
// inclui pendente+vencido). Operador raramente quer ver pendentes ignorando
// vencidos (vencidos são MAIS urgentes). 'Vencido' separado mantém o sinal
// de urgência. Quem precisar do filtro fino "só pendente" → usa 'Todos' +
// ordenação ou filtros de data.
const STATUS_CHIPS = [
  { key: 'open',      label: 'Em aberto', tone: 'blue',    statuses: ['pendente', 'vencido'], icon: 'i-lucide-clock' },
  { key: 'vencido',   label: 'Vencido',   tone: 'ruby',    statuses: ['vencido'],             icon: 'i-lucide-alert-circle' },
  { key: 'pago',      label: 'Pago',      tone: 'emerald', statuses: ['pago'],                icon: 'i-lucide-check-circle-2' },
  { key: 'estornado', label: 'Estornado', tone: 'violet',  statuses: ['estornado'],           icon: 'i-lucide-undo' },
  { key: 'all',       label: 'Todos',     tone: 'blue',    statuses: [],                      icon: 'i-lucide-list' },
];

const STATUS_BADGE = {
  pendente:  { color: 'slate',   icon: 'i-lucide-clock',          label: 'Pendente' },
  pago:      { color: 'emerald', icon: 'i-lucide-check-circle-2', label: 'Pago' },
  vencido:   { color: 'ruby',    icon: 'i-lucide-alert-circle',   label: 'Vencido' },
  estornado: { color: 'violet',  icon: 'i-lucide-undo',           label: 'Estornado' },
  cancelado: { color: 'slate',   icon: 'i-lucide-x-circle',       label: 'Cancelado' },
};

const expenses = ref([]);
const meta = ref({});
const filters = ref({
  status_chip: 'open',
  q: '',
  from: '',
  to: '',
  overdue_only: false,
});
const currentPage = ref(1);
const perPage = ref(10);
const loading = ref(false);
const bankAccounts = ref([]);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const activeChip = computed(
  () => STATUS_CHIPS.find(c => c.key === filters.value.status_chip) || STATUS_CHIPS[0]
);

async function load() {
  loading.value = true;
  try {
    const params = { page: currentPage.value, per_page: perPage.value };
    if (activeChip.value.statuses.length > 0) params.status = activeChip.value.statuses;
    if (filters.value.q) params.q = filters.value.q;
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;
    if (filters.value.overdue_only) params.overdue_only = 'true';

    const { data } = await FinancialV2.expenses.index(params);
    expenses.value = data?.data || [];
    meta.value = data?.meta || {};
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[PayablesV2] load error', err);
    notifyError('Falha ao carregar despesas.');
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

watch(filters, () => {
  currentPage.value = 1;
  load();
}, { deep: true });

watch([currentPage, perPage], load);

onMounted(() => { load(); loadBankAccounts(); });

function statusBadge(status) {
  return STATUS_BADGE[status] || STATUS_BADGE.pendente;
}

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

// Modal de pagamento (canon F-21) — substitui o `confirm()` nativo.
const showPayModal = ref(false);
const expenseBeingPaid = ref(null);

function payExpense(expense) {
  expenseBeingPaid.value = expense;
  showPayModal.value = true;
}

function onPayConfirmed() {
  showPayModal.value = false;
  expenseBeingPaid.value = null;
  load();
}

// Modal de lançamento avulso de saída (canon F-25) — botão "Nova despesa avulsa"
// no header pra entradas que não cabem no fluxo de despesa recorrente.
const showManualEntryModal = ref(false);

function openManualEntry() {
  showManualEntryModal.value = true;
}

function onManualEntryConfirmed() {
  showManualEntryModal.value = false;
  load();
}

// Estorno via modal dedicado (substitui prompt() nativo).
const reverseModalShow = ref(false);
const expenseToReverse = ref(null);

function reverseExpense(expense) {
  expenseToReverse.value = expense;
  reverseModalShow.value = true;
}

function closeReverseModal() {
  reverseModalShow.value = false;
  expenseToReverse.value = null;
}

async function onReverseConfirm({ reason }) {
  const exp = expenseToReverse.value;
  closeReverseModal();
  if (!exp) return;
  try {
    await FinancialV2.expenses.reverse(exp.id, { reason });
    notifySuccess('Despesa estornada.');
    load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao estornar despesa.');
  }
}

function clearDates() {
  filters.value.from = '';
  filters.value.to = '';
}
const hasDateFilter = computed(() => filters.value.from || filters.value.to);

function isPayable(exp) {
  return ['pendente', 'vencido'].includes(exp.status);
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">A Pagar</h1>
        <p class="finv2-page__subtitle">
          Despesas planejadas e recorrentes — pague, estorne ou reagende.
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <BeclinicButton
          variant="faded"
          color="ruby"
          icon="i-lucide-arrow-up-from-line"
          label="Nova saída avulsa"
          size="sm"
          @click="openManualEntry"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- KPIs -->
      <div class="finv2-kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-receipt w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total a pagar</span>
            <strong class="finv2-kpi__value">{{ centsToBRL(meta.total_to_pay_cents || 0) }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-repeat w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Recorrentes</span>
            <strong class="finv2-kpi__value">{{ centsToBRL(meta.total_recurring_cents || 0) }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger"><i class="i-lucide-calendar-clock w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Próximos 3 dias</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ centsToBRL(meta.total_due_soon_cents || 0) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral"><i class="i-lucide-list w-4 h-4" /></div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Transações</span>
            <strong class="finv2-kpi__value">{{ meta.total_count || 0 }}</strong>
          </div>
        </div>
      </div>

      <!-- Filtros: chips + busca + datas -->
      <div class="pyv2__filters">
        <div class="finv2-chips" role="tablist" aria-label="Filtrar por status">
          <button
            v-for="chip in STATUS_CHIPS"
            :key="chip.key"
            type="button"
            role="tab"
            class="finv2-chip"
            :class="[`finv2-chip--tone-${chip.tone}`, { 'finv2-chip--active': filters.status_chip === chip.key }]"
            @click="filters.status_chip = chip.key"
          >
            <i :class="chip.icon" class="w-3.5 h-3.5" />
            <span>{{ chip.label }}</span>
          </button>
        </div>

        <div class="pyv2__inputs">
          <FinSearchInput
            v-model="filters.q"
            placeholder="Buscar descrição…"
            class="pyv2__input--grow"
          />
          <div class="finv2-input-wrap finv2-input-wrap--date">
            <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
          </div>
          <div class="finv2-input-wrap finv2-input-wrap--date">
            <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
          </div>
          <Checkbox v-model="filters.overdue_only" label="Só vencidos" />
          <button v-if="hasDateFilter" type="button" class="pyv2__clear" @click="clearDates">
            <i class="i-lucide-x w-3.5 h-3.5" /> Limpar
          </button>
        </div>
      </div>

      <!-- Desktop: tabela -->
      <div class="finv2-table-wrap finv2-hide-mobile">
        <table class="finv2-table">
          <thead>
            <tr>
              <th>Descrição</th>
              <th>Categoria</th>
              <th>Vencimento</th>
              <th class="finv2-table__th-num">Valor</th>
              <th>Status</th>
              <th class="finv2-table__th-actions">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="6">
                <div class="finv2-state">
                  <div class="finv2-spinner" />
                  <span>Carregando despesas…</span>
                </div>
              </td>
            </tr>
            <tr v-else-if="expenses.length === 0">
              <td colspan="6">
                <div class="finv2-state">
                  <div class="finv2-state__icon-wrap"><i class="i-lucide-inbox w-7 h-7" /></div>
                  <p class="finv2-state__title">Nenhuma despesa encontrada</p>
                  <p class="finv2-state__hint">Ajuste os filtros ou cadastre uma despesa nova.</p>
                </div>
              </td>
            </tr>
            <tr v-for="exp in expenses" v-else :key="exp.id">
              <td>
                <div class="pyv2__desc-cell">
                  <strong>{{ exp.description }}</strong>
                  <Tooltip
                    v-if="exp.auto_pay_error"
                    :label="`Auto-pagamento falhou em ${formatDateBR(exp.auto_pay_attempted_at)}: ${exp.auto_pay_error}`"
                    position="top"
                    multiline
                  >
                    <span class="pyv2__autopay-warn">
                      <i class="i-lucide-alert-triangle w-3 h-3" />
                      Auto-pay falhou
                    </span>
                  </Tooltip>
                </div>
              </td>
              <td class="finv2-table__td-muted">{{ exp.category_name || 'Sem categoria' }}</td>
              <td class="finv2-table__td-date">{{ formatDateBR(exp.due_date) }}</td>
              <td class="finv2-table__td-num finv2-table__td-num--strong">{{ centsToBRL(exp.amount_cents) }}</td>
              <td>
                <Badge :label="statusBadge(exp.status).label" :color="statusBadge(exp.status).color"
                       :icon="statusBadge(exp.status).icon" size="xs" />
              </td>
              <td class="finv2-table__td-actions">
                <Tooltip v-if="isPayable(exp)" label="Pagar despesa">
                  <BeclinicButton size="xs" variant="faded" color="blue" icon="i-lucide-check" @click="payExpense(exp)" />
                </Tooltip>
                <Tooltip v-if="exp.status === 'pago'" label="Estornar">
                  <BeclinicButton size="xs" variant="ghost" color="ruby" icon="i-lucide-undo" @click="reverseExpense(exp)" />
                </Tooltip>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Mobile: cards -->
      <div class="finv2-cards finv2-show-mobile">
        <div v-if="loading" class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
        <div v-else-if="expenses.length === 0" class="finv2-state">
          <div class="finv2-state__icon-wrap"><i class="i-lucide-inbox w-7 h-7" /></div>
          <p class="finv2-state__title">Nenhuma despesa</p>
        </div>
        <article v-for="exp in expenses" v-else :key="`m-${exp.id}`" class="finv2-card">
          <div class="pyv2__card-row">
            <div class="pyv2__card-info">
              <strong>{{ exp.description }}</strong>
              <span class="pyv2__card-meta">{{ exp.category_name || 'Sem categoria' }}</span>
              <Tooltip
                v-if="exp.auto_pay_error"
                :label="`Auto-pagamento falhou em ${formatDateBR(exp.auto_pay_attempted_at)}: ${exp.auto_pay_error}`"
                position="top"
                multiline
              >
                <span class="pyv2__autopay-warn">
                  <i class="i-lucide-alert-triangle w-3 h-3" />
                  Auto-pay falhou
                </span>
              </Tooltip>
            </div>
            <Badge :label="statusBadge(exp.status).label" :color="statusBadge(exp.status).color"
                   :icon="statusBadge(exp.status).icon" size="xs" />
          </div>
          <div class="pyv2__card-grid">
            <div>
              <span class="pyv2__card-label">Valor</span>
              <strong class="pyv2__card-value">{{ centsToBRL(exp.amount_cents) }}</strong>
            </div>
            <div>
              <span class="pyv2__card-label">Vencimento</span>
              <span class="pyv2__card-value-muted">{{ formatDateBR(exp.due_date) }}</span>
            </div>
          </div>
          <div v-if="isPayable(exp) || exp.status === 'pago'" class="pyv2__card-actions">
            <BeclinicButton v-if="isPayable(exp)" size="sm" variant="faded" color="blue"
                            icon="i-lucide-check" label="Pagar" @click="payExpense(exp)" />
            <BeclinicButton v-if="exp.status === 'pago'" size="sm" variant="ghost" color="ruby"
                            icon="i-lucide-undo" label="Estornar" @click="reverseExpense(exp)" />
          </div>
        </article>
      </div>

      <Pagination
        v-model:current-page="currentPage"
        v-model:per-page="perPage"
        :total-count="meta.total_count || 0"
        item-label="despesas"
      />
    </div>

    <!-- Modais -->
    <PayExpenseModalV2
      :show="showPayModal"
      :expense="expenseBeingPaid"
      @close="showPayModal = false"
      @confirm="onPayConfirmed"
    />
    <ManualEntryModalV2
      :show="showManualEntryModal"
      direction="out"
      @close="showManualEntryModal = false"
      @confirm="onManualEntryConfirmed"
    />
    <ReverseExpenseModalV2
      v-if="reverseModalShow"
      :show="reverseModalShow"
      :expense="expenseToReverse"
      @close="closeReverseModal"
      @confirm="onReverseConfirm"
    />
  </div>
</template>

<style scoped lang="scss">
/* Estilos compartilhados (.finv2-page, .finv2-kpis, .finv2-chip, .finv2-table,
   .finv2-input, .finv2-state) vêm do global em
   plugins/financial/frontend/styles/financial/_layout.scss
   importado via `import 'financial.scss'` no topo do <script>.
   Aqui só ficam os ajustes específicos da página A Pagar. */

.pyv2__filters { display: flex; flex-direction: column; gap: 12px; }
.pyv2__inputs {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr auto auto;
  gap: 8px;
  align-items: center;
}
@media (max-width: 800px) {
  .pyv2__inputs { grid-template-columns: 1fr 1fr; }
  .pyv2__input--grow { grid-column: 1 / -1; }
}
.pyv2__clear {
  display: inline-flex; align-items: center; gap: 4px;
  background: transparent;
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-9));
  font-size: 12px; cursor: pointer;
  padding: 9px 12px; border-radius: 8px;
  &:hover { color: rgb(var(--slate-12)); border-color: rgb(var(--slate-7)); }
}

/* Mobile cards específicos da página */
.pyv2__card-row { display: flex; align-items: flex-start; gap: 10px; }
.pyv2__card-info { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px; }
.pyv2__card-meta { font-size: 12px; color: rgb(var(--slate-9)); }

/* Coluna Descrição da tabela + cards mobile: lugar pra empilhar o
   warning de auto-pay falhou abaixo do nome. */
.pyv2__desc-cell {
  display: flex; flex-direction: column; gap: 4px;
}
.pyv2__autopay-warn {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px; font-weight: 600;
  letter-spacing: 0.04em;
  background: rgba(220, 38, 38, 0.12);
  color: #991b1b;
  cursor: help;
  width: fit-content;
  i { color: #dc2626; }
}
:root.dark .pyv2__autopay-warn {
  background: rgba(220, 38, 38, 0.20);
  color: #fca5a5;
  i { color: #fca5a5; }
}
.pyv2__card-grid {
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 10px;
  padding-top: 10px; border-top: 1px solid rgb(var(--slate-3));
}
.pyv2__card-label {
  display: block; font-size: 10.5px; text-transform: uppercase;
  letter-spacing: 0.04em; color: rgb(var(--slate-9)); margin-bottom: 3px;
}
.pyv2__card-value { font-size: 14px; color: rgb(var(--slate-12)); font-weight: 600; font-variant-numeric: tabular-nums; }
.pyv2__card-value-muted { font-size: 13px; color: rgb(var(--slate-11)); }
.pyv2__card-actions { display: flex; gap: 8px; flex-wrap: wrap; }
</style>
