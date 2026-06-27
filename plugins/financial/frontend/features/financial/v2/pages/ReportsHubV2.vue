<script setup>
/**
 * Hub de Relatórios — canon F-30 + wireframe card-grid (2026-05-23).
 *
 * Refator do antigo padrão tab-bar (3 abas) pro card-grid (7 relatórios)
 * conforme wireframe Streit Financeiro. Estrutura:
 *
 *   ┌─ Hub landing ──┐    ┌─ Detail view ─────────────┐
 *   │ 8 cards em 3   │ →  │ Voltar · Título · Export  │
 *   │ grupos (Recei- │    │ <component slug-driven>   │
 *   │ tas/Despesas/  │    └───────────────────────────┘
 *   │ Performance)   │
 *   └────────────────┘
 *
 * URL: /reports = hub landing; /reports/:slug = detail view.
 * Slugs legados (`expenses`, `convenio`, `ticket`) viram redirect interno
 * pros novos slugs (`expenses-by-category`, `revenue-by-insurance`, `average-ticket`).
 *
 * SEM duplicação: Comissões e Fluxo Projetado NÃO aparecem aqui — têm
 * tela própria. Hub foca em análise tabular pra GERENTE/ADMIN/AUDITOR.
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import PeriodSelectorV2 from '../components/PeriodSelectorV2.vue';

import RevenueByProcedureReport from '../components/reports/RevenueByProcedureReport.vue';
import RevenueByProfessionalReport from '../components/reports/RevenueByProfessionalReport.vue';
import RevenueByPaymentMethodReport from '../components/reports/RevenueByPaymentMethodReport.vue';
import RevenueByInsuranceReport from '../components/reports/RevenueByInsuranceReport.vue';
import ExpensesByCategoryReport from '../components/reports/ExpensesByCategoryReport.vue';
import AccountStatementReport from '../components/reports/AccountStatementReport.vue';
import AverageTicketReport from '../components/reports/AverageTicketReport.vue';
import GoalsVsActualReport from '../components/reports/GoalsVsActualReport.vue';

import '@plugins/financial/frontend/styles/financial.scss';

const route = useRoute();
const router = useRouter();

// ── Catálogo de cards ─────────────────────────────────────────────
// `component` é o próprio componente Vue, importado acima.
// `slug` casa com `route.params.tab` — backward-compat fica em LEGACY_ALIASES.
const REVENUE_CARDS = [
  {
    slug: 'revenue-by-procedure',
    icon: 'i-lucide-clipboard-list',
    title: 'Receitas por Procedimento',
    subtitle: 'Qual procedimento gerou mais receita no período',
    component: RevenueByProcedureReport,
  },
  {
    slug: 'revenue-by-professional',
    icon: 'i-lucide-users',
    title: 'Receitas por Profissional',
    subtitle: 'Produção de cada DR no período',
    component: RevenueByProfessionalReport,
  },
  {
    slug: 'revenue-by-payment-method',
    icon: 'i-lucide-credit-card',
    title: 'Receitas por Forma de Pagamento',
    subtitle: 'Quanto veio de Pix, crédito, convênio + taxas',
    component: RevenueByPaymentMethodReport,
  },
  {
    slug: 'revenue-by-insurance',
    icon: 'i-lucide-shield',
    title: 'Receitas por Convênio',
    subtitle: 'Faturado, recebido e gap por operadora',
    component: RevenueByInsuranceReport,
  },
];

const EXPENSES_CARDS = [
  {
    slug: 'expenses-by-category',
    icon: 'i-lucide-pie-chart',
    title: 'Despesas por Categoria',
    subtitle: 'Ranking de onde o dinheiro saiu',
    component: ExpensesByCategoryReport,
  },
  {
    slug: 'account-statement',
    icon: 'i-lucide-wallet',
    title: 'Extrato por Conta',
    subtitle: 'Todos os lançamentos de uma conta',
    component: AccountStatementReport,
  },
];

const PERFORMANCE_CARDS = [
  {
    slug: 'average-ticket',
    icon: 'i-lucide-trending-up',
    title: 'Ticket Médio',
    subtitle: 'Geral + ranking por profissional',
    component: AverageTicketReport,
  },
  {
    slug: 'goals-vs-actual',
    icon: 'i-lucide-target',
    title: 'Metas vs Realizado',
    subtitle: 'Todas as metas com % atingido',
    component: GoalsVsActualReport,
  },
];

const ALL_CARDS = [...REVENUE_CARDS, ...EXPENSES_CARDS, ...PERFORMANCE_CARDS];

// Aliases pra URLs antigas. Tela legada usava `expenses`/`convenio`/`ticket`
// como tabs; hoje pra preservar bookmarks externos mapeamos pros novos
// slugs sem quebrar o link.
const LEGACY_ALIASES = {
  expenses: 'expenses-by-category',
  convenio: 'revenue-by-insurance',
  ticket:   'average-ticket',
};

const requestedSlug = computed(() => {
  const raw = route.params.tab;
  if (!raw) return null;
  return LEGACY_ALIASES[raw] || raw;
});

const activeCard = computed(() => {
  if (!requestedSlug.value) return null;
  return ALL_CARDS.find(c => c.slug === requestedSlug.value) || null;
});

// ── Filtro de período compartilhado ────────────────────────────────
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
});

// ── Navegação ─────────────────────────────────────────────────────
function openCard(slug) {
  router.push({
    name: 'financial_v2_reports_hub_tab',
    params: { ...route.params, tab: slug },
  });
}

function goBackToHub() {
  router.push({
    name: 'financial_v2_reports_hub',
    params: { accountId: route.params.accountId },
  });
}

// Quando alguém abre /reports/expenses (slug legado), redireciona
// invisivelmente pro slug novo (mantém URL bonita).
watch(requestedSlug, (slug, oldSlug) => {
  const raw = route.params.tab;
  if (raw && slug && raw !== slug && LEGACY_ALIASES[raw]) {
    router.replace({
      name: 'financial_v2_reports_hub_tab',
      params: { ...route.params, tab: slug },
    });
  }
});

// ── Export CSV ────────────────────────────────────────────────────
// Cada componente filho expõe `exportCsv()` via defineExpose. O Hub
// chama via ref e materializa o blob de download. Mantém a lógica de
// formatação no componente (tem contexto dos dados) e o disparo do
// download no Hub (UI shell).
const activeReportRef = ref(null);

function exportCurrentReport() {
  if (!activeReportRef.value?.exportCsv) return;
  const rows = activeReportRef.value.exportCsv();
  if (!rows || rows.length === 0) return;

  const csv = rows.map(r =>
    r.map(cell => {
      const s = String(cell ?? '');
      // RFC 4180: escapar campo se contém vírgula, quebra ou aspas
      if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
      return s;
    }).join(',')
  ).join('\n');

  const blob = new Blob(["﻿" + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  const period = `${filters.value.from}_a_${filters.value.to}`;
  a.download = `${activeCard.value.slug}_${period}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Relatórios</h1>
        <p class="finv2-page__subtitle">
          <template v-if="!activeCard">Visões específicas com filtros próprios. Apenas leitura — sem mutação.</template>
          <template v-else>{{ activeCard.subtitle }}</template>
        </p>
      </div>
      <div v-if="activeCard" class="finv2-page__header-actions">
        <PeriodSelectorV2
          v-model:from="filters.from"
          v-model:to="filters.to"
        />
        <BeclinicButton
          variant="solid"
          color="teal"
          icon="i-lucide-table-2"
          label="Baixar tabela"
          size="sm"
          @click="exportCurrentReport"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- ━━━━━ HUB (LANDING) ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -->
      <template v-if="!activeCard">
        <section class="rep-hub__group">
          <h2 class="rep-hub__group-title">Receitas</h2>
          <div class="rep-hub__cards">
            <button
              v-for="card in REVENUE_CARDS"
              :key="card.slug"
              type="button"
              class="rep-hub__card"
              @click="openCard(card.slug)"
            >
              <i :class="card.icon" class="rep-hub__card-icon" />
              <strong class="rep-hub__card-title">{{ card.title }}</strong>
              <span class="rep-hub__card-subtitle">{{ card.subtitle }}</span>
            </button>
          </div>
        </section>

        <section class="rep-hub__group">
          <h2 class="rep-hub__group-title">Despesas</h2>
          <div class="rep-hub__cards">
            <button
              v-for="card in EXPENSES_CARDS"
              :key="card.slug"
              type="button"
              class="rep-hub__card"
              @click="openCard(card.slug)"
            >
              <i :class="card.icon" class="rep-hub__card-icon" />
              <strong class="rep-hub__card-title">{{ card.title }}</strong>
              <span class="rep-hub__card-subtitle">{{ card.subtitle }}</span>
            </button>
          </div>
        </section>

        <section class="rep-hub__group">
          <h2 class="rep-hub__group-title">Performance</h2>
          <div class="rep-hub__cards">
            <button
              v-for="card in PERFORMANCE_CARDS"
              :key="card.slug"
              type="button"
              class="rep-hub__card"
              @click="openCard(card.slug)"
            >
              <i :class="card.icon" class="rep-hub__card-icon" />
              <strong class="rep-hub__card-title">{{ card.title }}</strong>
              <span class="rep-hub__card-subtitle">{{ card.subtitle }}</span>
            </button>
          </div>
        </section>
      </template>

      <!-- ━━━━━ DETAIL VIEW ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ -->
      <template v-else>
        <div class="rep-hub__detail-header">
          <BeclinicButton
            variant="ghost"
            color="slate"
            icon="i-lucide-arrow-left"
            label="Voltar"
            size="sm"
            @click="goBackToHub"
          />
          <h2 class="rep-hub__detail-title">
            <i :class="activeCard.icon" />
            {{ activeCard.title }}
          </h2>
        </div>

        <component
          v-if="activeCard.component"
          :is="activeCard.component"
          :key="activeCard.slug"
          ref="activeReportRef"
          :from="filters.from"
          :to="filters.to"
        />
      </template>
    </div>
  </div>
</template>

<style scoped lang="scss">
.rep-hub__group {
  display: flex; flex-direction: column; gap: 12px;
  margin-bottom: 28px;
  &:last-child { margin-bottom: 0; }
}
.rep-hub__group-title {
  margin: 0;
  font-size: 11px; font-weight: 700;
  text-transform: uppercase; letter-spacing: 0.06em;
  color: rgb(var(--slate-10));
}

.rep-hub__cards {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 14px;
  @media (max-width: 1024px) { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  @media (max-width: 640px)  { grid-template-columns: 1fr; }
}
.rep-hub__card {
  display: flex; flex-direction: column; gap: 8px;
  align-items: flex-start;
  padding: 18px 18px 16px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  text-align: left;
  cursor: pointer;
  transition: background 0.12s ease, border-color 0.12s ease, transform 0.06s ease;

  &:hover {
    background: rgb(var(--slate-3));
    border-color: rgb(var(--blue-8));
  }
  &:active { transform: translateY(1px); }
}
.rep-hub__card-icon {
  width: 22px; height: 22px;
  color: rgb(var(--blue-9));
  margin-bottom: 4px;
}
.rep-hub__card-title {
  font-size: 14px; font-weight: 600;
  color: rgb(var(--slate-12));
}
.rep-hub__card-subtitle {
  font-size: 12px; color: rgb(var(--slate-9));
  line-height: 1.4;
}

/* Detail view */
.rep-hub__detail-header {
  display: flex; align-items: center; gap: 12px;
  padding-bottom: 12px;
  border-bottom: 1px solid rgb(var(--slate-4));
  margin-bottom: 4px;
}
.rep-hub__detail-title {
  margin: 0;
  font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: inline-flex; align-items: center; gap: 8px;
  i { width: 18px; height: 18px; color: rgb(var(--blue-9)); }
}
</style>
