<script setup>
/**
 * DRE — v2.
 *
 * Demonstração do Resultado do Exercício em regime de competência.
 *
 * Bugs preservados:
 *   BUG-03: Var % nunca mostra valores absurdos — backend retorna string
 *           já tratada ("Novo", "—", "+5.4%").
 *   BUG-04: Aviso destacado quando há lançamentos sem categoria.
 *
 * UI premium:
 *   - Layout `.finv2-page` (scroll + sticky header).
 *   - Period selector com ícones de seta.
 *   - Sections com expand/collapse (details).
 *   - Resumo financeiro com hierarquia visual (indent + borda).
 *   - Mobile responsivo.
 */
import { ref, computed, onMounted, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

// Seletor de granularidade do período. 'all' usa janela ampla 2010→hoje
// pra cobrir histórico migrado (Clinicorp inclui dados desde jul/2023).
const PERIOD_TYPES = [
  { value: 'week',    label: 'Semana' },
  { value: 'month',   label: 'Mês' },
  { value: 'quarter', label: 'Trimestre' },
  { value: 'year',    label: 'Ano' },
  { value: 'all',     label: 'Todos' },
];

const periodType = ref('month');
const anchor = ref(new Date());
const data = ref(null);
const loading = ref(false);

const period = computed(() => buildPeriod(periodType.value, anchor.value));

function buildPeriod(type, date) {
  const y = date.getFullYear();
  const m = date.getMonth();
  if (type === 'all') {
    const today = new Date().toISOString().slice(0, 10);
    return { from: '2010-01-01', to: today, label: 'Todo o período' };
  }
  if (type === 'year') {
    return {
      from: `${y}-01-01`,
      to: `${y}-12-31`,
      label: String(y),
    };
  }
  if (type === 'quarter') {
    const q = Math.floor(m / 3);
    const firstMonth = q * 3;
    const first = new Date(y, firstMonth, 1).toISOString().slice(0, 10);
    const last = new Date(y, firstMonth + 3, 0).toISOString().slice(0, 10);
    return { from: first, to: last, label: `T${q + 1}/${y}` };
  }
  if (type === 'week') {
    // Semana ISO: segunda a domingo. JS getDay() retorna 0=domingo..6=sábado.
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

async function load() {
  loading.value = true;
  try {
    const { data: payload } = await FinancialV2.reports.dre({
      from: period.value.from,
      to: period.value.to,
    });
    data.value = payload;
  } finally {
    loading.value = false;
  }
}

watch(period, load, { deep: true });
onMounted(load);

function shift(delta) {
  if (periodType.value === 'all') return;
  const d = new Date(anchor.value);
  if (periodType.value === 'year') d.setFullYear(d.getFullYear() + delta);
  else if (periodType.value === 'quarter') d.setMonth(d.getMonth() + delta * 3);
  else if (periodType.value === 'week') d.setDate(d.getDate() + delta * 7);
  else d.setMonth(d.getMonth() + delta);
  anchor.value = d;
}

const summary = computed(() => data.value?.summary || {});
const sections = computed(() => data.value?.sections || []);
const uncategorized = computed(() => data.value?.uncategorized || { count: 0, amount_cents: 0 });

function varBadgeColor(label) {
  if (!label || label === '—') return 'slate';
  if (label === 'Novo') return 'amber';
  if (label.startsWith('+')) return 'emerald';
  if (label.startsWith('-') || label.startsWith('−')) return 'ruby';
  return 'slate';
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">DRE</h1>
        <p class="finv2-page__subtitle">
          Demonstração do Resultado do Exercício — regime competência (receita
          aparece quando o orçamento é aprovado, não quando o dinheiro entra).
        </p>
      </div>
      <div class="dre__period-group">
        <div class="dre__period-tabs" role="tablist">
          <button
            v-for="type in PERIOD_TYPES"
            :key="type.value"
            :class="['dre__period-tab', { 'dre__period-tab--active': periodType === type.value }]"
            type="button"
            @click="periodType = type.value"
          >
            {{ type.label }}
          </button>
        </div>
        <div class="dre__period">
          <BeclinicButton
            size="sm"
            variant="ghost"
            color="slate"
            icon="i-lucide-chevron-left"
            :disabled="periodType === 'all'"
            @click="shift(-1)"
          />
          <strong class="dre__period-label">{{ period.label }}</strong>
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
    </header>

    <div class="finv2-page__body">
      <!-- Aviso de não categorizados -->
      <div v-if="uncategorized.count > 0" class="dre__alert">
        <i class="i-lucide-alert-triangle w-5 h-5" />
        <div class="dre__alert-text">
          <strong>{{ uncategorized.count }} lançamento(s) sem categoria</strong>
          <small>
            {{ centsToBRL(uncategorized.amount_cents) }} sem classificação.
            Cadastre categorias e reclassifique para o DRE refletir corretamente.
          </small>
        </div>
        <router-link
          :to="{ name: 'financial_v2_reclassify' }"
          class="dre__alert-link"
        >
          Reclassificar
          <i class="i-lucide-arrow-right w-3.5 h-3.5" />
        </router-link>
      </div>

      <!-- Loading -->
      <div v-if="loading" class="finv2-state">
        <div class="finv2-spinner" />
        <span>Carregando DRE…</span>
      </div>

      <template v-else-if="data">
        <!-- Sections -->
        <div class="dre__sections">
          <details
            v-for="section in sections"
            :key="section.kind"
            class="dre__section"
            open
          >
            <summary class="dre__section-summary">
              <div class="dre__section-title">
                <i class="i-lucide-chevron-down dre__section-chevron" />
                <h2>{{ section.label }}</h2>
                <Badge
                  :label="section.var_label"
                  :color="varBadgeColor(section.var_label)"
                  size="xs"
                />
              </div>
              <strong class="dre__section-total">{{ centsToBRL(section.total_cents) }}</strong>
            </summary>

            <div class="finv2-table-wrap dre__section-table">
              <table class="finv2-table">
                <thead>
                  <tr>
                    <th>Categoria</th>
                    <th class="finv2-table__th-num">Atual</th>
                    <th class="finv2-table__th-num">Período anterior</th>
                    <th>Variação</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    v-for="cat in section.categories"
                    :key="cat.id || 'sem-cat'"
                    :class="{ 'dre__row--warn': cat.warning }"
                  >
                    <td>
                      <span v-if="cat.warning" class="dre__warn-icon">
                        <i class="i-lucide-alert-circle w-3.5 h-3.5" />
                      </span>
                      {{ cat.name }}
                    </td>
                    <td class="finv2-table__td-num finv2-table__td-num--strong">
                      {{ centsToBRL(cat.total_cents) }}
                    </td>
                    <td class="finv2-table__td-num finv2-table__td-muted">
                      {{ centsToBRL(cat.previous_total_cents) }}
                    </td>
                    <td>
                      <Badge
                        :label="cat.var_label"
                        :color="varBadgeColor(cat.var_label)"
                        size="xs"
                      />
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
          </details>
        </div>

        <!-- Resumo financeiro -->
        <section class="dre__summary">
          <h2 class="dre__summary-title">Resumo</h2>
          <ul class="dre__summary-list">
            <li class="dre__summary-row">
              <span>Receita Bruta</span>
              <strong>{{ centsToBRL(summary.receita_bruta_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--indent">
              <span>(–) Deduções</span>
              <strong class="dre__summary-row--negative-strong">{{ centsToBRL(summary.deducoes_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--equals">
              <span>= Receita Líquida</span>
              <strong>{{ centsToBRL(summary.receita_liquida_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--indent">
              <span>(–) Custos Variáveis</span>
              <strong class="dre__summary-row--negative-strong">{{ centsToBRL(summary.custos_variaveis_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--equals">
              <span>= Margem Bruta</span>
              <strong>{{ centsToBRL(summary.margem_bruta_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--indent">
              <span>(–) Despesas Fixas</span>
              <strong class="dre__summary-row--negative-strong">{{ centsToBRL(summary.despesas_fixas_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--equals">
              <span>= EBITDA</span>
              <strong>{{ centsToBRL(summary.ebitda_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--indent">
              <span>(–) Outras Despesas</span>
              <strong class="dre__summary-row--negative-strong">{{ centsToBRL(summary.outras_despesas_cents) }}</strong>
            </li>
            <li class="dre__summary-row dre__summary-row--total">
              <span>= Lucro Líquido</span>
              <strong>{{ centsToBRL(summary.lucro_liquido_cents) }}</strong>
            </li>
          </ul>
        </section>
      </template>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Layout, KPIs, table, badges e estados vêm do _layout.scss global. */

/* Os 2 containers (tabs e navegação) padronizados em 38px de altura pra ficarem
   alinhados visualmente. Tab ativo usa a brand color (--color-woot-500). */
$dre-period-h: 38px;

.dre__period-group {
  display: inline-flex; align-items: center; gap: 8px; flex-wrap: wrap;
}
.dre__period-tabs {
  display: inline-flex; align-items: center; gap: 2px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 3px;
  height: $dre-period-h;
  box-sizing: border-box;
}
.dre__period-tab {
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
.dre__period-tab--active {
  background: var(--w-500, #1f93ff);
  color: #fff;
  &:hover {
    background: var(--w-600, #0e7be0);
    color: #fff;
  }
}
:root.dark .dre__period-tab--active {
  background: var(--w-500, #1f93ff);
  color: #fff;
  &:hover { background: var(--w-600, #0e7be0); }
}
.dre__period {
  display: inline-flex; align-items: center; gap: 4px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  padding: 3px 6px;
  height: $dre-period-h;
  box-sizing: border-box;
}
.dre__period-label {
  font-size: 14px; font-weight: 600; color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
  min-width: 150px; text-align: center;
  padding: 0 4px;
}

@media (max-width: 640px) {
  .dre__period-group { width: 100%; justify-content: space-between; }
  .dre__period-tabs { flex: 1; justify-content: space-between; }
  .dre__period-tab { flex: 1; padding: 0 4px; font-size: 11.5px; }
  .dre__period-label { min-width: 100px; font-size: 13px; }
}

/* ── Aviso de não categorizados ─────────────────────────────── */
.dre__alert {
  display: flex; align-items: flex-start; gap: 12px;
  padding: 12px 14px;
  background: rgba(245, 158, 11, 0.10);
  border-left: 3px solid #f59e0b;
  border-radius: 10px;
  i { color: #d97706; flex-shrink: 0; margin-top: 1px; }
}
:root.dark .dre__alert i { color: #fcd34d; }
.dre__alert-text {
  flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 2px;
  strong { color: rgb(var(--slate-12)); font-weight: 600; font-size: 13.5px; }
  small  { color: rgb(var(--slate-11)); font-size: 12px; line-height: 1.5; }
}
.dre__alert-link {
  display: inline-flex; align-items: center; gap: 4px; flex-shrink: 0;
  font-size: 12.5px; font-weight: 500;
  color: #b45309; text-decoration: none;
  &:hover { color: #92400e; text-decoration: underline; }
}
:root.dark .dre__alert-link { color: #fcd34d;
  &:hover { color: #fef3c7; }
}

/* ── Sections (collapsible) ─────────────────────────────────── */
.dre__sections { display: flex; flex-direction: column; gap: 12px; }
.dre__section {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  overflow: hidden;
}
.dre__section-summary {
  list-style: none;
  display: flex; justify-content: space-between; align-items: center;
  padding: 14px 16px;
  cursor: pointer;
  user-select: none;
  transition: background 0.12s ease;
  &:hover { background: rgb(var(--slate-3) / 0.5); }
  &::-webkit-details-marker { display: none; }
}
.dre__section-title { display: flex; align-items: center; gap: 8px;
  h2 { margin: 0; font-size: 15px; font-weight: 600; color: rgb(var(--slate-12)); }
}
.dre__section-chevron {
  width: 16px; height: 16px;
  color: rgb(var(--slate-9));
  transition: transform 0.2s ease;
}
.dre__section[open] .dre__section-chevron { transform: rotate(180deg); }
.dre__section-total {
  font-size: 16px; font-weight: 600; color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
.dre__section-table {
  border: 0; border-top: 1px solid rgb(var(--slate-4));
  border-radius: 0;
}

/* Linha com warning (sem categoria) */
.dre__row--warn td:first-child {
  color: #b45309; font-weight: 600;
}
:root.dark .dre__row--warn td:first-child { color: #fcd34d; }
.dre__warn-icon {
  display: inline-flex; align-items: center;
  margin-right: 6px;
  color: #d97706;
}

/* ── Resumo ─────────────────────────────────────────────────── */
.dre__summary {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  padding: 16px 18px;
}
.dre__summary-title {
  margin: 0 0 12px;
  font-size: 11px; text-transform: uppercase; letter-spacing: 0.06em;
  color: rgb(var(--slate-9)); font-weight: 600;
}
.dre__summary-list {
  list-style: none; padding: 0; margin: 0;
  display: flex; flex-direction: column; gap: 6px;
}
.dre__summary-row {
  display: flex; justify-content: space-between; align-items: center;
  font-size: 13.5px; color: rgb(var(--slate-11));
  strong {
    color: rgb(var(--slate-12)); font-weight: 600;
    font-variant-numeric: tabular-nums;
  }
}
.dre__summary-row--indent {
  padding-left: 16px;
  font-size: 13px;
  color: rgb(var(--slate-9));
}
.dre__summary-row--negative-strong { color: #b91c1c !important; }
:root.dark .dre__summary-row--negative-strong { color: #fca5a5 !important; }
.dre__summary-row--equals {
  padding-top: 4px;
  border-top: 1px dashed rgb(var(--slate-5));
  span { font-weight: 500; color: rgb(var(--slate-12)); }
}
.dre__summary-row--total {
  padding-top: 10px; margin-top: 4px;
  border-top: 2px solid rgb(var(--slate-7));
  font-size: 16px; font-weight: 600;
  span { color: rgb(var(--slate-12)); }
  strong { font-size: 18px; color: #047857; }
}
:root.dark .dre__summary-row--total strong { color: #6ee7b7; }
</style>
