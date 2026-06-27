<script setup>
/**
 * Tab "Procedimentos e Serviços" — wireframe 2026-05-23.
 *
 * Lista TODOS os AgendaServices cadastrados em /agenda/settings (não muda
 * lá), mostrando precificação financeira + estatísticas históricas:
 *
 *   CÓDIGO | NOME + REAL | CATEGORIA | PREÇO | HIST. QTD | FAIXA REAL | DURAÇÃO | STATUS | AÇÕES
 *
 * Stats agregados em batch pelo backend (sem N+1) via Budget aprovados/concluídos.
 *
 * Endpoint da Fase 2A (com stats da Fase 2B-procedimentos):
 *   GET /financial/v2/service_pricings → [{code, agenda_service, pricing, stats}]
 *   PUT /financial/v2/service_pricings/:agenda_service_id (upsert)
 *   DELETE /financial/v2/service_pricings/:agenda_service_id (deactivate)
 */
import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FinancialV2 from '../../api/financialV2';
import ServicePricingFormModalV2 from './ServicePricingFormModalV2.vue';

const route = useRoute();
const router = useRouter();

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const items = ref([]);  // [{ code, agenda_service, pricing, stats }]
const dreCategories = ref([]);
const loading = ref(false);
const errorState = ref(null);

const showModal = ref(false);
const modalAgendaService = ref(null);
const modalExistingPricing = ref(null);

async function load() {
  loading.value = true;
  errorState.value = null;
  try {
    const [pricingsRes, categoriesRes] = await Promise.all([
      FinancialV2.servicePricings.index(),
      FinancialV2.categories.index({ include_system: 'true' }),
    ]);
    items.value = pricingsRes?.data?.data || [];
    dreCategories.value = categoriesRes?.data?.data || [];
  } catch (err) {
    errorState.value = err?.response?.data?.message || 'Erro ao carregar serviços';
    notifyError(errorState.value);
  } finally {
    loading.value = false;
  }
}

// Deep-link `?service_id=<id>` (vindo de Agenda > Serviços) abre o modal
// de pricing automático pro serviço solicitado. Após abrir, limpa o query
// param pra não reabrir em refresh acidental.
async function handleDeepLink() {
  const targetId = Number(route.query.service_id);
  if (!targetId) return;

  // Espera os items carregarem
  await nextTick();
  const target = items.value.find(i => i.agenda_service?.id === targetId);
  if (target) {
    openModalFor(target.agenda_service, target.pricing);
  }

  // Remove o query param pra não reabrir em F5
  const { service_id, ...rest } = route.query;
  router.replace({ query: rest });
}

onMounted(async () => {
  await load();
  await handleDeepLink();
});

watch(() => route.query.service_id, handleDeepLink);

// ── Categorização visual ─────────────────────────────────────────────
const itemsWithPricing = computed(() => items.value.filter(i => i.pricing));
const itemsWithoutPricing = computed(() => items.value.filter(i => !i.pricing));

// ── Formato wireframe da categoria: "rec-particular::Endodontia" ─────
// Decompõe path L1/L2/L3 em prefix curto (rec/exp) + contexto + nome.
function categoryShortLabel(categoryId) {
  if (!categoryId) return '—';
  const cat = dreCategories.value.find(c => c.id === categoryId);
  if (!cat) return `#${categoryId}`;
  if (!cat.path) return cat.name;

  const ids = cat.path.split('/').filter(Boolean).map(Number);
  const ancestors = ids
    .map(id => dreCategories.value.find(c => c.id === id))
    .filter(Boolean);

  if (ancestors.length === 0) return cat.name;

  const root = ancestors[0];
  const subgroup = ancestors[1];

  // Prefixo curto baseado em root + subgrupo
  let prefix = root.kind === 'receita' ? 'rec' : 'exp';
  if (subgroup) {
    const sub = subgroup.name.toLowerCase();
    if (sub.includes('particular')) prefix += '-particular';
    else if (sub.includes('convênio') || sub.includes('convenio')) prefix += '-convenio';
    else if (sub.includes('pacote')) prefix += '-pacote';
    else if (sub.includes('outras')) prefix += '-outras';
  }

  return `${prefix}::${cat.name}`;
}

