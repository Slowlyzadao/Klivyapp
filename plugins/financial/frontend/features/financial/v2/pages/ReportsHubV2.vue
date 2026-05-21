<script setup>
/**
 * Relatórios — v2 (canon F-30).
 *
 * Hub com 3 sub-relatórios em tabs:
 *   1. Despesas por Categoria — pizza/barras + drill-down + tendência 6m
 *   2. Faturamento por Convênio — faturado/recebido/gap por operadora
 *   3. Ticket Médio — geral + ranking por profissional
 *
 * Filtro de período é compartilhado entre as 3 tabs.
 *
 * Visualizações usam CSS bars proporcionais — sem chart.js aqui pra manter
 * o bundle leve. (Se pedir gráfico mais elaborado, plugar `vue-chartjs`
 * que já existe em `components/AverageTicketTrend.vue`.)
 */
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const route = useRoute();
const router = useRouter();
const notifyError = msg => useNotification.error(msg);

// Tabs URL-driven (espelha SettingsV2). TabBar global aceita objects com
// { key, label } e cuida do indicador animado.
const TABS = [
  { key: 'expenses', label: 'Despesas por Categoria' },
  { key: 'convenio', label: 'Convênio' },
  { key: 'ticket',   label: 'Ticket Médio' },
];

const activeTab = computed(() => {
  const requested = route.params.tab;
  return TABS.find(t => t.key === requested)?.key || 'expenses';
});

const activeTabIndex = computed(() => {
  const idx = TABS.findIndex(t => t.key === activeTab.value);
  return idx >= 0 ? idx : 0;
});

function onTabChanged(tab) {
  router.push({
    name: 'financial_v2_reports_hub_tab',
    params: { ...route.params, tab: tab.key },
  });
}

// Wrapper das tabs pra centralizar a ativa no mobile via scrollIntoView
// (mesma técnica do SettingsV2).
const tabsWrapRef = ref(null);
function scrollActiveTabIntoView() {
  nextTick(() => {
    if (!tabsWrapRef.value) return;
    const activeBtn = tabsWrapRef.value.querySelector('button.text-n-blue-11');
    if (!activeBtn || typeof activeBtn.scrollIntoView !== 'function') return;
    activeBtn.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' });
  });
}
watch(activeTabIndex, scrollActiveTabIntoView, { immediate: true });

const loading = ref(false);

function startOfMonthISO() {
  const d = new Date(); d.setDate(1);
  return d.toISOString().slice(0, 10);
}
function endOfMonthISO() {
  const d = new Date();
  return new Date(d.getFullYear(), d.getMonth() + 1, 0).toISOString().slice(0, 10);
}

const filters = ref({
  from: startOfMonthISO(),
  to: endOfMonthISO(),
  convenio_mode: 'all',
});

// Estado por relatório.
const expensesData = ref({ categories: [], trend: [], summary: {}, uncategorized: {} });
const ticketData = ref({ overall: {}, by_professional: [] });
const convenioData = ref({ summary: {}, operadoras: [] });

// Drill-down de despesas
const drillCategoryId = ref(undefined); // undefined = sem drill, null = "Sem categoria"
const drillCategoryName = ref('');
const drillExpenses = ref([]);
const drillLoading = ref(false);

async function loadExpenses() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.reports.expensesByCategory({
      from: filters.value.from, to: filters.value.to,
    });
    expensesData.value = data || { categories: [], trend: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar despesas por categoria.');
  } finally {
    loading.value = false;
  }
}

async function loadTicket() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.reports.ticketMedio({
      from: filters.value.from, to: filters.value.to,
    });
    ticketData.value = data || { overall: {}, by_professional: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar ticket médio.');
  } finally {
    loading.value = false;
  }
}

async function loadConvenio() {
  loading.value = true;
  try {
    const { data } = await FinancialV2.reports.convenio({
      from: filters.value.from, to: filters.value.to,
      mode: filters.value.convenio_mode,
    });
    convenioData.value = data || { summary: {}, operadoras: [] };
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar relatório de convênio.');
  } finally {
    loading.value = false;
  }
}

function reloadActive() {
  if (activeTab.value === 'expenses') return loadExpenses();
  if (activeTab.value === 'ticket') return loadTicket();
  if (activeTab.value === 'convenio') return loadConvenio();
  return null;
}

// Watch da rota: troca de tab fecha drill-down e recarrega só a tab ativa
// (evita as 3 chamadas paralelas que estavam causando os 3 toasts juntos).
watch(activeTab, () => {
  drillCategoryId.value = undefined;
  reloadActive();
});

