<script setup>
/**
 * Comissões — v2 (canon F-29).
 *
 * Apuração de comissões por profissional dentro de um período. Mostra
 * KPIs (devida / paga / estornada / líquida), tabela agrupada por
 * profissional com acordeão expandindo as linhas individuais. Botão
 * "Marcar como pago" por linha → cria Expense em A Pagar (PayCommission
 * service no backend).
 *
 * Estornos aparecem com sinal negativo (canon F-29 §critérios).
 *
 * Permissões:
 *   • GERENTE/ADMIN/AUDITOR veem todos os profissionais.
 *   • DENTIST vê apenas as próprias (validado no backend).
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import '@plugins/financial/frontend/styles/financial.scss';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const report = ref({ summary: {}, professionals: [] });
const loading = ref(false);
const professionals = ref([]); // lista p/ filtro

// Default = mês corrente (canon: período padrão é o mês vigente)
const todayISO = () => new Date().toISOString().slice(0, 10);
function startOfMonthISO() {
  const d = new Date(); d.setDate(1);
  return d.toISOString().slice(0, 10);
}
function endOfMonthISO() {
  const d = new Date();
  const end = new Date(d.getFullYear(), d.getMonth() + 1, 0);
  return end.toISOString().slice(0, 10);
}

const filters = ref({
  from: startOfMonthISO(),
  to: endOfMonthISO(),
  professional_id: '',
});

// Expansão por profissional (acordeão).
const expanded = ref({});
function toggleExpanded(profId) {
  expanded.value[profId] = !expanded.value[profId];
}

const professionalOptions = computed(() => {
  const opts = [{ value: '', label: 'Todos os profissionais' }];
  professionals.value.forEach(p => {
    if (p?.id) opts.push({ value: p.id, label: p.name || `Profissional #${p.id}` });
  });
  return opts;
});

const summary = computed(() => report.value?.summary || {});

async function load() {
  loading.value = true;
  try {
    const params = { from: filters.value.from, to: filters.value.to };
    if (filters.value.professional_id) params.professional_id = filters.value.professional_id;
    const { data } = await FinancialV2.reports.commissions(params);
    report.value = data || { summary: {}, professionals: [] };
    // Pre-expand single result pra UX limpa.
    if (report.value.professionals?.length === 1) {
      expanded.value[report.value.professionals[0].id] = true;
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[CommissionsV2] load error', err);
    notifyError(err?.response?.data?.error || 'Falha ao carregar relatório de comissões.');
  } finally {
    loading.value = false;
  }
}

// Carrega lista de profissionais — extraídos do backend via algumas
// fontes possíveis. Como a lista vem da CommissionRule, usamos o endpoint
// de regras pra descobrir profissionais com regra cadastrada.
async function loadProfessionals() {
  try {
    const { data } = await FinancialV2.commissionRules.index({ active: 'true' });
    const list = data?.data || [];
    const seen = new Set();
    professionals.value = list
      .map(r => r.professional)
      .filter(p => p && !seen.has(p.id) && seen.add(p.id));
  } catch {
    professionals.value = [];
  }
}

watch(filters, load, { deep: true });
onMounted(() => { load(); loadProfessionals(); });

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

function formatPercent(basisPoints) {
  if (basisPoints == null) return '—';
  return `${(basisPoints / 100).toFixed(basisPoints % 100 === 0 ? 0 : 2)}%`;
}

const STATUS_TONE = {
  devida:    { color: 'amber',   icon: 'i-lucide-clock' },
  paga:      { color: 'emerald', icon: 'i-lucide-check-circle-2' },
  estornada: { color: 'violet',  icon: 'i-lucide-undo' },
};
function statusBadge(s) {
  return STATUS_TONE[s] || { color: 'slate', icon: 'i-lucide-circle' };
}

// Marcar como pago — modal de confirmação + PayCommission service.
const showPayModal = ref(false);
const entryToPay = ref(null);
const paying = ref(false);

function openPay(entry, professionalName) {
  entryToPay.value = { ...entry, _professional_name: professionalName };
  showPayModal.value = true;
}

async function confirmPay() {
  const entry = entryToPay.value;
  if (!entry) return;
  paying.value = true;
  try {
    await FinancialV2.commissionEntries.pay(entry.id);
    notifySuccess('Comissão marcada como paga. Despesa criada em A Pagar.');
    showPayModal.value = false;
    entryToPay.value = null;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao marcar como paga.');
  } finally {
    paying.value = false;
  }
}

const hasFilter = computed(() =>
  filters.value.professional_id || filters.value.from || filters.value.to,
);

function resetFilters() {
  filters.value = {
    from: startOfMonthISO(),
    to: endOfMonthISO(),
    professional_id: '',
  };
}
</script>

<template>
  <div class="finv2-page">
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Comissões</h1>
        <p class="finv2-page__subtitle">
          Apuração por profissional. Estornos aparecem com sinal negativo.
          Marcar como pago gera despesa em <strong>A Pagar</strong> com categoria Comissões.
        </p>
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- KPIs -->
      <div class="finv2-kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-clock w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Devida</span>
            <strong class="finv2-kpi__value">{{ centsToBRL(summary.total_due_cents || 0) }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--positive">
            <i class="i-lucide-check-circle-2 w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Paga</span>
            <strong class="finv2-kpi__value finv2-kpi__value--positive">
              {{ centsToBRL(summary.total_paid_cents || 0) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger">
            <i class="i-lucide-undo w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Estornada</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ centsToBRL(summary.total_reversed_cents || 0) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-scale w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total líquido</span>
            <strong
              class="finv2-kpi__value"
              :class="(summary.total_net_cents || 0) >= 0
                ? 'finv2-kpi__value--positive'
                : 'finv2-kpi__value--danger'"
            >
              {{ centsToBRL(summary.total_net_cents || 0) }}
            </strong>
          </div>
        </div>
      </div>

      <!-- Filtros -->
      <div class="com-v2__filters">
        <div class="com-v2__filter com-v2__filter--grow">
          <FormSelect
            v-model="filters.professional_id"
            :options="professionalOptions"
            placeholder="Todos os profissionais"
            searchable
            auto-searchable
          />
        </div>
        <div class="com-v2__filter com-v2__filter--date">
          <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
        </div>
        <div class="com-v2__filter com-v2__filter--date">
          <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
        </div>
        <button v-if="hasFilter" type="button" class="com-v2__clear" @click="resetFilters">
          <i class="i-lucide-x w-3.5 h-3.5" /> Limpar
        </button>
      </div>

      <!-- Lista -->
      <div v-if="loading" class="finv2-state">
        <div class="finv2-spinner" /><span>Carregando…</span>
      </div>
      <div
        v-else-if="!report.professionals || report.professionals.length === 0"
        class="finv2-state"
      >
        <div class="finv2-state__icon-wrap">
          <i class="i-lucide-percent w-7 h-7" />
        </div>
        <p class="finv2-state__title">Nenhuma comissão no período</p>
        <p class="finv2-state__hint">
          Ajuste o intervalo de datas ou selecione outro profissional.
        </p>
      </div>

      <div v-else class="com-v2__list">
        <article
          v-for="prof in report.professionals"
          :key="prof.id"
          class="com-v2__group"
          :class="{ 'com-v2__group--expanded': expanded[prof.id] }"
        >
          <header
            class="com-v2__group-header"
            role="button"
            tabindex="0"
            @click="toggleExpanded(prof.id)"
            @keydown.enter="toggleExpanded(prof.id)"
            @keydown.space.prevent="toggleExpanded(prof.id)"
          >
            <div class="com-v2__group-prof">
              <ProfessionalChip
                :name="prof.name"
                :avatar-url="prof.avatar_url || ''"
                size="sm"
              />
              <span class="com-v2__group-meta">
                {{ prof.entries_count }}
                {{ prof.entries_count === 1 ? 'lançamento' : 'lançamentos' }}
              </span>
            </div>
            <div class="com-v2__group-totals">
              <div class="com-v2__total-pill com-v2__total-pill--due">
                <span class="com-v2__total-label">Devida</span>
                <strong>{{ centsToBRL(prof.totals.due_cents) }}</strong>
              </div>
              <div class="com-v2__total-pill com-v2__total-pill--paid">
                <span class="com-v2__total-label">Paga</span>
                <strong>{{ centsToBRL(prof.totals.paid_cents) }}</strong>
              </div>
              <div
                v-if="prof.totals.reversed_cents > 0"
                class="com-v2__total-pill com-v2__total-pill--reversed"
              >
                <span class="com-v2__total-label">Estornada</span>
                <strong>− {{ centsToBRL(prof.totals.reversed_cents) }}</strong>
              </div>
              <div class="com-v2__total-pill com-v2__total-pill--net">
                <span class="com-v2__total-label">Líquido</span>
                <strong
                  :class="prof.totals.net_cents >= 0
                    ? 'com-v2__net--positive'
                    : 'com-v2__net--negative'"
                >
                  {{ centsToBRL(prof.totals.net_cents) }}
                </strong>
              </div>
            </div>
            <i
              class="com-v2__chevron"
              :class="expanded[prof.id] ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
            />
          </header>

          <transition name="com-v2__expand">
            <div v-if="expanded[prof.id]" class="com-v2__entries">
              <div class="finv2-table-wrap">
                <table class="finv2-table">
                  <thead>
                    <tr>
                      <th>Status</th>
                      <th>Recebimento</th>
                      <th>Paciente</th>
                      <th>Procedimento</th>
                      <th class="finv2-table__th-num">Valor recebido</th>
                      <th class="finv2-table__th-num">% / base</th>
                      <th class="finv2-table__th-num">Comissão</th>
                      <th class="com-v2__th-actions">Ações</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="e in prof.entries" :key="e.id">
                      <td>
                        <Badge
                          :label="e.status_label"
                          :color="statusBadge(e.status).color"
                          :icon="statusBadge(e.status).icon"
                          size="xs"
                        />
                      </td>
                      <td>
                        <div class="com-v2__cell-stack">
                          <strong>{{ formatDateBR(e.competence_date) }}</strong>
                          <span v-if="e.payment_receipt?.receipt_number" class="com-v2__cell-hint">
                            {{ e.payment_receipt.receipt_number }}
                          </span>
                        </div>
                      </td>
                      <td>
                        <ProfessionalChip
                          v-if="e.patient?.name"
                          :name="e.patient.name"
                          :avatar-url="e.patient.avatar_url || ''"
                          size="sm"
                        />
                        <span v-else class="finv2-table__td-muted">—</span>
                      </td>
                      <td class="finv2-table__td-muted">
                        {{ e.procedure_name || '—' }}
                      </td>
                      <td class="finv2-table__td-num">
                        {{ centsToBRL(e.payment_receipt?.net_amount_cents || e.base_amount_cents) }}
                      </td>
                      <td class="finv2-table__td-num">
                        <div class="com-v2__cell-stack com-v2__cell-stack--right">
                          <strong>{{ formatPercent(e.percent_basis_points) }}</strong>
                          <span class="com-v2__cell-hint">
                            sobre {{ centsToBRL(e.calc_base_cents) }}
                          </span>
                        </div>
                      </td>
                      <td
                        class="finv2-table__td-num finv2-table__td-num--strong"
                        :class="e.signed_amount_cents < 0 ? 'com-v2__amount--negative' : ''"
                      >
                        {{ e.signed_amount_cents < 0 ? '−' : '' }}
                        {{ centsToBRL(Math.abs(e.signed_amount_cents)) }}
                      </td>
                      <td class="com-v2__td-actions">
                        <Tooltip v-if="e.status === 'devida'" label="Marcar como paga">
                          <BeclinicButton
                            size="xs"
                            variant="ghost"
                            color="teal"
                            icon="i-lucide-check"
                            @click="openPay(e, prof.name)"
                          />
                        </Tooltip>
                        <Tooltip
                          v-else-if="e.status === 'paga' && e.expense_id"
                          :label="'Despesa #' + e.expense_id + ' — gerencie em A Pagar'"
                        >
                          <i class="i-lucide-receipt w-3.5 h-3.5 com-v2__icon-muted" />
                        </Tooltip>
                        <span v-else class="finv2-table__td-muted">—</span>
                      </td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </transition>
        </article>
      </div>
    </div>

    <!-- Confirmação de "marcar como pago" -->
    <ConfirmDangerModal
      v-model:show="showPayModal"
      title="Marcar comissão como paga?"
      :message="entryToPay
        ? `Será criada uma despesa em A Pagar de ${centsToBRL(entryToPay.commission_amount_cents)} para ${entryToPay._professional_name}. O pagamento real acontece em A Pagar.`
        : ''"
      confirm-label="Marcar como paga"
      :loading="paying"
      @confirm="confirmPay"
    />
  </div>
</template>

<style scoped lang="scss">
.com-v2__filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.com-v2__filter { min-width: 0; flex: 0 0 220px; }
.com-v2__filter--grow { flex: 1 1 280px; }
.com-v2__filter--date { flex: 0 0 160px; }
@media (max-width: 640px) {
  .com-v2__filter,
  .com-v2__filter--grow,
  .com-v2__filter--date { flex: 1 1 100%; }
}
.com-v2__clear {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 8px 12px;
  border-radius: 8px;
  border: 1px solid rgb(var(--slate-5));
  background: rgb(var(--slate-2));
  font-size: 12px;
  color: rgb(var(--slate-11));
  cursor: pointer;
  &:hover { background: rgb(var(--slate-3)); }
}

/* ── Lista agrupada ──────────────────────────────────────────────── */
.com-v2__list { display: flex; flex-direction: column; gap: 10px; }
.com-v2__group {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
  transition: border-color 0.12s ease;
  &:hover { border-color: rgb(var(--slate-6)); }
}
.com-v2__group--expanded { border-color: rgb(var(--blue-7)); }

