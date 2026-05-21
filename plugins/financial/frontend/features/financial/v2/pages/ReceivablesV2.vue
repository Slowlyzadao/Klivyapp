<script setup>
/**
 * A Receber — v2 (canon Financial::*).
 *
 * Listagem AGRUPADA POR PACIENTE (refactor 2026-05-09):
 *   • Linha-pai = paciente com avatar, contagem, total em aberto, próximo
 *     vencimento e indicador de vencidas. Ocupa 1 linha por paciente.
 *   • Click na linha-pai → expande inline e mostra todas as parcelas do
 *     paciente (mesma estrutura/ações da versão antiga).
 *   • Múltiplos pacientes podem ficar abertos ao mesmo tempo.
 *   • Bulk receive: continua sendo escopado por paciente (regra anterior).
 *   • Filtros, busca e datas continuam server-side via mesmo backend.
 *   • Paginação agora é por PACIENTE (10/página default).
 *   • Mobile: cards stacked com expand/collapse no toque.
 *
 * Backend: GET /financial/v2/installments/by_patient
 *   Retorna [{ patient, summary, installments }] paginado por paciente.
 *   Aceita os mesmos filtros do `index` (status, q, from, to).
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import {
  PAYMENT_METHOD_BADGE_LABELS,
  paymentMethodVisual,
} from '@plugins/patients/frontend/constants/financial';
import FinancialV2 from '../api/financialV2';
import { centsToBRL } from '../composables/useMoney';
import ReceivePaymentModalV2 from '../components/ReceivePaymentModalV2.vue';
import FinSearchInput from '../components/FinSearchInput.vue';
import '@plugins/financial/frontend/styles/financial.scss';

// Chips de filtro — ordem e nomenclatura alinhadas com a Aba Financeiro do
// paciente pra reduzir fricção cognitiva ao trocar entre as 2 telas.
//   • "Todos" primeiro (convenção: opção mais permissiva inicia a lista).
//   • "Em aberto" = pendente + parcial (NÃO inclui vencido — esse fica em
//     chip separado pra dar foco). Antes incluía vencido aqui também,
//     causava sobreposição confusa de "Em aberto" e "Vencidos".
//   • Chip "Pendente" puro removido — era subset de "Em aberto" e gerava
//     dúvida ("qual a diferença?"). Filtro singular é raramente necessário.
//   • Labels pluralizadas (Vencidos/Recebidos/etc) consistente com Aba
//     Financeiro do paciente.
const STATUS_CHIPS = [
  { key: 'all',        label: 'Todos',      tone: 'blue',    statuses: [],                       icon: 'i-lucide-list' },
  { key: 'open',       label: 'Em aberto',  tone: 'amber',   statuses: ['pendente', 'parcial'],  icon: 'i-lucide-clock' },
  { key: 'vencido',    label: 'Vencidos',   tone: 'ruby',    statuses: ['vencido'],              icon: 'i-lucide-alert-circle' },
  { key: 'recebido',   label: 'Recebidos',  tone: 'emerald', statuses: ['recebido'],             icon: 'i-lucide-check-circle-2' },
  { key: 'estornado',  label: 'Estornados', tone: 'violet',  statuses: ['estornado'],            icon: 'i-lucide-undo' },
  { key: 'cancelado',  label: 'Cancelados', tone: 'slate',   statuses: ['cancelado'],            icon: 'i-lucide-x-circle' },
];

const STATUS_BADGE = {
  pendente:   { color: 'slate',   icon: 'i-lucide-clock',           label: 'Pendente' },
  parcial:    { color: 'blue',    icon: 'i-lucide-circle-dot',      label: 'Parcial' },
  recebido:   { color: 'emerald', icon: 'i-lucide-check-circle-2',  label: 'Recebido' },
  vencido:    { color: 'ruby',    icon: 'i-lucide-alert-circle',    label: 'Vencido' },
  estornado:  { color: 'violet',  icon: 'i-lucide-undo',            label: 'Estornado' },
  cancelado:  { color: 'slate',   icon: 'i-lucide-x-circle',        label: 'Cancelado' },
  renegociado:{ color: 'amber',   icon: 'i-lucide-refresh-cw',      label: 'Renegociado' },
};

// `groups` substitui o array plano `installments` da versão anterior.
// Cada entrada: { patient, summary, installments: [...] }
const groups = ref([]);
const loading = ref(false);
const filters = ref({
  status_chip: 'open',
  q: '',
  payment_method: '',
  from: '',
  to: '',
});
const currentPage = ref(1);
const perPage = ref(10);
const meta = ref({
  total_to_receive_cents: 0,
  total_received_cents: 0,
  total_overdue_cents: 0,
  total: 0,             // total de PACIENTES (paginação)
  total_installments: 0, // total de parcelas matching (KPI extra)
});

// Set<patientId> — pacientes com acordeão expandido. Múltiplos podem ficar
// abertos ao mesmo tempo. Ao trocar filtro/página, resetamos pra evitar
// dados estranhos (paciente que foi pra outra página continuar "expandido").
const expanded = ref(new Set());

// Seleção de parcelas pra bulk receive — continua escopada por paciente
// (regra anterior). Mapa: { [installmentId]: true }.
const selected = ref({});

const showReceiveModal = ref(false);
const receivePatient = ref(null);
const focusedInstallmentIds = ref([]);

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

// Lista plana de TODAS as parcelas atualmente carregadas (na página).
// Necessária pra computar `selectedInstallments` e o modal de receber.
const allInstallments = computed(() =>
  groups.value.flatMap(g => g.installments)
);

const selectedInstallments = computed(() =>
  allInstallments.value.filter(i => selected.value[i.id]),
);

const canBulkReceive = computed(() => {
  if (selectedInstallments.value.length === 0) return false;
  const patientIds = new Set(selectedInstallments.value.map(i => i.patient.id));
  return patientIds.size === 1 && selectedInstallments.value.every(
    i => ['pendente', 'vencido', 'parcial'].includes(i.status)
  );
});

const activeChip = computed(
  () => STATUS_CHIPS.find(c => c.key === filters.value.status_chip) || STATUS_CHIPS[0]
);

async function load() {
  loading.value = true;
  try {
    const params = { page: currentPage.value, per_page: perPage.value };
    if (activeChip.value.statuses.length > 0) {
      params.status = activeChip.value.statuses;
    }
    if (filters.value.q) params.q = filters.value.q;
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;

    const { data } = await FinancialV2.installments.byPatient(params);
    groups.value = data?.data || [];
    meta.value = { ...(data?.meta || {}) };
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[ReceivablesV2] load error', err);
    notifyError('Falha ao carregar parcelas.');
  } finally {
    loading.value = false;
  }
}

watch(filters, () => {
  currentPage.value = 1;
  // Mantém `expanded` propositadamente — UX 2026-05-12: alternar chips de
  // status (Em aberto / Pendente / etc) não deve fechar acordeões abertos.
  // Se um paciente expandido sair da lista filtrada, o id "fantasma" no Set
  // é inofensivo (v-for não renderiza nada extra).
  selected.value = {};
  load();
}, { deep: true });

watch([currentPage, perPage], () => {
  // Paginação muda os pacientes na tela — limpar expanded faz sentido aqui.
  expanded.value = new Set();
  selected.value = {};
  load();
});

onMounted(load);

// ── Helpers de visual ────────────────────────────────────────────────
function statusBadge(status) {
  return STATUS_BADGE[status] || STATUS_BADGE.pendente;
}

function methodLabel(method) {
  return PAYMENT_METHOD_BADGE_LABELS[method] || method || '—';
}

function methodVisual(method) {
  return paymentMethodVisual(method) || { color: 'slate', icon: 'i-lucide-circle' };
}

function formatDateBR(iso) {
  if (!iso) return '—';
  const [y, m, d] = String(iso).slice(0, 10).split('-');
  if (!y || !m || !d) return iso;
  return `${d}/${m}/${y}`;
}

function budgetLabel(inst) {
  return inst?.budget?.label || (inst?.budget_id ? `Orçamento #${inst.budget_id}` : '');
}

// Descrição amigável do orçamento (vem do backend: notes ou nome do
// primeiro item). Reduz fricção em telas com várias parcelas do mesmo
// orçamento — em vez de "#5" repetido, mostra o nome do procedimento.
function budgetDescription(inst) {
  return inst?.budget?.description || '';
}

function isPayable(inst) {
  // Aceita o status cru OU o derivado: parcela pendente que venceu vira
  // `effective_status: 'vencido'` mas continua pagável.
  const s = inst.effective_status || inst.status;
  return ['pendente', 'vencido', 'parcial'].includes(s);
}

// Agrupa parcelas por orçamento (budget_id) preservando ordem original
// (que vem por due_date ASC do backend). Mesma UX do Aba Financeiro do
// paciente — em vez de lista plana com 25 parcelas misturadas, mostra
// cada orçamento como bloco com seu header (label + total + N pagas).
function groupedByBudget(installments) {
  const groups = new Map();
  for (const inst of installments) {
    const key = inst.budget_id || `no-budget-${inst.id}`;
    if (!groups.has(key)) {
      groups.set(key, {
        budget: inst.budget || { id: inst.budget_id, label: budgetLabel(inst) },
        installments: [],
      });
    }
    groups.get(key).installments.push(inst);
  }
  return Array.from(groups.values()).map(g => ({
    ...g,
    paidCount: g.installments.filter(i => i.status === 'recebido').length,
    totalCount: g.installments.length,
  }));
}

// ── Expansão acordeão ───────────────────────────────────────────────
function toggleExpand(patientId) {
  const next = new Set(expanded.value);
  if (next.has(patientId)) next.delete(patientId);
  else next.add(patientId);
  expanded.value = next;
}

function isExpanded(patientId) {
  return expanded.value.has(patientId);
}

function expandAll() {
  expanded.value = new Set(groups.value.map(g => g.patient.id));
}

function collapseAll() {
  expanded.value = new Set();
  selected.value = {};
}

const allExpanded = computed(() =>
  groups.value.length > 0 && groups.value.every(g => expanded.value.has(g.patient.id))
);

// ── Bulk select / receive ────────────────────────────────────────────
function openReceiveForRow(inst) {
  receivePatient.value = inst.patient;
  focusedInstallmentIds.value = [inst.id];
  showReceiveModal.value = true;
}

function openReceiveBulk() {
  if (!canBulkReceive.value) return;
  receivePatient.value = selectedInstallments.value[0].patient;
  focusedInstallmentIds.value = selectedInstallments.value.map(i => i.id);
  showReceiveModal.value = true;
}

const modalInstallments = computed(() => {
  if (focusedInstallmentIds.value.length === 0) return [];
  const ids = new Set(focusedInstallmentIds.value);
  return allInstallments.value.filter(i => ids.has(i.id));
});

function onReceiveConfirmed() {
  selected.value = {};
  focusedInstallmentIds.value = [];
  showReceiveModal.value = false;
  notifySuccess('Pagamento registrado.');
  load();
}

async function chargeWhatsapp(inst) {
  try {
    const { data } = await FinancialV2.installments.chargeWhatsapp(inst.id);
    if (data?.whatsapp_url) {
      window.open(data.whatsapp_url, '_blank', 'noopener');
    } else if (data?.phone && data?.message) {
      const url = `https://wa.me/${data.phone}?text=${encodeURIComponent(data.message)}`;
      window.open(url, '_blank', 'noopener');
    } else {
      notifyError('Paciente sem telefone cadastrado.');
    }
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[ReceivablesV2] whatsapp error', err);
    notifyError('Falha ao gerar mensagem WhatsApp.');
  }
}

function clearDates() {
  filters.value.from = '';
  filters.value.to = '';
}

// Reset completo dos filtros — usado no empty state pra recuperação rápida
// quando o usuário ficou "preso" numa combinação de filtros que retorna vazio.
function resetFilters() {
  filters.value.status_chip = 'all';
  filters.value.q = '';
  filters.value.from = '';
  filters.value.to = '';
}

const hasDateFilter = computed(() => filters.value.from || filters.value.to);
const selectedCount = computed(() => Object.values(selected.value).filter(Boolean).length);
</script>

<template>
  <div class="finv2-page">
    <!-- Header sticky -->
    <header class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">A Receber</h1>
        <p class="finv2-page__subtitle">
          Agrupado por paciente — clique pra expandir parcelas. Filtre por
          status, paciente ou período.
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <BeclinicButton
          v-if="selectedCount > 0"
          variant="solid"
          color="teal"
          icon="i-lucide-circle-dollar-sign"
          :label="`Receber ${selectedCount} ${selectedCount === 1 ? 'parcela' : 'parcelas'}`"
          :disabled="!canBulkReceive"
          @click="openReceiveBulk"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- KPIs -->
      <div class="finv2-kpis">
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-wallet w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Total a receber</span>
            <strong class="finv2-kpi__value">{{ centsToBRL(meta.total_to_receive_cents) }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--positive">
            <i class="i-lucide-trending-up w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Recebido</span>
            <strong class="finv2-kpi__value finv2-kpi__value--positive">
              {{ centsToBRL(meta.total_received_cents) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger">
            <i class="i-lucide-alert-triangle w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Vencido</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ centsToBRL(meta.total_overdue_cents) }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-users w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Pacientes</span>
            <strong class="finv2-kpi__value">
              {{ meta.total || 0 }}
              <span class="rcv-v2__pacientes-sub">
                · {{ meta.total_installments || 0 }} parcelas
              </span>
            </strong>
          </div>
        </div>
      </div>

      <!-- Filtros -->
      <div class="rcv-v2__filters">
        <div class="finv2-chips" role="tablist" aria-label="Filtrar por status">
          <button
            v-for="chip in STATUS_CHIPS"
            :key="chip.key"
            type="button"
            role="tab"
            class="finv2-chip"
            :class="[`finv2-chip--tone-${chip.tone}`, { 'finv2-chip--active': filters.status_chip === chip.key }]"
            :aria-selected="filters.status_chip === chip.key"
            @click="filters.status_chip = chip.key"
          >
            <i :class="chip.icon" class="w-3.5 h-3.5" />
            <span>{{ chip.label }}</span>
          </button>
        </div>

        <div class="rcv-v2__inputs">
          <FinSearchInput
            v-model="filters.q"
            placeholder="Buscar por paciente…"
            class="rcv-v2__input--grow"
          />
          <div class="finv2-input-wrap finv2-input-wrap--date">
            <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
          </div>
          <div class="finv2-input-wrap finv2-input-wrap--date">
            <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
          </div>
          <button v-if="hasDateFilter" type="button" class="rcv-v2__clear" @click="clearDates">
            <i class="i-lucide-x w-3.5 h-3.5" /> Limpar
          </button>
        </div>

        <!-- Quick actions: expandir/recolher todos -->
        <div v-if="groups.length > 0" class="rcv-v2__quick-actions">
          <button
            v-if="!allExpanded"
            type="button"
            class="rcv-v2__link-btn"
            @click="expandAll"
          >
            <i class="i-lucide-unfold-vertical w-3.5 h-3.5" />
            Expandir todos
          </button>
          <button
            v-else
            type="button"
            class="rcv-v2__link-btn"
            @click="collapseAll"
          >
            <i class="i-lucide-fold-vertical w-3.5 h-3.5" />
            Recolher todos
          </button>
        </div>
      </div>

      <!-- Loading / Empty -->
      <div v-if="loading" class="finv2-state">
        <div class="finv2-spinner" />
        <span>Carregando pacientes…</span>
      </div>
      <div v-else-if="groups.length === 0" class="finv2-state">
        <div class="finv2-state__icon-wrap"><i class="i-lucide-inbox w-7 h-7" /></div>
        <p class="finv2-state__title">Nenhum paciente encontrado</p>
        <!-- Mensagem contextual baseada nos filtros ativos: ajuda o usuário
             a entender por que veio vazio (busca restritiva, chip + busca,
             ou simplesmente sem dados na conta). -->
        <p class="finv2-state__hint">
          <template v-if="filters.q && activeChip.key !== 'all'">
            Nenhum paciente com "<strong>{{ filters.q }}</strong>" tem parcelas em <strong>{{ activeChip.label }}</strong>.
          </template>
          <template v-else-if="filters.q">
            Nenhum paciente com "<strong>{{ filters.q }}</strong>" no nome. A busca é por <strong>nome do paciente</strong>, não por profissional.
          </template>
          <template v-else-if="activeChip.key !== 'all'">
            Nenhuma parcela em <strong>{{ activeChip.label }}</strong> no momento.
          </template>
          <template v-else>
            Ajuste os filtros ou aguarde novos lançamentos.
          </template>
        </p>
        <button
          v-if="filters.q || activeChip.key !== 'all' || hasDateFilter"
          type="button"
          class="finv2-state__reset-btn"
          @click="resetFilters"
        >
          <i class="i-lucide-x w-3.5 h-3.5" />
          Limpar filtros
        </button>
      </div>

      <!-- Lista de pacientes (acordeão) -->
      <div v-else class="rcv-v2__patients">
        <article
          v-for="group in groups"
          :key="group.patient.id"
          class="rcv-v2__patient-card"
          :class="{ 'rcv-v2__patient-card--expanded': isExpanded(group.patient.id) }"
        >
          <!-- Linha-pai (sempre visível) -->
          <button
            type="button"
            class="rcv-v2__patient-header"
            :aria-expanded="isExpanded(group.patient.id)"
            @click="toggleExpand(group.patient.id)"
          >
            <div class="rcv-v2__patient-info">
              <ProfessionalChip
                :name="group.patient.name || '—'"
                :avatar-url="group.patient.avatar_url || ''"
                size="md"
              />
            </div>

            <div class="rcv-v2__patient-stats">
              <div class="rcv-v2__stat">
                <span class="rcv-v2__stat-label">Parcelas</span>
                <strong class="rcv-v2__stat-value">{{ group.summary.count }}</strong>
              </div>
              <div class="rcv-v2__stat">
                <span class="rcv-v2__stat-label">Total em aberto</span>
                <strong class="rcv-v2__stat-value rcv-v2__stat-value--money">
                  {{ centsToBRL(group.summary.total_remaining_cents) }}
                </strong>
              </div>
              <div class="rcv-v2__stat rcv-v2__stat--hide-sm">
                <span class="rcv-v2__stat-label">Próx. vencimento</span>
                <strong class="rcv-v2__stat-value">
                  {{ formatDateBR(group.summary.next_due_date) }}
                </strong>
              </div>
              <div class="rcv-v2__stat-status">
                <Badge
                  v-if="group.summary.overdue_count > 0"
                  :label="`${group.summary.overdue_count} vencida${group.summary.overdue_count > 1 ? 's' : ''}`"
                  color="ruby"
                  icon="i-lucide-alert-circle"
                  size="xs"
                />
                <Badge
                  v-else-if="group.summary.open_count > 0"
                  label="Em dia"
                  color="emerald"
                  icon="i-lucide-check-circle-2"
                  size="xs"
                />
                <Badge
                  v-else
                  label="Sem pendências"
                  color="slate"
                  size="xs"
                />
              </div>
            </div>

            <i
              class="rcv-v2__chevron"
              :class="isExpanded(group.patient.id) ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
              aria-hidden="true"
            />
          </button>

          <!-- Conteúdo expandido: tabela de parcelas (desktop) -->
          <div
            v-if="isExpanded(group.patient.id)"
            class="rcv-v2__expanded"
          >
            <!-- Desktop: tabela aninhada (wrap em div pra `finv2-hide-mobile`
                 não quebrar o `display: table` do <table>). -->
            <div class="finv2-hide-mobile">
            <table class="finv2-table rcv-v2__inner-table">
              <thead>
                <tr>
                  <th class="rcv-v2__th-checkbox"></th>
                  <th>Parcela</th>
                  <th class="finv2-table__th-num">Saldo</th>
                  <th>Vencimento</th>
                  <th>Forma</th>
                  <th>Status</th>
                  <th class="finv2-table__th-actions">Ações</th>
                </tr>
              </thead>
              <tbody>
                <!-- Agrupa parcelas por orçamento (mesma UX do Aba Financeiro
                     do paciente). Cada grupo tem um header de orçamento +
                     suas parcelas. Em pacientes com vários orçamentos a
                     leitura fica MUITO mais escaneável. -->
                <template
                  v-for="g in groupedByBudget(group.installments)"
                  :key="`bg-${g.budget.id || 'no-budget'}`"
                >
                  <tr class="rcv-v2__budget-header-row">
                    <td colspan="7">
                      <div class="rcv-v2__budget-header">
                        <i class="i-lucide-folder-open w-3.5 h-3.5" />
                        <strong>{{ g.budget.label || 'Orçamento' }}</strong>
                        <span
                          v-if="g.budget.description"
                          class="rcv-v2__budget-header-desc"
                        >
                          · {{ g.budget.description }}
                        </span>
                        <span class="rcv-v2__budget-header-count">
                          {{ g.paidCount }}/{{ g.totalCount }} pagas
                        </span>
                      </div>
                    </td>
                  </tr>
                  <tr
                    v-for="inst in g.installments"
                    :key="inst.id"
                    :class="{ 'rcv-v2__row--selected': selected[inst.id] }"
                  >
                    <td class="rcv-v2__td-checkbox">
                      <Checkbox
                        v-model="selected[inst.id]"
                        :disabled="!isPayable(inst)"
                        aria-label="Selecionar parcela"
                      />
                    </td>
                    <td>
                      <strong>
                        parcela {{ inst.number }}/{{ inst.total_in_series }}
                      </strong>
                    </td>
                    <td class="finv2-table__td-num finv2-table__td-num--strong">
                      {{ centsToBRL(inst.remaining_cents) }}
                      <span
                        v-if="inst.amount_cents !== inst.remaining_cents"
                        class="rcv-v2__amount-original"
                      >
                        de {{ centsToBRL(inst.amount_cents) }}
                      </span>
                    </td>
                    <td class="finv2-table__td-date">{{ formatDateBR(inst.due_date) }}</td>
                    <td>
                      <Badge
                        v-if="inst.payment_method"
                        :label="methodLabel(inst.payment_method)"
                        :color="methodVisual(inst.payment_method).color"
                        :icon="methodVisual(inst.payment_method).icon"
                        size="xs"
                      />
                      <span v-else class="finv2-table__td-muted">—</span>
                    </td>
                    <td>
                      <Badge
                        :label="statusBadge(inst.effective_status || inst.status).label"
                        :color="statusBadge(inst.effective_status || inst.status).color"
                        :icon="statusBadge(inst.effective_status || inst.status).icon"
                        size="xs"
                      />
                    </td>
                    <td class="finv2-table__td-actions">
                      <Tooltip v-if="isPayable(inst)" label="Receber pagamento">
                        <BeclinicButton
                          size="xs"
                          variant="faded"
                          color="teal"
                          icon="i-lucide-check"
                          @click="openReceiveForRow(inst)"
                        />
                      </Tooltip>
                      <Tooltip v-if="isPayable(inst)" label="Cobrar via WhatsApp">
                        <BeclinicButton
                          size="xs"
                          variant="ghost"
                          color="teal"
                          icon="i-ri-whatsapp-fill"
                          @click="chargeWhatsapp(inst)"
                        />
                      </Tooltip>
                    </td>
                  </tr>
                </template>
              </tbody>
            </table>
            </div>

            <!-- Mobile: cards de parcela aninhados — wrap em div helper
                 pra `finv2-show-mobile` não brigar com `display: flex`
                 da classe scoped `.rcv-v2__inner-cards`. -->
            <div class="finv2-show-mobile">
            <!-- Mobile também agrupa por orçamento — bloco com header + cards
                 de parcelas dentro. Mesma UX do desktop. -->
            <div class="rcv-v2__inner-cards">
              <template
                v-for="g in groupedByBudget(group.installments)"
                :key="`mbg-${g.budget.id || 'no-budget'}`"
              >
                <div class="rcv-v2__budget-header rcv-v2__budget-header--mobile">
                  <i class="i-lucide-folder-open w-3.5 h-3.5" />
                  <strong>{{ g.budget.label || 'Orçamento' }}</strong>
                  <span class="rcv-v2__budget-header-count">
                    {{ g.paidCount }}/{{ g.totalCount }} pagas
                  </span>
                </div>
              <article
                v-for="inst in g.installments"
                :key="`m-${inst.id}`"
                class="rcv-v2__inner-card"
                :class="{ 'rcv-v2__inner-card--selected': selected[inst.id] }"
              >
                <div class="rcv-v2__inner-card-row">
                  <Checkbox
                    v-model="selected[inst.id]"
                    :disabled="!isPayable(inst)"
                    aria-label="Selecionar parcela"
                  />
                  <div class="rcv-v2__inner-card-info">
                    <strong>
                      parcela {{ inst.number }}/{{ inst.total_in_series }}
                    </strong>
                  </div>
                  <Badge
                    :label="statusBadge(inst.status).label"
                    :color="statusBadge(inst.status).color"
                    :icon="statusBadge(inst.status).icon"
                    size="xs"
                  />
                </div>
                <div class="rcv-v2__inner-card-grid">
                  <div>
                    <span class="rcv-v2__inner-card-label">Saldo</span>
                    <strong class="rcv-v2__inner-card-value">
                      {{ centsToBRL(inst.remaining_cents) }}
                    </strong>
                  </div>
                  <div>
                    <span class="rcv-v2__inner-card-label">Vencimento</span>
                    <span class="rcv-v2__inner-card-value-muted">
                      {{ formatDateBR(inst.due_date) }}
                    </span>
                  </div>
                  <div>
                    <span class="rcv-v2__inner-card-label">Forma</span>
                    <Badge
                      v-if="inst.payment_method"
                      :label="methodLabel(inst.payment_method)"
                      :color="methodVisual(inst.payment_method).color"
                      :icon="methodVisual(inst.payment_method).icon"
                      size="xs"
                    />
                    <span v-else class="finv2-table__td-muted">—</span>
                  </div>
                </div>
                <div v-if="isPayable(inst)" class="rcv-v2__inner-card-actions">
                  <BeclinicButton
                    size="sm"
                    variant="faded"
                    color="teal"
                    icon="i-lucide-check"
                    label="Receber"
                    @click="openReceiveForRow(inst)"
                  />
                  <BeclinicButton
                    size="sm"
                    variant="ghost"
                    color="teal"
                    icon="i-ri-whatsapp-fill"
                    label="WhatsApp"
                    @click="chargeWhatsapp(inst)"
                  />
                </div>
              </article>
              </template>
            </div>
            </div>
          </div>
        </article>
      </div>

      <Pagination
        v-model:current-page="currentPage"
        v-model:per-page="perPage"
        :total-count="meta.total || 0"
        item-label="pacientes"
        :per-page-options="[10, 25, 50]"
      />
    </div>

    <ReceivePaymentModalV2
      :show="showReceiveModal"
      :installments="modalInstallments"
      :patient="receivePatient"
      @close="showReceiveModal = false"
      @confirm="onReceiveConfirmed"
    />
  </div>
</template>

<style scoped lang="scss">
/* Layout, KPIs, table, chips e estados vêm do _layout.scss global. */