watch(() => filters.value.from, reloadActive);
watch(() => filters.value.to, reloadActive);
watch(() => filters.value.convenio_mode, () => {
  if (activeTab.value === 'convenio') loadConvenio();
});

onMounted(reloadActive);

async function openDrill(category) {
  drillCategoryId.value = category.id;
  drillCategoryName.value = category.name;
  drillLoading.value = true;
  try {
    const { data } = await FinancialV2.reports.expensesByCategoryDrilldown(
      category.id == null ? null : category.id,
      { from: filters.value.from, to: filters.value.to },
    );
    drillExpenses.value = data?.data || [];
  } catch (err) {
    notifyError(err?.response?.data?.error || 'Falha ao carregar despesas da categoria.');
  } finally {
    drillLoading.value = false;
  }
}

function closeDrill() {
  drillCategoryId.value = undefined;
  drillExpenses.value = [];
}

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

// Cores semânticas pra barras de categoria — espelha DRE.
const CATEGORY_BAR_COLOR = {
  receita:        '#10b981',
  despesa_fixa:   '#dc2626',
  custo_variavel: '#f59e0b',
  outra_despesa:  '#64748b',
};
function categoryBarColor(kind) {
  return CATEGORY_BAR_COLOR[kind] || '#94a3b8';
}

// Para visualização da tendência: maior valor na série define escala
// das barras. Tudo virou % da maior pra ser comparável.
const trendMax = computed(() => {
  const max = Math.max(0, ...(expensesData.value.trend || []).map(t => t.total_cents || 0));
  return max || 1;
});