.com-v2__group-header {
  display: flex;
  align-items: center;
  gap: 16px;
  padding: 14px 18px;
  cursor: pointer;
  user-select: none;
  &:hover { background: rgb(var(--slate-2)); }
}
.com-v2__group-prof {
  display: flex;
  align-items: center;
  gap: 10px;
  flex: 1 1 0;
  min-width: 0;
}
.com-v2__group-meta {
  font-size: 12px;
  color: rgb(var(--slate-9));
  white-space: nowrap;
}

.com-v2__group-totals {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.com-v2__total-pill {
  display: flex;
  flex-direction: column;
  gap: 1px;
  padding: 6px 12px;
  border-radius: 8px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  min-width: 96px;
}
.com-v2__total-label {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
}
.com-v2__total-pill strong {
  font-size: 13px;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-12));
}
.com-v2__total-pill--due strong { color: rgb(var(--amber-11)); }
.com-v2__total-pill--paid strong { color: #047857; }
.com-v2__total-pill--reversed strong { color: rgb(var(--violet-11)); }
.com-v2__total-pill--net { background: rgb(var(--blue-3)); border-color: rgb(var(--blue-6)); }
:root.dark .com-v2__total-pill--net { background: rgba(59, 130, 246, 0.15); }
.com-v2__net--positive { color: #047857; }
.com-v2__net--negative { color: #b91c1c; }
:root.dark .com-v2__net--positive { color: #6ee7b7; }
:root.dark .com-v2__net--negative { color: #fca5a5; }

.com-v2__chevron {
  width: 18px;
  height: 18px;
  color: rgb(var(--slate-9));
  flex-shrink: 0;
}

@media (max-width: 800px) {
  .com-v2__group-header { flex-wrap: wrap; }
  .com-v2__group-prof { flex: 1 1 100%; }
  .com-v2__group-totals { flex: 1 1 100%; }
}

/* ── Linhas das comissões ─────────────────────────────────────── */
.com-v2__entries {
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-1));
}
.com-v2__cell-stack {
  display: flex;
  flex-direction: column;
  gap: 1px;
}
.com-v2__cell-stack--right { text-align: right; align-items: flex-end; }
.com-v2__cell-hint {
  font-size: 11px;
  color: rgb(var(--slate-9));
}
.com-v2__amount--negative { color: #b91c1c; }
:root.dark .com-v2__amount--negative { color: #fca5a5; }

.com-v2__th-actions { width: 80px; text-align: right; }
.com-v2__td-actions {
  text-align: right;
  white-space: nowrap;
}
.com-v2__icon-muted {
  color: rgb(var(--slate-9));
  vertical-align: middle;
  margin-right: 6px;
}

/* Acordeão expand/collapse */
.com-v2__expand-enter-active,
.com-v2__expand-leave-active {
  transition: max-height 0.2s ease, opacity 0.15s ease;
  overflow: hidden;
}
.com-v2__expand-enter-from,
.com-v2__expand-leave-to { max-height: 0; opacity: 0; }
.com-v2__expand-enter-to,
.com-v2__expand-leave-from { max-height: 1200px; opacity: 1; }
</style>