.finv2-page { display: flex; flex-direction: column; background: rgb(var(--slate-1)); color: rgb(var(--slate-12)); }

.rcv-v2__pacientes-sub {
  font-size: 11px;
  font-weight: 400;
  color: rgb(var(--slate-9));
}

/* ── Filtros ──────────────────────────────────────────────────── */
.rcv-v2__filters { display: flex; flex-direction: column; gap: 10px; }
.rcv-v2__inputs {
  display: grid;
  grid-template-columns: 2fr 1fr 1fr auto;
  gap: 8px;
  align-items: center;
}
@media (max-width: 800px) {
  .rcv-v2__inputs { grid-template-columns: 1fr 1fr; }
  .rcv-v2__input--grow { grid-column: 1 / -1; }
}
.rcv-v2__clear {
  display: inline-flex; align-items: center; gap: 4px;
  background: transparent;
  border: 1px solid rgb(var(--slate-5));
  color: rgb(var(--slate-9));
  font-size: 12px; cursor: pointer;
  padding: 9px 12px; border-radius: 8px;
  &:hover { color: rgb(var(--slate-12)); border-color: rgb(var(--slate-7)); }
}
.rcv-v2__quick-actions {
  display: flex; gap: 8px; align-items: center;
  margin-top: 2px;
}
.rcv-v2__link-btn {
  display: inline-flex; align-items: center; gap: 4px;
  background: transparent; border: 0;
  color: rgb(var(--slate-9));
  font-size: 12px;
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 6px;
  &:hover { color: rgb(var(--slate-12)); background: rgb(var(--slate-3)); }
}