// Full path (mostrado em tooltip — operador vê hierarquia completa ao hover)
function categoryFullPath(categoryId) {
  if (!categoryId) return '';
  const cat = dreCategories.value.find(c => c.id === categoryId);
  if (!cat?.path) return cat?.name || '';
  const ids = cat.path.split('/').filter(Boolean).map(Number);
  return ids
    .map(id => dreCategories.value.find(c => c.id === id)?.name)
    .filter(Boolean)
    .join(' › ');
}

function formatBRL(cents) {
  if (cents == null) return '—';
  return (cents / 100).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });
}

function formatBRLShort(cents) {
  if (cents == null) return '—';
  // Mostra "R$ 7.863" (sem centavos quando inteiro) pro layout compacto
  const v = cents / 100;
  if (Number.isInteger(v)) {
    return 'R$ ' + v.toLocaleString('pt-BR');
  }
  return 'R$ ' + v.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function formatPriceRange(item) {
  if (!item.stats?.has_real_data) return '—';
  const min = item.stats.price_min_cents;
  const max = item.stats.price_max_cents;
  if (min == null || max == null) return '—';
  if (min === max) return formatBRLShort(min);
  return `${formatBRLShort(min)} – ${formatBRLShort(max)}`;
}

function formatQty(qty) {
  if (!qty || qty === 0) return '—';
  return qty.toLocaleString('pt-BR');
}

function formatDuration(minutes) {
  if (!minutes) return '—';
  return `${minutes}min`;
}

// ── Ações ─────────────────────────────────────────────────────────────
function openModalFor(agendaService, pricing = null) {
  modalAgendaService.value = agendaService;
  modalExistingPricing.value = pricing;
  showModal.value = true;
}

function onPricingSaved() {
  load();
}

// Quando o modal cria uma nova DreCategory inline, adiciona ela ao
// `dreCategories` local pra que o dropdown reativo "veja" imediatamente.
// Sem reload full — só inserção + ordenação por path.
function onCategoryCreated(newCategory) {
  if (!newCategory?.id) return;
  // De-dup: se por acaso já estiver na lista (race condition), substitui
  const idx = dreCategories.value.findIndex(c => c.id === newCategory.id);
  if (idx >= 0) {
    dreCategories.value[idx] = newCategory;
  } else {
    dreCategories.value = [...dreCategories.value, newCategory]
      .sort((a, b) => (a.path || '').localeCompare(b.path || ''));
  }
}

async function onPricingDeactivate({ agendaServiceId }) {
  try {
    await FinancialV2.servicePricings.deactivate(agendaServiceId);
    notifySuccess('Pricing removido. Serviço permanece na agenda.');
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Erro ao remover');
  }
}
</script>

<template>
  <div class="proctab">
    <header class="proctab-header">
      <div>
        <h2 class="proctab-title">Procedimentos e Serviços</h2>
        <p class="proctab-subtitle">
          Setup #6 · Catálogo clínico. Preço, categoria DRE e estatísticas históricas
          dos serviços cadastrados em <strong>Agenda &gt; Serviços</strong>.
        </p>
      </div>
    </header>

    <!-- Loading -->
    <div v-if="loading && items.length === 0" class="proctab-loading">
      <div class="proctab-spinner" />
      <span>Carregando procedimentos...</span>
    </div>

    <!-- Error -->
    <div v-else-if="errorState" class="proctab-error">
      <i class="i-lucide-alert-circle" />
      <div>
        <strong>Não foi possível carregar.</strong>
        <p>{{ errorState }}</p>
      </div>
      <BeclinicButton variant="ghost" color="slate" label="Tentar de novo" @click="load" />
    </div>

    <!-- Empty -->
    <div v-else-if="items.length === 0" class="proctab-empty">
      <i class="i-lucide-package-x" />
      <h3>Nenhum procedimento cadastrado</h3>
      <p>
        Os serviços são cadastrados em <strong>Agenda &gt; Configurações &gt; Serviços</strong>.
        Depois volte aqui pra configurar preço, categoria DRE e ver estatísticas.
      </p>
    </div>

    <!-- Conteúdo -->
    <div v-else class="proctab-content">
      <!-- Banner: sem precificação -->
      <div v-if="itemsWithoutPricing.length > 0" class="proctab-banner proctab-banner--warn">
        <i class="i-lucide-alert-triangle" />
        <div>
          <strong>
            {{ itemsWithoutPricing.length }} procedimento(s) sem precificação.
          </strong>
          <p>Esses procedimentos ainda não têm <strong>preço configurado</strong> no financeiro. Configure cada um para registrar o valor padrão do serviço.</p>
        </div>
      </div>

      <!-- Tabela -->
      <div class="proctab-table-wrap">
        <table class="proctab-table">
          <thead>
            <tr>
              <th class="proctab-th-code">CÓDIGO</th>
              <th class="proctab-th-name">NOME</th>
              <th class="proctab-th-category">CATEGORIA</th>
              <th class="proctab-th-price">PREÇO ATUAL</th>
              <th class="proctab-th-hist">HISTÓRICO (QTD)</th>
              <th class="proctab-th-range">FAIXA REAL</th>
              <th class="proctab-th-dur">DURAÇÃO</th>
              <th class="proctab-th-status">STATUS</th>
              <th class="proctab-th-actions"></th>
            </tr>
          </thead>
          <tbody>
            <!-- SEM pricing primeiro (chamado à ação) -->
            <tr v-for="item in itemsWithoutPricing" :key="`empty-${item.agenda_service.id}`" class="proctab-row proctab-row--warn">
              <td class="proctab-td-code">
                <div class="proctab-code-stack">
                  <span class="proctab-code-seq">{{ item.code }}</span>
                  <span class="proctab-code-ref" :title="`Mesmo serviço em Agenda > Serviços: ID #${item.agenda_service.id}`">
                    #{{ item.agenda_service.id }}
                  </span>
                </div>
              </td>
              <td class="proctab-td-name">
                <span class="proctab-color-dot" :style="{ background: item.agenda_service.color || '#94a3b8' }" />
                <span class="proctab-name-text">{{ item.agenda_service.name }}</span>
                <span v-if="item.stats?.has_real_data" class="proctab-badge proctab-badge--real">REAL</span>
              </td>
              <td class="proctab-td-category">
                <span class="proctab-missing">não configurada</span>
              </td>
              <td class="proctab-td-price">—</td>
              <td class="proctab-td-hist">{{ formatQty(item.stats?.historical_qty) }}</td>
              <td class="proctab-td-range">—</td>
              <td class="proctab-td-dur">{{ formatDuration(item.agenda_service.duration_minutes) }}</td>
              <td class="proctab-td-status">
                <span class="proctab-status proctab-status--warn">⚠ Configurar</span>
              </td>
              <td class="proctab-td-actions">
                <BeclinicButton
                  variant="solid"
                  color="blue"
                  size="sm"
                  icon="i-lucide-plus"
                  label="Configurar"
                  @click="openModalFor(item.agenda_service)"
                />
              </td>
            </tr>

            <!-- Com pricing configurado -->
            <tr v-for="item in itemsWithPricing" :key="`ok-${item.agenda_service.id}`" class="proctab-row">
              <td class="proctab-td-code">
                <div class="proctab-code-stack">
                  <span class="proctab-code-seq">{{ item.code }}</span>
                  <span class="proctab-code-ref" :title="`Mesmo serviço em Agenda > Serviços: ID #${item.agenda_service.id}`">
                    #{{ item.agenda_service.id }}
                  </span>
                </div>
              </td>
              <td class="proctab-td-name">
                <span class="proctab-color-dot" :style="{ background: item.agenda_service.color || '#94a3b8' }" />
                <span class="proctab-name-text">{{ item.agenda_service.name }}</span>
                <span v-if="item.stats?.has_real_data" class="proctab-badge proctab-badge--real">REAL</span>
              </td>
              <td class="proctab-td-category">
                <span class="proctab-category-short"
                      :title="categoryFullPath(item.pricing.financial_dre_category_id)">
                  {{ categoryShortLabel(item.pricing.financial_dre_category_id) }}
                </span>
              </td>
              <td class="proctab-td-price">{{ formatBRLShort(item.pricing.particular_price_cents) }}</td>
              <td class="proctab-td-hist">{{ formatQty(item.stats?.historical_qty) }}</td>
              <td class="proctab-td-range">{{ formatPriceRange(item) }}</td>
              <td class="proctab-td-dur">{{ formatDuration(item.agenda_service.duration_minutes) }}</td>
              <td class="proctab-td-status">
                <span class="proctab-status"
                      :class="item.pricing.status === 'active' ? 'proctab-status--ok' : 'proctab-status--inactive'">
                  {{ item.pricing.status === 'active' ? 'ATIVO' : 'INATIVO' }}
                </span>
              </td>
              <td class="proctab-td-actions" @click.stop>
                <Tooltip label="Editar preço" position="left">
                  <button
                    type="button"
                    class="proctab-icon-btn"
                    aria-label="Editar preço"
                    @click.stop="openModalFor(item.agenda_service, item.pricing)"
                  >
                    <i class="i-lucide-pencil" />
                  </button>
                </Tooltip>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Modal -->
    <ServicePricingFormModalV2
      v-if="modalAgendaService"
      :show="showModal"
      :agenda-service="modalAgendaService"
      :existing-pricing="modalExistingPricing"
      :dre-categories="dreCategories"
      @close="showModal = false"
      @confirm="onPricingSaved"
      @deactivate="onPricingDeactivate"
      @category-created="onCategoryCreated"
    />
  </div>
</template>

<style scoped lang="scss">
.proctab {
  /* Padding agora vem do `.finset__main` do parent (SettingsV2).
     Sem padding aqui pra evitar duplicação. */
  color: rgb(var(--slate-12));
}

.proctab-header {
  margin-bottom: 20px;
  padding-bottom: 16px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.proctab-title {
  margin: 0 0 6px;
  font-size: 22px;
  font-weight: 700;
}
.proctab-subtitle {
  margin: 0;
  font-size: 13px;
  color: rgb(var(--slate-10));
  line-height: 1.5;
  max-width: 760px;
}

.proctab-loading, .proctab-empty, .proctab-error {
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 80px 24px;
  text-align: center;
  color: rgb(var(--slate-9));
  font-size: 14px;
  gap: 12px;
}
.proctab-loading { flex-direction: row; }
.proctab-empty, .proctab-error {
  flex-direction: column;
  i { width: 32px; height: 32px; color: rgb(var(--slate-7)); }
  h3 { margin: 0; font-size: 16px; color: rgb(var(--slate-11)); }
  p { margin: 4px 0 0; max-width: 480px; font-size: 13px; }
}
.proctab-error { color: rgb(var(--ruby-10)); }

.proctab-spinner {
  width: 18px;
  height: 18px;
  border: 2px solid rgb(var(--slate-5));
  border-top-color: rgb(var(--blue-9));
  border-radius: 50%;
  animation: spin 0.8s linear infinite;
}
@keyframes spin { to { transform: rotate(360deg); } }

.proctab-content {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.proctab-banner {
  display: flex;
  gap: 12px;
  padding: 12px 16px;
  border-radius: 10px;
  align-items: flex-start;

  &--warn {
    background: rgba(245, 158, 11, 0.08);
    border-left: 3px solid rgb(var(--amber-8));
    color: rgb(var(--amber-11));
    i { width: 20px; height: 20px; color: rgb(var(--amber-10)); flex-shrink: 0; margin-top: 2px; }
    strong { color: rgb(var(--amber-12)); }
    p { margin: 4px 0 0; font-size: 13px; color: rgb(var(--slate-11)); }
  }
}

.proctab-table-wrap {
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  background: rgb(var(--slate-1));
  overflow-x: auto;
}

.proctab-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 900px;

  thead {
    background: rgb(var(--slate-2));
    th {
      padding: 10px 12px;
      text-align: left;
      font-size: 10px;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: rgb(var(--slate-10));
      border-bottom: 1px solid rgb(var(--slate-4));
      white-space: nowrap;
    }
  }

  tbody {
    tr {
      border-bottom: 1px solid rgb(var(--slate-3));
      transition: background-color .12s ease;
      &:last-child { border-bottom: 0; }
      &:hover { background: rgba(255, 255, 255, 0.02); }

      &.proctab-row--warn {
        background: rgba(245, 158, 11, 0.04);
        &:hover { background: rgba(245, 158, 11, 0.08); }
      }
    }

    td {
      padding: 10px 12px;
      vertical-align: middle;
    }
  }
}

/* Larguras das colunas */
.proctab-th-code, .proctab-td-code {
  width: 88px;
  font-variant-numeric: tabular-nums;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  color: rgb(var(--slate-9));
  font-size: 12px;
}
/* Stack do CÓDIGO: sequencial em destaque + ID Agenda em tom muted como
   cross-reference. Resolve a confusão "001 vs # 2109" — mesmo serviço,
   identificadores diferentes (interno financeiro × DB key da Agenda). */
.proctab-code-stack {
  display: flex; flex-direction: column; gap: 1px; line-height: 1.2;
}
.proctab-code-seq {
  color: rgb(var(--slate-12)); font-weight: 600;
}
.proctab-code-ref {
  color: rgb(var(--slate-8));
  font-size: 10.5px;
  cursor: help;
}
.proctab-th-name, .proctab-td-name { min-width: 260px; }
.proctab-th-category, .proctab-td-category { min-width: 200px; }
.proctab-th-price, .proctab-td-price {
  width: 120px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.proctab-th-hist, .proctab-td-hist {
  width: 110px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-11));
}
.proctab-th-range, .proctab-td-range {
  width: 140px;
  text-align: right;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-11));
  font-size: 12px;
}
.proctab-th-dur, .proctab-td-dur {
  width: 80px;
  text-align: center;
  color: rgb(var(--slate-10));
  font-variant-numeric: tabular-nums;
  font-size: 12px;
}
.proctab-th-status, .proctab-td-status { width: 130px; }
.proctab-th-actions, .proctab-td-actions { width: 1%; white-space: nowrap; text-align: right; }

