<script setup>
/**
 * Dashboard financeiro — v2.
 *
 * Layout premium full-width alinhado com o resto das páginas v2:
 *   • Header sticky com backdrop-blur
 *   • KPIs com ícones + cores semânticas (positivo/negativo/neutro)
 *   • Cards "today / month / outlook" agrupados visualmente
 *   • Meta com gauge animado
 *   • Mobile: 1-2 colunas adaptáveis
 *
 * Bugs corrigidos antes (mantidos):
 *   BUG-05: Ticket Médio mostra "—" quando não há base.
 *   BUG-06: Nomes claros — "Resultado de Hoje" / "Saldo Disponível Hoje".
 *   BUG-11: Gauge de meta oculto se meta=0; mostra CTA.
 */
import { ref, onMounted, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import SetupWizardV2 from '../components/SetupWizardV2.vue';
import ManualEntryModalV2 from '../components/ManualEntryModalV2.vue';
import CashFlowDailyChartV2 from '../components/charts/CashFlowDailyChartV2.vue';
import RevenueCompositionChartV2 from '../components/charts/RevenueCompositionChartV2.vue';
import AgingChartV2 from '../components/charts/AgingChartV2.vue';
import RevenueByProfessionalChartV2 from '../components/charts/RevenueByProfessionalChartV2.vue';
import CashFlowProjectionChartV2 from '../components/charts/CashFlowProjectionChartV2.vue';
import DelinquencyTrendChartV2 from '../components/charts/DelinquencyTrendChartV2.vue';
import Sparkline from '../components/charts/Sparkline.vue';
// Carrega o CSS global do plugin financeiro — necessário pra .finv2-page
// ter `position: absolute; inset: 0; overflow-y: auto` (single-source de
// scroll vertical). Sem esse import a página fica com scroll travado.
import '@plugins/financial/frontend/styles/financial.scss';

const data = ref(null);
const loading = ref(false);
const setupRequired = ref(false);
const errorMessage = ref('');

// Sparklines: dados de tendência 14 dias para entradas/saídas/saldo.
// Vem do endpoint v1 `/dashboard/kpis` (legado já calcula isso).
// Carregamento independente do dashboard principal — não bloqueia paint.
const sparklines = ref({ entradas: [], saidas: [], saldo: [], inadimplencia: [] });

// Period selector — mesmo padrão do DRE. Controla os KPIs do bloco "Mês"
// (que vira "Período") + Próximos vencimentos + Comparação vs período anterior.
// Charts (Cash Flow Diário etc) mantêm sua janela própria.
const PERIOD_TYPES = [
  { value: 'week',    label: 'Semana' },
  { value: 'month',   label: 'Mês' },
  { value: 'quarter', label: 'Trimestre' },
  { value: 'year',    label: 'Ano' },
  { value: 'all',     label: 'Todos' },
];
const periodType = ref('month');
const anchor = ref(new Date());
const period = computed(() => buildPeriod(periodType.value, anchor.value));

function buildPeriod(type, date) {
  const y = date.getFullYear();
  const m = date.getMonth();
  if (type === 'all') {
    return { from: '2010-01-01', to: new Date().toISOString().slice(0, 10), label: 'Todo o período' };
  }
  if (type === 'year') {
    return { from: `${y}-01-01`, to: `${y}-12-31`, label: String(y) };
  }
  if (type === 'quarter') {
    const q = Math.floor(m / 3);
    const firstMonth = q * 3;
    const first = new Date(y, firstMonth, 1).toISOString().slice(0, 10);
    const last = new Date(y, firstMonth + 3, 0).toISOString().slice(0, 10);
    return { from: first, to: last, label: `T${q + 1}/${y}` };
  }
  if (type === 'week') {
    const d = new Date(date);
    const day = d.getDay();
    const diffToMonday = day === 0 ? -6 : 1 - day;
    d.setDate(d.getDate() + diffToMonday);
    const start = new Date(d);
    const end = new Date(d);
    end.setDate(d.getDate() + 6);
    const fmt = dt => `${String(dt.getDate()).padStart(2, '0')}/${String(dt.getMonth() + 1).padStart(2, '0')}`;
    return {
      from: start.toISOString().slice(0, 10),
      to: end.toISOString().slice(0, 10),
      label: `${fmt(start)} – ${fmt(end)}/${end.getFullYear()}`,
    };
  }
  const first = new Date(y, m, 1).toISOString().slice(0, 10);
  const last = new Date(y, m + 1, 0).toISOString().slice(0, 10);
  return { from: first, to: last, label: `${String(m + 1).padStart(2, '0')}/${y}` };
}

function shift(delta) {
  if (periodType.value === 'all') return;
  const d = new Date(anchor.value);
  if (periodType.value === 'year') d.setFullYear(d.getFullYear() + delta);
  else if (periodType.value === 'quarter') d.setMonth(d.getMonth() + delta * 3);
  else if (periodType.value === 'week') d.setDate(d.getDate() + delta * 7);
  else d.setMonth(d.getMonth() + delta);
  anchor.value = d;
}

// Label dinâmico da section "Mês" — muda conforme o período.
const monthSectionLabel = computed(() => {
  const map = { week: 'Semana', month: 'Mês', quarter: 'Trimestre', year: 'Ano', all: 'Período' };
  return map[periodType.value] || 'Período';
});

// Título da section de meta, baseado no `kind` que o backend devolve.
// Backend escolhe a meta certa (monthly/quarterly/annual) conforme a duração
// do período filtrado — o frontend apenas reflete.
function goalTitleFor(kind) {
  const map = {
    monthly:   'Meta de receita mensal',
    quarterly: 'Meta de receita trimestral',
    annual:    'Meta de receita anual',
  };
  return map[kind] || 'Meta de receita';
}

async function load() {
  loading.value = true;
  errorMessage.value = '';
  try {
    const { data: payload } = await FinancialV2.reports.dashboard({
      from: period.value.from,
      to: period.value.to,
    });
    data.value = payload;
    setupRequired.value = false;
  } catch (err) {
    if (err?.response?.status === 412 && err.response.data?.error === 'financial_setup_required') {
      setupRequired.value = true;
    } else {
      errorMessage.value = err?.response?.data?.message || err?.message || 'Erro ao carregar dashboard';
    }
  } finally {
    loading.value = false;
  }
}

// Re-carrega dashboard quando o período muda (charts mantêm sua janela própria,
// só os KPIs reagem ao filtro — comportamento documentado no subtítulo de cada
// chart "últimos N dias / meses").
watch(period, () => load(), { deep: true });

function onSetupCompleted() {
  setupRequired.value = false;
  load();
}

async function loadSparklines() {
  try {
    const { data: payload } = await FinancialV2.reports.dashboardKpis();
    sparklines.value = payload?.sparklines || { entradas: [], saidas: [], saldo: [], inadimplencia: [] };
  } catch (_e) {
    // sparklines são adorno — silencioso é melhor que poluir a UI com erro.
  }
}

onMounted(() => {
  load();
  loadSparklines();
});

function formatTicket(t) {
  if (!t || t.value_cents === null || t.unique_patients === 0) return '—';
  return centsToBRL(t.value_cents);
}

// Modal de lançamento avulso (canon F-25). Aberto via botões "Nova entrada"
// / "Nova saída" do header do Dashboard. Recarrega KPIs após confirmar.
const showManualEntryModal = ref(false);
const manualEntryDirection = ref(null);

function openManualEntry(direction) {
  manualEntryDirection.value = direction;
  showManualEntryModal.value = true;
}
function onManualEntryConfirmed() {
  showManualEntryModal.value = false;
  manualEntryDirection.value = null;
  load();
}
</script>

<template>
  <div class="finv2-page">
    <!-- Header sticky -->
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Dashboard</h1>
        <p class="finv2-page__subtitle">
          Resumo financeiro: receita, despesas, recebíveis e meta.
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <!-- Period selector (mesmo design do DRE) -->
        <div v-if="!loading && !setupRequired" class="dash-v2__period-group">
          <div class="dash-v2__period-tabs" role="tablist">
            <button
              v-for="type in PERIOD_TYPES"
              :key="type.value"
              :class="['dash-v2__period-tab', { 'dash-v2__period-tab--active': periodType === type.value }]"
              type="button"
              @click="periodType = type.value"
            >
              {{ type.label }}
            </button>
          </div>
          <div class="dash-v2__period">
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-chevron-left"
              :disabled="periodType === 'all'"
              @click="shift(-1)"
            />
            <strong class="dash-v2__period-label">{{ period.label }}</strong>
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-chevron-right"
              :disabled="periodType === 'all'"
              @click="shift(1)"
            />
          </div>
        </div>

        <BeclinicButton
          v-if="!loading && !setupRequired"
          variant="faded"
          color="teal"
          icon="i-lucide-arrow-down-to-line"
          label="Nova entrada"
          size="sm"
          @click="openManualEntry('in')"
        />
        <BeclinicButton
          v-if="!loading && !setupRequired"
          variant="faded"
          color="ruby"
          icon="i-lucide-arrow-up-from-line"
          label="Nova saída"
          size="sm"
          @click="openManualEntry('out')"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- Loading -->
      <div v-if="loading" class="dash-v2__loading">
        <div class="dash-v2__spinner" aria-hidden="true" />
        <span>Carregando dashboard…</span>
      </div>

      <!-- Setup wizard -->
      <SetupWizardV2 v-else-if="setupRequired" @completed="onSetupCompleted" />

      <!-- Erro -->
      <div v-else-if="errorMessage" class="dash-v2__error">
        <div class="dash-v2__error-icon">
          <i class="i-lucide-alert-triangle w-7 h-7" />
        </div>
        <p class="dash-v2__error-title">Erro ao carregar dashboard</p>
        <p class="dash-v2__error-msg">{{ errorMessage }}</p>
        <BeclinicButton
          variant="solid"
          color="ruby"
          icon="i-lucide-refresh-cw"
          label="Tentar novamente"
          @click="load"
        />
      </div>

      <!-- Conteúdo -->
      <template v-else-if="data">
        <!-- Linha 1: Hoje -->
        <section class="dash-v2__section">
          <h2 class="dash-v2__section-title">Hoje</h2>
          <div class="dash-v2__grid dash-v2__grid--2">
            <div class="dash-v2__kpi dash-v2__kpi--lg">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--neutral">
                <i class="i-lucide-activity w-5 h-5" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Resultado de Hoje</span>
                <strong class="dash-v2__kpi-value">{{ centsToBRL(data.today.net_cents) }}</strong>
                <Sparkline
                  v-if="sparklines.saldo?.length"
                  class="dash-v2__kpi-spark"
                  :values="sparklines.saldo"
                  color="#64748b"
                  :height="22"
                />
                <small class="dash-v2__kpi-hint">
                  Entradas {{ centsToBRL(data.today.income_cents) }} · Saídas
                  {{ centsToBRL(data.today.outflow_cents) }}
                </small>
              </div>
            </div>
            <div class="dash-v2__kpi dash-v2__kpi--lg">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--positive">
                <i class="i-lucide-wallet w-5 h-5" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Saldo Disponível Hoje</span>
                <strong class="dash-v2__kpi-value dash-v2__kpi-value--positive">
                  {{ centsToBRL(data.cash.available_balance_cents) }}
                </strong>
                <Sparkline
                  v-if="sparklines.saldo?.length"
                  class="dash-v2__kpi-spark"
                  :values="sparklines.saldo"
                  color="#10b981"
                  :height="22"
                />
                <small class="dash-v2__kpi-hint">
                  Soma de todas as contas (exceto a receber de cartão)
                </small>
              </div>
            </div>
          </div>
        </section>

        <!-- Linha 2: Período (Mês / Semana / Trimestre / Ano / Todos) -->
        <section class="dash-v2__section">
          <h2 class="dash-v2__section-title">{{ monthSectionLabel }} · {{ period.label }}</h2>
          <div class="dash-v2__grid dash-v2__grid--4">
            <div class="dash-v2__kpi dash-v2__kpi--highlight">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--positive">
                <i class="i-lucide-trending-up w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Receita Bruta</span>
                <strong class="dash-v2__kpi-value">{{ centsToBRL(data.month.receita_bruta_cents) }}</strong>
                <Sparkline
                  v-if="sparklines.entradas?.length"
                  class="dash-v2__kpi-spark"
                  :values="sparklines.entradas"
                  color="#10b981"
                  :height="18"
                />
                <small
                  class="dash-v2__kpi-trend"
                  :class="data.comparison.income_var_label === 'Novo' ? 'dash-v2__kpi-trend--neutral' : 'dash-v2__kpi-trend--positive'"
                >
                  {{ data.comparison.income_var_label }} vs mês anterior
                </small>
              </div>
            </div>
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--danger">
                <i class="i-lucide-trending-down w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Despesa</span>
                <strong class="dash-v2__kpi-value dash-v2__kpi-value--danger">
                  {{ centsToBRL(data.month.despesa_total_cents) }}
                </strong>
                <Sparkline
                  v-if="sparklines.saidas?.length"
                  class="dash-v2__kpi-spark"
                  :values="sparklines.saidas"
                  color="#ef4444"
                  :height="18"
                />
              </div>
            </div>
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--positive">
                <i class="i-lucide-banknote w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Lucro Líquido</span>
                <strong class="dash-v2__kpi-value dash-v2__kpi-value--positive">
                  {{ centsToBRL(data.month.lucro_liquido_cents) }}
                </strong>
                <small
                  class="dash-v2__kpi-trend"
                  :class="data.comparison.lucro_var_label === 'Novo' ? 'dash-v2__kpi-trend--neutral' : 'dash-v2__kpi-trend--positive'"
                >
                  {{ data.comparison.lucro_var_label }}
                </small>
              </div>
            </div>
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--neutral">
                <i class="i-lucide-users w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Ticket Médio</span>
                <strong class="dash-v2__kpi-value">{{ formatTicket(data.ticket_medio) }}</strong>
                <small class="dash-v2__kpi-hint">
                  <template v-if="data.ticket_medio?.unique_patients > 0">
                    {{ data.ticket_medio.unique_patients }} pacientes únicos
                  </template>
                  <template v-else>Sem pacientes únicos no período</template>
                </small>
              </div>
            </div>
          </div>
        </section>

        <!-- Linha 3: Vencimentos — actionable info, vem antes dos charts (acima do fold) -->
        <section class="dash-v2__section">
          <h2 class="dash-v2__section-title">Vencimentos · {{ period.label }}</h2>
          <div class="dash-v2__grid dash-v2__grid--4">
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--neutral">
                <i class="i-lucide-clock w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">A Receber ({{ monthSectionLabel.toLowerCase() }})</span>
                <strong class="dash-v2__kpi-value">
                  {{ centsToBRL(data.receivables.pending_total_cents) }}
                </strong>
              </div>
            </div>
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--danger">
                <i class="i-lucide-alert-triangle w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">Vencido</span>
                <strong class="dash-v2__kpi-value dash-v2__kpi-value--danger">
                  {{ centsToBRL(data.receivables.overdue_total_cents) }}
                </strong>
                <small class="dash-v2__kpi-hint">
                  {{ data.receivables.overdue_count }} parcela(s) vencida(s)
                </small>
              </div>
            </div>
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--neutral">
                <i class="i-lucide-receipt w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">A Pagar ({{ monthSectionLabel.toLowerCase() }})</span>
                <strong class="dash-v2__kpi-value">
                  {{ centsToBRL(data.payables.pending_total_cents) }}
                </strong>
              </div>
            </div>
            <div class="dash-v2__kpi">
              <div class="dash-v2__kpi-icon dash-v2__kpi-icon--neutral">
                <i class="i-lucide-calendar-clock w-4 h-4" />
              </div>
              <div class="dash-v2__kpi-content">
                <span class="dash-v2__kpi-label">A vencer em 3 dias</span>
                <strong class="dash-v2__kpi-value">
                  {{ centsToBRL(data.payables.due_soon_total_cents) }}
                </strong>
              </div>
            </div>
          </div>
        </section>

        <!-- Meta de receita (gauge dinâmico) — segunda info actionable -->
        <section v-if="data.revenue_goal" class="dash-v2__goal">
          <div class="dash-v2__goal-header">
            <div>
              <h2 class="dash-v2__goal-title">{{ goalTitleFor(data.revenue_goal.kind) }}</h2>
              <p class="dash-v2__goal-subtitle">
                {{ centsToBRL(data.revenue_goal.achieved_cents) }} de
                {{ centsToBRL(data.revenue_goal.goal_cents) }} · {{ period.label }}
              </p>
            </div>
            <div class="dash-v2__goal-percent">
              {{ data.revenue_goal.progress_percent }}<span>%</span>
            </div>
          </div>
          <div class="dash-v2__goal-gauge">
            <div
              class="dash-v2__goal-gauge-fill"
              :style="{ width: Math.min(data.revenue_goal.progress_percent, 100) + '%' }"
            />
          </div>
        </section>
        <section v-else class="dash-v2__goal-cta">
          <i class="i-lucide-target w-5 h-5" />
          <p>
            Cadastre uma <strong>meta de receita</strong> para acompanhar seu progresso.
          </p>
          <router-link
            :to="{ name: 'financial_v2_settings_tab', params: { tab: 'goals' } }"
            class="dash-v2__goal-cta-link"
          >
            Ir para Configurações → Metas
            <i class="i-lucide-arrow-right w-3.5 h-3.5" />
          </router-link>
        </section>

        <!-- Charts row 1: Fluxo de Caixa diário + Composição de Receita -->
        <section class="dash-v2__section">
          <h2 class="dash-v2__section-title">Análises · {{ period.label }}</h2>
          <div class="dash-v2__charts-grid">
            <CashFlowDailyChartV2 :from="period.from" :to="period.to" :label="period.label" />
            <RevenueCompositionChartV2 :from="period.from" :to="period.to" :label="`${period.label} · top 5 categorias`" />
          </div>
        </section>

        <!-- Charts row 2: Aging (snapshot) + Receita por Profissional -->
        <section class="dash-v2__section">
          <div class="dash-v2__charts-grid">
            <AgingChartV2 />
            <RevenueByProfessionalChartV2 :from="period.from" :to="period.to" :label="`${period.label} · top 5`" />
          </div>
        </section>

        <!-- Charts row 3: Projeção (forward-looking 60d) + Tendência Inadimplência (12 meses) -->
        <section class="dash-v2__section">
          <h2 class="dash-v2__section-title">Previsões e tendências</h2>
          <div class="dash-v2__charts-grid">
            <CashFlowProjectionChartV2 />
            <DelinquencyTrendChartV2 />
          </div>
        </section>
      </template>
    </div>

    <ManualEntryModalV2
      :show="showManualEntryModal"
      :direction="manualEntryDirection"
      @close="showManualEntryModal = false"
      @confirm="onManualEntryConfirmed"
    />
  </div>
</template>

<style scoped lang="scss">
/* ── Layout base — full width, sticky header, premium feel ──────── */
/* Position absolute + inset 0 + overflow-y auto vêm do global
   plugins/financial/frontend/styles/financial/_layout.scss
   (regra `.finv2-page` lá garante <main> relative + scroll single-source). */
.finv2-page {
  display: flex;
  flex-direction: column;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-12));
}
.finv2-page__header {
  position: sticky;
  top: 0;
  z-index: 10;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 16px;
  padding: 18px 24px;
  background: rgb(var(--slate-1) / 0.92);
  backdrop-filter: blur(8px);
  border-bottom: 1px solid rgb(var(--slate-4));
  flex-wrap: wrap;
}
.finv2-page__title {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
  letter-spacing: -0.01em;
  color: rgb(var(--slate-12));
}
.finv2-page__subtitle {
  margin: 4px 0 0;
  font-size: 13px;
  color: rgb(var(--slate-9));
}
.finv2-page__header-actions {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.finv2-page__body {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 20px;
  padding: 20px 24px 28px;
}
@media (max-width: 640px) {
  .finv2-page__header { padding: 14px 16px; }
  .finv2-page__body   { padding: 16px 14px 24px; gap: 14px; }
  .finv2-page__title  { font-size: 18px; }
}

/* ── Sections ─────────────────────────────────────────────────── */
.dash-v2__section {
  display: flex;
  flex-direction: column;
  gap: 10px;
}
.dash-v2__section-title {
  margin: 0;
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
  font-weight: 600;
}

.dash-v2__grid {
  display: grid;
  gap: 12px;
}
.dash-v2__grid--2 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.dash-v2__grid--4 { grid-template-columns: repeat(4, minmax(0, 1fr)); }
.dash-v2__charts-grid {
  display: grid; gap: 14px;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
@media (max-width: 1024px) {
  .dash-v2__grid--4 { grid-template-columns: repeat(2, 1fr); }
  .dash-v2__charts-grid { grid-template-columns: 1fr; }
}
@media (max-width: 640px) {
  .dash-v2__grid--2 { grid-template-columns: 1fr; }
  .dash-v2__grid--4 { grid-template-columns: 1fr; }
}

/* ── KPI cards ─────────────────────────────────────────────────── */
.dash-v2__kpi {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 16px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  transition: border-color 0.15s ease, transform 0.15s ease;
  &:hover {
    border-color: rgb(var(--slate-6));
    transform: translateY(-1px);
  }
}
.dash-v2__kpi--lg .dash-v2__kpi-value { font-size: 26px; }
.dash-v2__kpi--highlight {
  background: linear-gradient(135deg, rgb(var(--slate-2)) 0%, rgba(16, 185, 129, 0.05) 100%);
  border-color: rgba(16, 185, 129, 0.25);
}
:root.dark .dash-v2__kpi--highlight {
  background: linear-gradient(135deg, rgb(var(--slate-2)) 0%, rgba(16, 185, 129, 0.08) 100%);
}

.dash-v2__kpi-icon {
  flex-shrink: 0;
  width: 38px;
  height: 38px;
  border-radius: 10px;
  display: flex;
  align-items: center;
  justify-content: center;
  &--neutral {
    background: rgb(var(--slate-3));
    color: rgb(var(--slate-11));
  }
  &--positive {
    background: rgba(16, 185, 129, 0.12);
    color: #047857;
  }
  &--danger {
    background: rgba(220, 38, 38, 0.12);
    color: #b91c1c;
  }
}
:root.dark .dash-v2__kpi-icon--positive { color: #6ee7b7; background: rgba(16, 185, 129, 0.18); }
:root.dark .dash-v2__kpi-icon--danger   { color: #fca5a5; background: rgba(220, 38, 38, 0.18); }

.dash-v2__kpi-content {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
  flex: 1;
}
.dash-v2__kpi-label {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
  font-weight: 500;
}
.dash-v2__kpi-value {
  font-size: 20px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  line-height: 1.2;
}
.dash-v2__kpi-value--positive { color: #047857; }
:root.dark .dash-v2__kpi-value--positive { color: #6ee7b7; }
.dash-v2__kpi-value--danger { color: #b91c1c; }
:root.dark .dash-v2__kpi-value--danger { color: #fca5a5; }
.dash-v2__kpi-hint {
  font-size: 11.5px;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}
.dash-v2__kpi-trend {
  font-size: 11.5px;
  font-weight: 500;
  margin-top: 2px;
  &--positive { color: #047857; }
  &--neutral  { color: rgb(var(--slate-9)); }
}
:root.dark .dash-v2__kpi-trend--positive { color: #6ee7b7; }

/* Sparkline mini abaixo do valor do KPI — adorno sutil de tendência. */
.dash-v2__kpi-spark {
  margin: 4px 0 2px;
  opacity: 0.85;
}

/* ── Period selector (idêntico ao DRE) ──────────────────────────────────── */
$dash-period-h: 38px;

.dash-v2__period-group {
  display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap;
}
.dash-v2__period-tabs {
  display: inline-flex; align-items: center; gap: 2px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 3px;
  height: $dash-period-h;
  box-sizing: border-box;
}
.dash-v2__period-tab {
  display: inline-flex; align-items: center; justify-content: center;
  font-size: 12.5px; font-weight: 500;
  color: rgb(var(--slate-11));
  background: transparent;
  border: 0;
  border-radius: 7px;
  padding: 0 12px;
  height: 100%;
  cursor: pointer;
  transition: background 0.12s ease, color 0.12s ease;
  &:hover { color: rgb(var(--slate-12)); }
}
.dash-v2__period-tab--active {
  background: var(--w-500, #1f93ff);
  color: #fff;
  &:hover {
    background: var(--w-600, #0e7be0);
    color: #fff;
  }
}
:root.dark .dash-v2__period-tab--active {
  background: var(--w-500, #1f93ff);
  color: #fff;
  &:hover { background: var(--w-600, #0e7be0); }
}
.dash-v2__period {
  display: inline-flex; align-items: center; gap: 4px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 3px 6px;
  height: $dash-period-h;
  box-sizing: border-box;
}
.dash-v2__period-label {
  font-size: 14px; font-weight: 600; color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  min-width: 150px; text-align: center;
  padding: 0 4px;
}
@media (max-width: 640px) {
  .dash-v2__period-group { width: 100%; justify-content: space-between; }
  .dash-v2__period-tabs { flex: 1; justify-content: space-between; }
  .dash-v2__period-tab { flex: 1; padding: 0 4px; font-size: 11.5px; }
  .dash-v2__period-label { min-width: 100px; font-size: 13px; }
}

/* ── Meta de receita ──────────────────────────────────────────── */
.dash-v2__goal {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 18px;
  display: flex;
  flex-direction: column;
  gap: 14px;
}
.dash-v2__goal-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 14px;
  flex-wrap: wrap;
}
.dash-v2__goal-title {
  margin: 0;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.dash-v2__goal-subtitle {
  margin: 4px 0 0;
  font-size: 13px;
  color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
}
.dash-v2__goal-percent {
  font-size: 32px;
  font-weight: 700;
  color: #047857;
  line-height: 1;
  font-variant-numeric: tabular-nums;
  span { font-size: 18px; opacity: 0.8; margin-left: 2px; }
}
:root.dark .dash-v2__goal-percent { color: #6ee7b7; }
.dash-v2__goal-gauge {
  height: 10px;
  background: rgb(var(--slate-3));
  border-radius: 999px;
  overflow: hidden;
}
.dash-v2__goal-gauge-fill {
  height: 100%;
  background: linear-gradient(90deg, #10b981, #34d399);
  transition: width 400ms ease-out;
  border-radius: 999px;
}

.dash-v2__goal-cta {
  background: rgba(245, 158, 11, 0.10);
  border-left: 4px solid #f59e0b;
  border-radius: 10px;
  padding: 14px 16px;
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  color: rgb(var(--slate-12));
  font-size: 13px;
  i { color: #d97706; flex-shrink: 0; }
  p { margin: 0; flex: 1; min-width: 0; }
  strong { font-weight: 600; }
}
.dash-v2__goal-cta-link {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: #047857;
  text-decoration: none;
  font-weight: 500;
  font-size: 13px;
  &:hover { color: #065f46; text-decoration: underline; }
}
:root.dark .dash-v2__goal-cta-link { color: #6ee7b7; }

/* ── Estados (loading, erro) ──────────────────────────────────── */
.dash-v2__loading,
.dash-v2__error {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 12px;
  padding: 60px 20px;
  text-align: center;
}
.dash-v2__loading { color: rgb(var(--slate-9)); font-size: 14px; }
.dash-v2__spinner {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  border: 3px solid rgb(var(--slate-9));
  border-top-color: transparent;
  animation: dash-v2-spin 0.9s linear infinite;
}
@keyframes dash-v2-spin {
  to { transform: rotate(360deg); }
}

.dash-v2__error-icon {
  width: 56px;
  height: 56px;
  border-radius: 14px;
  background: rgba(220, 38, 38, 0.12);
  color: #b91c1c;
  display: flex;
  align-items: center;
  justify-content: center;
}
:root.dark .dash-v2__error-icon { color: #fca5a5; background: rgba(220, 38, 38, 0.18); }
.dash-v2__error-title {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.dash-v2__error-msg {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-9));
  max-width: 420px;
}
</style>