/* ── Lista de pacientes (acordeão) ───────────────────────────── */
.rcv-v2__patients { display: flex; flex-direction: column; gap: 8px; }

.rcv-v2__patient-card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  overflow: hidden;
  transition: border-color 0.15s ease;
  &:hover { border-color: rgb(var(--slate-6)); }
}
.rcv-v2__patient-card--expanded {
  border-color: rgb(var(--blue-7));
  box-shadow: 0 0 0 1px rgba(37, 99, 235, 0.10);
}

.rcv-v2__patient-header {
  display: grid;
  grid-template-columns: minmax(0, 1.5fr) minmax(0, 2fr) auto;
  align-items: center;
  gap: 14px;
  padding: 14px 16px;
  width: 100%;
  background: transparent;
  border: 0;
  cursor: pointer;
  text-align: left;
  transition: background 0.1s ease;
  &:hover { background: rgb(var(--slate-2) / 0.5); }
}
@media (max-width: 800px) {
  .rcv-v2__patient-header {
    grid-template-columns: 1fr auto;
    grid-template-areas: 'info chevron' 'stats stats';
  }
}

.rcv-v2__patient-info {
  display: flex; align-items: center; gap: 8px;
  min-width: 0;
}
@media (max-width: 800px) { .rcv-v2__patient-info { grid-area: info; } }