.proctab-td-name {
  display: flex;
  align-items: center;
  gap: 8px;
}
.proctab-color-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  flex-shrink: 0;
}
.proctab-name-text {
  font-weight: 500;
  color: rgb(var(--slate-12));
}

.proctab-badge {
  display: inline-block;
  padding: 1px 6px;
  border-radius: 4px;
  font-size: 9px;
  font-weight: 700;
  letter-spacing: 0.05em;
  text-transform: uppercase;

  &--real {
    background: rgba(16, 185, 129, 0.15);
    color: rgb(var(--emerald-11));
  }
}

.proctab-category-short {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 11px;
  color: rgb(var(--slate-10));
  cursor: help;
}
.proctab-missing {
  color: rgb(var(--amber-10));
  font-size: 11px;
  font-style: italic;
}

/* Botão de ação em ícone (editar) — mesmo padrão de Contas Bancárias /
   Formas de Pagamento (substitui o botão "Inativar" em texto). */
.proctab-icon-btn {
  width: 28px; height: 28px;
  padding: 0; margin: 0;
  display: inline-flex; align-items: center; justify-content: center;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 6px;
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition: background-color 0.12s ease, color 0.12s ease, border-color 0.12s ease;
  i { width: 14px; height: 14px; }

  &:hover {
    background: rgb(var(--slate-3));
    color: rgb(var(--blue-11));
    border-color: rgb(var(--slate-4));
  }
}

.proctab-status {
  display: inline-block;
  padding: 2px 8px;
  border-radius: 4px;
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.05em;
  /* nowrap impede quebra do "⚠ Configurar" em 2 linhas quando a coluna
     está apertada. Combinado com width=130px na coluna, dá folga
     suficiente sem desperdiçar espaço. */
  white-space: nowrap;

  &--ok {
    background: rgba(16, 185, 129, 0.15);
    color: rgb(var(--emerald-11));
  }
  &--inactive {
    background: rgba(100, 116, 139, 0.15);
    color: rgb(var(--slate-10));
  }
  &--warn {
    background: rgba(245, 158, 11, 0.15);
    color: rgb(var(--amber-11));
  }
}
</style>