// Convênio modes
const CONVENIO_MODES = [
  { key: 'all',        label: 'Todos',      tone: 'blue' },
  { key: 'convenio',   label: 'Convênio',   tone: 'cyan' },
  { key: 'particular', label: 'Particular', tone: 'slate' },
];
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Relatórios</h1>
        <p class="finv2-page__subtitle">
          Despesas por Categoria, Faturamento por Convênio e Ticket Médio.
          Períodos compartilhados entre as 3 abas.
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
        <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- TabBar global (mesmo padrão de Configurações) — pílula com indicador
           deslizante animado, scroll horizontal sem barra visível no mobile. -->
      <div ref="tabsWrapRef" class="rep-v2__tabs-wrap">
        <TabBar
          :tabs="TABS"
          :initial-active-tab="activeTabIndex"
          @tab-changed="onTabChanged"
        />
      </div>

      <!-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -->
      <!-- TAB 1 — DESPESAS POR CATEGORIA -->
      <section v-if="activeTab === 'expenses'" class="rep-v2__section">
        <div class="finv2-kpis">
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--danger">
              <i class="i-lucide-trending-down w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Total despesas (pago)</span>
              <strong class="finv2-kpi__value finv2-kpi__value--danger">
                {{ centsToBRL(expensesData.summary.total_cents || 0) }}
              </strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
              <i class="i-lucide-list w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Lançamentos</span>
              <strong class="finv2-kpi__value">{{ expensesData.summary.expenses_count || 0 }}</strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
              <i class="i-lucide-tag w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Categorias usadas</span>
              <strong class="finv2-kpi__value">{{ expensesData.summary.categories_count || 0 }}</strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--danger">
              <i class="i-lucide-alert-circle w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Sem categoria</span>
              <strong class="finv2-kpi__value finv2-kpi__value--danger">
                {{ centsToBRL(expensesData.uncategorized.total_cents || 0) }}
              </strong>
            </div>
          </div>
        </div>

        <!-- Tendência 6 meses (barras) -->
        <div class="rep-v2__card">
          <header class="rep-v2__card-header">
            <h3 class="rep-v2__card-title">Tendência — últimos 6 meses</h3>
            <p class="rep-v2__card-hint">Total de despesas pagas por mês (independente do filtro de período).</p>
          </header>
          <div class="rep-v2__trend">
            <div
              v-for="t in (expensesData.trend || [])"
              :key="t.month"
              class="rep-v2__trend-col"
            >
              <div class="rep-v2__trend-bar-wrap">
                <div
                  class="rep-v2__trend-bar"
                  :style="{ height: `${Math.max(2, (t.total_cents / trendMax) * 100)}%` }"
                />
              </div>
              <span class="rep-v2__trend-value">{{ centsToBRL(t.total_cents) }}</span>
              <span class="rep-v2__trend-label">{{ t.label }}</span>
            </div>
          </div>
        </div>

        <!-- Breakdown por categoria com barras % -->
        <div v-if="!loading && expensesData.categories.length === 0" class="finv2-state">
          <div class="finv2-state__icon-wrap"><i class="i-lucide-pie-chart w-7 h-7" /></div>
          <p class="finv2-state__title">Nenhuma despesa paga no período</p>
          <p class="finv2-state__hint">Ajuste o período ou registre despesas em A Pagar.</p>
        </div>
        <div v-else class="finv2-table-wrap">
          <table class="finv2-table">
            <thead>
              <tr>
                <th>Categoria</th>
                <th>Distribuição</th>
                <th class="finv2-table__th-num">% do total</th>
                <th class="finv2-table__th-num">Total</th>
                <th class="finv2-table__th-num">Lançamentos</th>
                <th class="rep-v2__th-actions"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="c in expensesData.categories" :key="c.id">
                <td>
                  <div class="rep-v2__cat-cell">
                    <span
                      class="rep-v2__cat-dot"
                      :style="{ background: categoryBarColor(c.kind) }"
                    />
                    <strong>{{ c.name }}</strong>
                  </div>
                </td>
                <td class="rep-v2__bar-cell">
                  <div class="rep-v2__bar-track">
                    <div
                      class="rep-v2__bar-fill"
                      :style="{
                        width: `${c.percent_of_total}%`,
                        background: categoryBarColor(c.kind),
                      }"
                    />
                  </div>
                </td>
                <td class="finv2-table__td-num finv2-table__td-num--strong">
                  {{ c.percent_of_total }}%
                </td>
                <td class="finv2-table__td-num finv2-table__td-num--strong">
                  {{ centsToBRL(c.total_cents) }}
                </td>
                <td class="finv2-table__td-num">{{ c.expenses_count }}</td>
                <td class="rep-v2__td-actions">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-eye"
                    label="Detalhar"
                    @click="openDrill(c)"
                  />
                </td>
              </tr>
              <tr
                v-if="expensesData.uncategorized.count > 0"
                class="rep-v2__row--warning"
              >
                <td>
                  <div class="rep-v2__cat-cell">
                    <span class="rep-v2__cat-dot" style="background: #f59e0b;" />
                    <strong>Sem categoria</strong>
                  </div>
                </td>
                <td colspan="2" class="finv2-table__td-muted">
                  Reclassifique pra entrar no DRE.
                </td>
                <td class="finv2-table__td-num finv2-table__td-num--strong">
                  {{ centsToBRL(expensesData.uncategorized.total_cents) }}
                </td>
                <td class="finv2-table__td-num">{{ expensesData.uncategorized.count }}</td>
                <td class="rep-v2__td-actions">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="amber"
                    icon="i-lucide-eye"
                    label="Ver"
                    @click="openDrill({ id: null, name: 'Sem categoria' })"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Drill-down -->
        <div v-if="drillCategoryId !== undefined" class="rep-v2__drill">
          <header class="rep-v2__drill-header">
            <h3 class="rep-v2__card-title">
              Despesas em "{{ drillCategoryName }}"
            </h3>
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              label="Fechar"
              @click="closeDrill"
            />
          </header>
          <div v-if="drillLoading" class="finv2-state">
            <div class="finv2-spinner" /><span>Carregando…</span>
          </div>
          <div v-else-if="drillExpenses.length === 0" class="finv2-state">
            <p class="finv2-state__title">Nenhuma despesa nessa categoria.</p>
          </div>
          <div v-else class="finv2-table-wrap">
            <table class="finv2-table">
              <thead>
                <tr>
                  <th>Descrição</th>
                  <th>Vencimento</th>
                  <th>Conta</th>
                  <th>Pagamento</th>
                  <th class="finv2-table__th-num">Valor</th>
                </tr>
              </thead>
              <tbody>
                <tr v-for="e in drillExpenses" :key="e.id">
                  <td><strong>{{ e.description }}</strong></td>
                  <td class="finv2-table__td-date">{{ formatDateBR(e.due_date) }}</td>
                  <td class="finv2-table__td-muted">{{ e.bank_account?.name || '—' }}</td>
                  <td class="finv2-table__td-muted">{{ e.payment_method || '—' }}</td>
                  <td class="finv2-table__td-num finv2-table__td-num--strong">
                    {{ centsToBRL(e.amount_cents) }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>

      <!-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -->
      <!-- TAB 2 — CONVÊNIO -->
      <section v-if="activeTab === 'convenio'" class="rep-v2__section">
        <div class="finv2-chips" role="tablist">
          <button
            v-for="m in CONVENIO_MODES"
            :key="m.key"
            type="button"
            class="finv2-chip"
            :class="[`finv2-chip--tone-${m.tone}`, { 'finv2-chip--active': filters.convenio_mode === m.key }]"
            @click="filters.convenio_mode = m.key"
          >
            <span>{{ m.label }}</span>
          </button>
        </div>

        <div class="finv2-kpis">
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
              <i class="i-lucide-receipt w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Faturado</span>
              <strong class="finv2-kpi__value">
                {{ centsToBRL(convenioData.summary.faturado_cents || 0) }}
              </strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--positive">
              <i class="i-lucide-banknote w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Recebido</span>
              <strong class="finv2-kpi__value finv2-kpi__value--positive">
                {{ centsToBRL(convenioData.summary.recebido_cents || 0) }}
              </strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--danger">
              <i class="i-lucide-alert-circle w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Em aberto</span>
              <strong class="finv2-kpi__value finv2-kpi__value--danger">
                {{ centsToBRL(convenioData.summary.em_aberto_cents || 0) }}
              </strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
              <i class="i-lucide-trending-up w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Ticket médio</span>
              <strong class="finv2-kpi__value">
                {{ centsToBRL(convenioData.summary.ticket_medio_cents || 0) }}
              </strong>
            </div>
          </div>
        </div>

        <div v-if="!loading && convenioData.operadoras.length === 0" class="finv2-state">
          <div class="finv2-state__icon-wrap"><i class="i-lucide-shield w-7 h-7" /></div>
          <p class="finv2-state__title">Nenhuma operadora no período</p>
          <p class="finv2-state__hint">Ajuste o filtro ou aprove orçamentos com convênio cadastrado no paciente.</p>
        </div>
        <div v-else class="finv2-table-wrap">
          <table class="finv2-table">
            <thead>
              <tr>
                <th>Operadora</th>
                <th class="finv2-table__th-num">Faturado</th>
                <th class="finv2-table__th-num">Recebido</th>
                <th class="finv2-table__th-num">Gap</th>
                <th class="finv2-table__th-num">Em aberto</th>
                <th class="finv2-table__th-num">Pacientes</th>
                <th class="finv2-table__th-num">Ticket médio</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="op in convenioData.operadoras" :key="op.name">
                <td>
                  <Badge
                    :label="op.name"
                    :color="op.name === 'Particular' ? 'slate' : 'cyan'"
                    size="xs"
                  />
                </td>
                <td class="finv2-table__td-num">{{ centsToBRL(op.faturado_cents) }}</td>
                <td class="finv2-table__td-num finv2-table__td-num--strong">
                  {{ centsToBRL(op.recebido_cents) }}
                </td>
                <td class="finv2-table__td-num rep-v2__gap">
                  {{ op.gap_cents > 0 ? centsToBRL(op.gap_cents) : '—' }}
                </td>
                <td class="finv2-table__td-num rep-v2__open">
                  {{ centsToBRL(op.em_aberto_cents) }}
                </td>
                <td class="finv2-table__td-num">{{ op.patients_count }}</td>
                <td class="finv2-table__td-num">{{ centsToBRL(op.ticket_medio_cents) }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -->
      <!-- TAB 3 — TICKET MÉDIO -->
      <section v-if="activeTab === 'ticket'" class="rep-v2__section">
        <div class="finv2-kpis">
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--positive">
              <i class="i-lucide-banknote w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Receita líquida</span>
              <strong class="finv2-kpi__value finv2-kpi__value--positive">
                {{ centsToBRL(ticketData.overall.receita_cents || 0) }}
              </strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
              <i class="i-lucide-users w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Pacientes únicos</span>
              <strong class="finv2-kpi__value">
                {{ ticketData.overall.patients_count || 0 }}
              </strong>
            </div>
          </div>
          <div class="finv2-kpi">
            <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
              <i class="i-lucide-trending-up w-4 h-4" />
            </div>
            <div class="finv2-kpi__content">
              <span class="finv2-kpi__label">Ticket médio geral</span>
              <strong class="finv2-kpi__value">
                {{ centsToBRL(ticketData.overall.ticket_medio_cents || 0) }}
              </strong>
            </div>
          </div>
        </div>

        <div v-if="!loading && ticketData.by_professional.length === 0" class="finv2-state">
          <div class="finv2-state__icon-wrap"><i class="i-lucide-trending-up w-7 h-7" /></div>
          <p class="finv2-state__title">Sem pagamentos no período</p>
          <p class="finv2-state__hint">Receba alguma parcela para começar a ver o ranking.</p>
        </div>
        <div v-else class="finv2-table-wrap">
          <table class="finv2-table">
            <thead>
              <tr>
                <th>Profissional</th>
                <th class="finv2-table__th-num">Receita</th>
                <th class="finv2-table__th-num">Pacientes únicos</th>
                <th class="finv2-table__th-num">Recibos</th>
                <th class="finv2-table__th-num">Ticket médio</th>
                <th>Comparativo</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="p in ticketData.by_professional" :key="p.id || 'none'">
                <td>
                  <ProfessionalChip
                    v-if="p.id"
                    :name="p.name"
                    :avatar-url="p.avatar_url || ''"
                    size="sm"
                  />
                  <span v-else class="finv2-table__td-muted">{{ p.name }}</span>
                </td>
                <td class="finv2-table__td-num">{{ centsToBRL(p.receita_cents) }}</td>
                <td class="finv2-table__td-num">{{ p.patients_count }}</td>
                <td class="finv2-table__td-num">{{ p.receipts_count }}</td>
                <td class="finv2-table__td-num finv2-table__td-num--strong">
                  {{ centsToBRL(p.ticket_medio_cents) }}
                </td>
                <td class="rep-v2__bar-cell">
                  <div class="rep-v2__bar-track">
                    <div
                      class="rep-v2__bar-fill"
                      :style="{
                        width: `${Math.min(100, (p.ticket_medio_cents /
                          Math.max(1, ticketData.overall.ticket_medio_cents || 1)) * 50)}%`,
                        background: '#3b82f6',
                      }"
                    />
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Wrapper das tabs: scroll horizontal sem barra + respiro vertical pra
   absorver outline+shadow do indicador da TabBar (mesma técnica usada
   em SettingsV2 — não recortar o pill ativo no mobile). */
.rep-v2__tabs-wrap {
  overflow-x: auto;
  scrollbar-width: none;
  -ms-overflow-style: none;
  &::-webkit-scrollbar { display: none; }
  padding: 4px 0;
}

.rep-v2__section { display: flex; flex-direction: column; gap: 16px; }

/* Card genérico (tendência, drill-down) */
.rep-v2__card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 16px 18px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rep-v2__card-header { display: flex; flex-direction: column; gap: 4px; }
.rep-v2__card-title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.rep-v2__card-hint {
  margin: 0;
  font-size: 12px;
  color: rgb(var(--slate-9));
}

/* Tendência (barras verticais) */
.rep-v2__trend {
  display: grid;
  grid-template-columns: repeat(6, minmax(0, 1fr));
  gap: 12px;
  height: 180px;
}
.rep-v2__trend-col {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  min-width: 0;
}
.rep-v2__trend-bar-wrap {
  flex: 1;
  width: 100%;
  display: flex;
  align-items: flex-end;
  justify-content: center;
  background: rgb(var(--slate-2));
  border-radius: 6px;
  overflow: hidden;
}
.rep-v2__trend-bar {
  width: 70%;
  background: linear-gradient(to top, #dc2626, #f87171);
  border-radius: 4px 4px 0 0;
  min-height: 2px;
  transition: height 0.3s ease;
}
.rep-v2__trend-value {
  font-size: 10.5px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
.rep-v2__trend-label {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

/* Barra horizontal % */
.rep-v2__bar-cell { width: 30%; min-width: 120px; }
.rep-v2__bar-track {
  width: 100%;
  height: 8px;
  background: rgb(var(--slate-3));
  border-radius: 4px;
  overflow: hidden;
}
.rep-v2__bar-fill {
  height: 100%;
  border-radius: 4px;
  transition: width 0.3s ease;
}

/* Categoria (bolinha + nome) */
.rep-v2__cat-cell { display: flex; align-items: center; gap: 8px; }
.rep-v2__cat-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }

.rep-v2__th-actions { width: 100px; text-align: right; }
.rep-v2__td-actions { text-align: right; white-space: nowrap; }

.rep-v2__row--warning td { background: rgba(245, 158, 11, 0.06); }
.rep-v2__row--warning strong { color: rgb(var(--amber-11)); }

/* Drill-down */
.rep-v2__drill {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--blue-7));
  border-radius: 12px;
  padding: 16px 18px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}
.rep-v2__drill-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}

/* Convênio */
.rep-v2__gap { color: rgb(var(--amber-11)); font-weight: 600; }
.rep-v2__open { color: rgb(var(--ruby-11)); }
:root.dark .rep-v2__gap { color: #fcd34d; }
:root.dark .rep-v2__open { color: #fca5a5; }

@media (max-width: 800px) {
  .rep-v2__bar-cell { min-width: 80px; }
  .rep-v2__trend { gap: 6px; height: 140px; }
}
</style>