.rcv-v2__patient-stats {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, auto));
  gap: 16px;
  align-items: center;
  justify-content: end;
}
@media (max-width: 800px) {
  .rcv-v2__patient-stats {
    grid-area: stats;
    grid-template-columns: 1fr 1fr auto;
    gap: 10px;
    margin-top: 4px;
    padding-top: 10px;
    border-top: 1px solid rgb(var(--slate-3));
  }
  .rcv-v2__stat--hide-sm { display: none; }
}

.rcv-v2__stat {
  display: flex; flex-direction: column; gap: 2px;
  min-width: 0;
}
.rcv-v2__stat-label {
  font-size: 10.5px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
  font-weight: 500;
  white-space: nowrap;
}
.rcv-v2__stat-value {
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
.rcv-v2__stat-value--money {
  color: rgb(var(--blue-11));
  font-size: 15px;
}

.rcv-v2__stat-status {
  display: flex; align-items: center; justify-content: flex-end;
  min-width: 0;
}

.rcv-v2__chevron {
  width: 18px; height: 18px;
  color: rgb(var(--slate-9));
  transition: transform 0.2s ease;
  flex-shrink: 0;
}
@media (max-width: 800px) { .rcv-v2__chevron { grid-area: chevron; } }

.rcv-v2__patient-card--expanded .rcv-v2__chevron {
  color: rgb(var(--blue-9));
}

/* ── Conteúdo expandido ──────────────────────────────────────── */
.rcv-v2__expanded {
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2) / 0.3);
}

// Header de grupo do orçamento — separador visual entre parcelas de
// orçamentos diferentes dentro do mesmo paciente. Mesma UX do Aba
// Financeiro do paciente (cards de orçamento com label + contador).
.rcv-v2__budget-header-row {
  td {
    background: rgb(var(--slate-3));
    border-top: 1px solid rgb(var(--slate-4));
    border-bottom: 1px solid rgb(var(--slate-4));
    padding: 8px 12px !important;
  }
  &:first-child td {
    border-top: none;
  }
}
.rcv-v2__budget-header {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 12px;
  color: rgb(var(--slate-11));
  strong {
    color: rgb(var(--slate-12));
    font-weight: 600;
    font-size: 12.5px;
  }
  &--mobile {
    padding: 8px 12px;
    margin-top: 8px;
    background: rgb(var(--slate-3));
    border-radius: 6px;
    border: 1px solid rgb(var(--slate-4));
    &:first-child { margin-top: 0; }
  }
}
.rcv-v2__budget-header-desc {
  color: rgb(var(--slate-10));
  font-weight: 400;
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  min-width: 0;
}
.rcv-v2__budget-header-count {
  margin-left: auto;
  font-size: 11px;
  font-weight: 600;
  color: rgb(var(--slate-10));
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
}

.rcv-v2__inner-table {
  background: transparent;
  thead th {
    background: rgb(var(--slate-2));
    font-size: 10.5px;
  }
  th, td { padding: 10px 16px; }
}

.rcv-v2__row--selected { background: rgba(37, 99, 235, 0.08) !important; }
.rcv-v2__th-checkbox, .rcv-v2__td-checkbox { width: 36px; }

.rcv-v2__inst-meta {
  display: flex; flex-direction: column; gap: 2px;
  strong { color: rgb(var(--slate-12)); font-weight: 500; font-size: 13px; }
}
.rcv-v2__budget-link {
  font-size: 11.5px;
  color: rgb(var(--slate-9));
}
/* Descrição do orçamento ao lado da parcela: peso normal pra não competir
   com o "parcela X/Y" mas com cor levemente mais quente (slate-11) que a
   linha do `#ID` abaixo. Trunca com ellipsis em telas estreitas. */
.rcv-v2__inst-desc {
  font-weight: 400;
  color: rgb(var(--slate-11));
  overflow: hidden;
  text-overflow: ellipsis;
}
.rcv-v2__amount-original {
  display: block;
  margin-top: 2px;
  font-size: 11px;
  font-weight: 400;
  color: rgb(var(--slate-9));
  text-decoration: line-through;
}

/* ── Inner cards (mobile) ────────────────────────────────────── */
.rcv-v2__inner-cards {
  display: flex; flex-direction: column; gap: 8px;
  padding: 12px;
}
.rcv-v2__inner-card {
  display: flex; flex-direction: column; gap: 10px;
  padding: 12px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 10px;
  &--selected {
    border-color: rgb(var(--blue-8));
    background: rgba(37, 99, 235, 0.06);
  }
}
.rcv-v2__inner-card-row {
  display: flex; align-items: flex-start; gap: 10px;
}
.rcv-v2__inner-card-info {
  flex: 1; min-width: 0;
  display: flex; flex-direction: column; gap: 2px;
  strong { color: rgb(var(--slate-12)); font-weight: 600; font-size: 13px; }
}
.rcv-v2__inner-card-meta { font-size: 11.5px; color: rgb(var(--slate-9)); }
.rcv-v2__inner-card-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
  padding-top: 8px;
  border-top: 1px solid rgb(var(--slate-3));
}
.rcv-v2__inner-card-label {
  display: block;
  font-size: 10px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
  margin-bottom: 2px;
}
.rcv-v2__inner-card-value {
  font-size: 13px;
  color: rgb(var(--slate-12));
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}
.rcv-v2__inner-card-value-muted {
  font-size: 12px;
  color: rgb(var(--slate-11));
}
.rcv-v2__inner-card-actions {
  display: flex; gap: 6px; flex-wrap: wrap;
  padding-top: 8px;
  border-top: 1px solid rgb(var(--slate-3));
}
</style>
