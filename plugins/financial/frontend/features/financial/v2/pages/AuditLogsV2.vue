<script setup>
/**
 * Auditoria — v2 (canon F-31).
 *
 * Tela global de AuditLog (financeiro). Lista cronológica de todas as
 * mudanças em entidades financeiras (Orçamento, Despesa, Recibo, etc.)
 * com filtros (entidade, ação, usuário, período, busca livre) e diff
 * visual before/after ao clicar numa linha.
 *
 * Permissões: backend exige ADMIN/AUDITOR/GERENTE (controller checa).
 *
 * Limitações:
 *   • Aba "Histórico de alterações" por entidade fica pra próxima rodada
 *     — exige tocar em cada tela de entidade. A tela global cobre 90% do
 *     valor (compliance + investigação reativa).
 *   • Export CSV usa endpoint backend existente.
 */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';

// PR audit 2026-05-21: `embedded=true` quando renderizada como tab dentro
// de SettingsV2 — esconde o header global próprio (h1 + subtitle + actions)
// pra não duplicar com o header "Configurações financeiras". Quando aberta
// via URL direta `/financial/v2/audit` (redirect → settings/audit), também
// vira embedded. Acesso standalone fora do Settings hoje não existe.
defineProps({ embedded: { type: Boolean, default: false } });
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import FinancialV2 from '../api/financialV2';
import FinSearchInput from '../components/FinSearchInput.vue';
import '@plugins/financial/frontend/styles/financial.scss';

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const logs = ref([]);
const meta = ref({});
const facets = ref({ entity_types: [], actions: [], users: [] });
const loading = ref(false);
const exporting = ref(false);

const filters = ref({
  entity_type: '',
  action: '',
  user_id: '',
  from: '',
  to: '',
  q: '',
});
const currentPage = ref(1);
const perPage = ref(50);

// Modal de detalhes (diff before/after)
const showDetailsModal = ref(false);
const selectedLog = ref(null);

const entityTypeOptions = computed(() => [
  { value: '', label: 'Todas as entidades' },
  ...facets.value.entity_types.map(e => ({ value: e.value, label: e.label })),
]);
const actionOptions = computed(() => [
  { value: '', label: 'Todas as ações' },
  ...facets.value.actions.map(a => ({ value: a.value, label: a.label })),
]);
const userOptions = computed(() => [
  { value: '', label: 'Todos os usuários' },
  ...facets.value.users.map(u => ({ value: u.id, label: u.name })),
]);

const hasFilter = computed(() =>
  filters.value.entity_type
  || filters.value.action
  || filters.value.user_id
  || filters.value.from
  || filters.value.to
  || filters.value.q,
);

async function load() {
  loading.value = true;
  try {
    const params = { page: currentPage.value, per_page: perPage.value };
    if (filters.value.entity_type) params.entity_type = filters.value.entity_type;
    if (filters.value.action) params.action = filters.value.action;
    if (filters.value.user_id) params.user_id = filters.value.user_id;
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;
    if (filters.value.q) params.q = filters.value.q;

    const { data } = await FinancialV2.auditLogs.index(params);
    logs.value = data?.data || [];
    meta.value = data?.meta || {};
    if (data?.meta?.facets) facets.value = data.meta.facets;
  } catch (err) {
    notifyError(err?.response?.data?.error === 'forbidden'
      ? 'Acesso negado. Apenas ADMIN/AUDITOR/GERENTE podem ver auditoria.'
      : 'Falha ao carregar auditoria.');
  } finally {
    loading.value = false;
  }
}

async function exportCsv() {
  exporting.value = true;
  try {
    const params = {};
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;
    const response = await FinancialV2.auditLogs.exportCsv(params);

    // 202 Accepted = export assíncrono (rows > 50k). Backend retorna JSON com
    // `async: true` + email de notificação. Como axios está com responseType:
    // 'blob', precisa ler o blob como texto e parsear.
    if (response.status === 202) {
      const text = await response.data.text();
      const json = JSON.parse(text);
      notifySuccess(json.message || `Export em processamento. Email será enviado para ${json.notification_email}.`);
      return;
    }

    // 200 = CSV pronto pra download síncrono
    const url = URL.createObjectURL(response.data);
    const link = document.createElement('a');
    link.href = url;
    link.download = `financial_audit_${new Date().toISOString().slice(0, 10)}.csv`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);
    notifySuccess('CSV exportado.');
  } catch (err) {
    // Status de erro do backend (429 rate limit, 422 range inválido) também
    // vem como blob. Tenta parsear pra mostrar mensagem útil.
    if (err?.response?.data instanceof Blob) {
      try {
        const text = await err.response.data.text();
        const json = JSON.parse(text);
        notifyError(json.message || 'Falha ao exportar CSV.');
        return;
      } catch {
        // não-JSON, cai no fallback
      }
    }
    notifyError(err?.response?.data?.message || 'Falha ao exportar CSV.');
  } finally {
    exporting.value = false;
  }
}

watch(filters, () => {
  currentPage.value = 1;
  load();
}, { deep: true });

watch([currentPage, perPage], load);

onMounted(load);

function openDetails(log) {
  selectedLog.value = log;
  showDetailsModal.value = true;
}

function closeDetails() {
  showDetailsModal.value = false;
  selectedLog.value = null;
}

function formatDateTimeBR(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

const ACTION_TONE = {
  create:  { color: 'emerald', icon: 'i-lucide-plus-circle' },
  update:  { color: 'blue',    icon: 'i-lucide-pencil' },
  destroy: { color: 'ruby',    icon: 'i-lucide-trash-2' },
  restore: { color: 'amber',   icon: 'i-lucide-rotate-ccw' },
  denied:  { color: 'violet',  icon: 'i-lucide-shield-x' },
};
function actionBadge(action) {
  return ACTION_TONE[action] || { color: 'slate', icon: 'i-lucide-circle' };
}

function clearFilters() {
  filters.value = {
    entity_type: '', action: '', user_id: '',
    from: '', to: '', q: '',
  };
}

// Helpers pra renderizar o diff. Converte um valor (potencialmente complexo
// como hash/array) em string legível pro humano.
function formatValue(v) {
  if (v === null || v === undefined) return '—';
  if (typeof v === 'boolean') return v ? 'sim' : 'não';
  if (typeof v === 'object') return JSON.stringify(v, null, 2);
  return String(v);
}

// Conjunto de chaves do log selecionado (união de before+after). Marca
// chaves alteradas com base no array `changed_keys` retornado pelo backend.
const diffRows = computed(() => {
  if (!selectedLog.value) return [];
  const before = selectedLog.value.before || {};
  const after  = selectedLog.value.after || {};
  const changedKeys = new Set(selectedLog.value.changed_keys || []);
  const allKeys = [...new Set([...Object.keys(before), ...Object.keys(after)])].sort();
  return allKeys.map(key => ({
    key,
    before: formatValue(before[key]),
    after:  formatValue(after[key]),
    changed: changedKeys.has(key),
  }));
});
</script>

<template>
  <div class="finv2-page" :class="{ 'finv2-page--embedded': embedded }">
    <header v-if="!embedded" class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">Auditoria</h1>
        <p class="finv2-page__subtitle">
          Histórico completo de alterações em entidades financeiras —
          quem fez, quando, o que mudou. Apenas ADMIN, AUDITOR e GERENTE.
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <BeclinicButton
          variant="faded"
          color="slate"
          icon="i-lucide-download"
          label="Exportar CSV"
          size="sm"
          :is-loading="exporting"
          @click="exportCsv"
        />
      </div>
    </header>

    <div class="finv2-page__body">
      <!-- Filtros -->
      <div class="aud-v2__filters">
        <div class="aud-v2__filter aud-v2__filter--grow">
          <FinSearchInput
            v-model="filters.q"
            placeholder="Buscar entidade, ID ou IP…"
          />
        </div>
        <div class="aud-v2__filter">
          <FormSelect
            v-model="filters.entity_type"
            :options="entityTypeOptions"
            placeholder="Entidade"
            searchable
            auto-searchable
          />
        </div>
        <div class="aud-v2__filter">
          <FormSelect
            v-model="filters.action"
            :options="actionOptions"
            placeholder="Ação"
          />
        </div>
        <div class="aud-v2__filter">
          <FormSelect
            v-model="filters.user_id"
            :options="userOptions"
            placeholder="Usuário"
            searchable
            auto-searchable
            clearable
          />
        </div>
        <div class="aud-v2__filter aud-v2__filter--date">
          <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
        </div>
        <div class="aud-v2__filter aud-v2__filter--date">
          <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
        </div>
        <button v-if="hasFilter" type="button" class="aud-v2__clear" @click="clearFilters">
          <i class="i-lucide-x w-3.5 h-3.5" /> Limpar
        </button>
      </div>

      <!-- Tabela -->
      <div class="finv2-table-wrap finv2-hide-mobile">
        <table class="finv2-table">
          <thead>
            <tr>
              <th>Data / hora</th>
              <th>Usuário</th>
              <th>Ação</th>
              <th>Entidade</th>
              <th>IP</th>
              <th>Campos alterados</th>
              <th class="aud-v2__th-actions"></th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="7">
                <div class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
              </td>
            </tr>
            <tr v-else-if="logs.length === 0">
              <td colspan="7">
                <div class="finv2-state">
                  <div class="finv2-state__icon-wrap"><i class="i-lucide-shield-check w-7 h-7" /></div>
                  <p class="finv2-state__title">Nenhuma alteração no filtro</p>
                  <p class="finv2-state__hint">
                    Ajuste os filtros ou use o período mais amplo.
                  </p>
                </div>
              </td>
            </tr>
            <tr
              v-for="log in logs"
              v-else
              :key="log.id"
              class="aud-v2__row"
              @click="openDetails(log)"
            >
              <td class="finv2-table__td-date">{{ formatDateTimeBR(log.created_at) }}</td>
              <td>
                <ProfessionalChip
                  v-if="log.user"
                  :name="log.user.name"
                  :avatar-url="log.user.avatar_url || ''"
                  size="sm"
                />
                <span v-else class="finv2-table__td-muted">Sistema</span>
              </td>
              <td>
                <Badge
                  :label="log.action_label"
                  :color="actionBadge(log.action).color"
                  :icon="actionBadge(log.action).icon"
                  size="xs"
                />
              </td>
              <td>
                <div class="aud-v2__entity-cell">
                  <strong>{{ log.entity_label }}</strong>
                  <span class="aud-v2__entity-id">#{{ log.entity_id }}</span>
                </div>
              </td>
              <td class="finv2-table__td-muted aud-v2__ip">{{ log.ip || '—' }}</td>
              <td>
                <div v-if="(log.changed_keys || []).length > 0" class="aud-v2__keys">
                  <span
                    v-for="k in (log.changed_keys || []).slice(0, 4)"
                    :key="k"
                    class="aud-v2__key-chip"
                  >{{ k }}</span>
                  <span v-if="(log.changed_keys || []).length > 4" class="aud-v2__key-more">
                    +{{ log.changed_keys.length - 4 }}
                  </span>
                </div>
                <span v-else class="finv2-table__td-muted">—</span>
              </td>
              <td class="aud-v2__td-actions">
                <Tooltip label="Ver diff completo">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-eye"
                    @click.stop="openDetails(log)"
                  />
                </Tooltip>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Cards mobile -->
      <div class="finv2-show-mobile">
        <div class="aud-v2__cards">
          <div v-if="loading" class="finv2-state">
            <div class="finv2-spinner" /><span>Carregando…</span>
          </div>
          <div v-else-if="logs.length === 0" class="finv2-state">
            <p class="finv2-state__title">Nenhuma alteração no filtro</p>
          </div>
          <article
            v-for="log in logs"
            v-else
            :key="log.id"
            class="aud-v2__card"
            @click="openDetails(log)"
          >
            <header class="aud-v2__card-header">
              <Badge
                :label="log.action_label"
                :color="actionBadge(log.action).color"
                size="xs"
              />
              <span class="aud-v2__card-date">{{ formatDateTimeBR(log.created_at) }}</span>
            </header>
            <p class="aud-v2__card-body">
              <strong>{{ log.entity_label }} #{{ log.entity_id }}</strong>
              <span class="aud-v2__card-meta">
                por {{ log.user?.name || 'Sistema' }}
                · {{ log.ip || 'sem IP' }}
              </span>
            </p>
            <div v-if="(log.changed_keys || []).length > 0" class="aud-v2__keys">
              <span
                v-for="k in (log.changed_keys || []).slice(0, 3)"
                :key="k"
                class="aud-v2__key-chip"
              >{{ k }}</span>
              <span v-if="(log.changed_keys || []).length > 3" class="aud-v2__key-more">
                +{{ log.changed_keys.length - 3 }}
              </span>
            </div>
          </article>
        </div>
      </div>

      <Pagination
        v-model:current-page="currentPage"
        v-model:per-page="perPage"
        :total-count="meta.total || 0"
        item-label="registros"
      />
    </div>

    <!-- Drawer/modal de detalhes (before vs after) -->
    <Teleport to="body">
      <div
        v-if="showDetailsModal && selectedLog"
        class="aud-v2__details-backdrop"
        @click.self="closeDetails"
      >
        <aside class="aud-v2__details">
          <header class="aud-v2__details-header">
            <div>
              <h2 class="aud-v2__details-title">
                <Badge
                  :label="selectedLog.action_label"
                  :color="actionBadge(selectedLog.action).color"
                  :icon="actionBadge(selectedLog.action).icon"
                  size="xs"
                />
                {{ selectedLog.entity_label }} #{{ selectedLog.entity_id }}
              </h2>
              <p class="aud-v2__details-meta">
                {{ formatDateTimeBR(selectedLog.created_at) }}
                · por {{ selectedLog.user?.name || 'Sistema' }}
                <template v-if="selectedLog.ip">· IP {{ selectedLog.ip }}</template>
              </p>
            </div>
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              @click="closeDetails"
            />
          </header>

          <div class="aud-v2__details-body">
            <div v-if="diffRows.length === 0" class="finv2-state">
              <p class="finv2-state__title">Sem dados de diff</p>
              <p class="finv2-state__hint">
                Esta entrada não registra valores antes/depois (provavelmente acesso negado ou ação sistêmica).
              </p>
            </div>
            <table v-else class="aud-v2__diff-table">
              <thead>
                <tr>
                  <th>Campo</th>
                  <th>Antes</th>
                  <th>Depois</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-for="row in diffRows"
                  :key="row.key"
                  :class="{ 'aud-v2__diff-row--changed': row.changed }"
                >
                  <td class="aud-v2__diff-key">{{ row.key }}</td>
                  <td class="aud-v2__diff-before">
                    <pre v-if="row.before.includes('\n')">{{ row.before }}</pre>
                    <span v-else>{{ row.before }}</span>
                  </td>
                  <td class="aud-v2__diff-after">
                    <pre v-if="row.after.includes('\n')">{{ row.after }}</pre>
                    <span v-else>{{ row.after }}</span>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </aside>
      </div>
    </Teleport>
  </div>
</template>

<style scoped lang="scss">
.aud-v2__filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.aud-v2__filter { min-width: 0; flex: 0 0 180px; }
.aud-v2__filter--grow { flex: 1 1 240px; }
.aud-v2__filter--date { flex: 0 0 150px; }
@media (max-width: 800px) {
  .aud-v2__filter,
  .aud-v2__filter--grow,
  .aud-v2__filter--date { flex: 1 1 100%; }
}
.aud-v2__clear {
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

/* Tabela */
.aud-v2__row {
  cursor: pointer;
  transition: background 0.12s ease;
  &:hover { background: rgb(var(--slate-2)); }
}
.aud-v2__entity-cell { display: flex; flex-direction: column; gap: 1px; }
.aud-v2__entity-id {
  font-size: 11px;
  color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
}
.aud-v2__ip {
  font-family: 'SF Mono', Menlo, monospace;
  font-size: 11.5px;
}
.aud-v2__keys {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
.aud-v2__key-chip {
  display: inline-flex;
  padding: 2px 6px;
  border-radius: 4px;
  background: rgba(245, 158, 11, 0.12);
  color: rgb(var(--amber-11));
  font-size: 10.5px;
  font-weight: 500;
  font-family: 'SF Mono', Menlo, monospace;
}
.aud-v2__key-more {
  display: inline-flex;
  padding: 2px 6px;
  font-size: 10.5px;
  color: rgb(var(--slate-9));
  font-weight: 500;
}
.aud-v2__th-actions { width: 56px; }
.aud-v2__td-actions { text-align: right; white-space: nowrap; }

/* Cards mobile */
.aud-v2__cards { display: flex; flex-direction: column; gap: 10px; }
.aud-v2__card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 12px 14px;
  display: flex;
  flex-direction: column;
  gap: 8px;
  cursor: pointer;
  transition: border-color 0.12s ease;
  &:hover { border-color: rgb(var(--blue-7)); }
}
.aud-v2__card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 8px;
}
.aud-v2__card-date {
  font-size: 11.5px;
  color: rgb(var(--slate-9));
}
.aud-v2__card-body {
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
  font-size: 13px;
  color: rgb(var(--slate-12));
}
.aud-v2__card-meta {
  font-size: 12px;
  color: rgb(var(--slate-9));
  font-weight: 400;
}

/* Drawer detalhes */
.aud-v2__details-backdrop {
  position: fixed;
  inset: 0;
  z-index: 9999;
  background: rgba(15, 23, 42, 0.55);
  backdrop-filter: blur(4px);
  display: flex;
  justify-content: flex-end;
}
.aud-v2__details {
  width: min(780px, 100%);
  height: 100%;
  background: rgb(var(--slate-1));
  border-left: 1px solid rgb(var(--slate-4));
  display: flex;
  flex-direction: column;
  box-shadow: -10px 0 25px -8px rgba(0, 0, 0, 0.2);
}
.aud-v2__details-header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  padding: 18px 22px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.aud-v2__details-title {
  margin: 0;
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}
.aud-v2__details-meta {
  margin: 6px 0 0;
  font-size: 12px;
  color: rgb(var(--slate-9));
}
.aud-v2__details-body {
  flex: 1;
  overflow-y: auto;
  padding: 20px 22px;
}

.aud-v2__diff-table {
  width: 100%;
  border-collapse: collapse;
  th, td {
    padding: 10px 12px;
    text-align: left;
    vertical-align: top;
    font-size: 12.5px;
    border-bottom: 1px solid rgb(var(--slate-3));
  }
  thead th {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: rgb(var(--slate-9));
    font-weight: 600;
    background: rgb(var(--slate-2));
  }
  pre {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    font-family: 'SF Mono', Menlo, monospace;
    font-size: 11.5px;
    line-height: 1.4;
  }
}
.aud-v2__diff-key {
  font-family: 'SF Mono', Menlo, monospace;
  color: rgb(var(--slate-12));
  font-weight: 500;
  width: 22%;
}
.aud-v2__diff-before {
  color: rgb(var(--slate-9));
  text-decoration: line-through;
  text-decoration-color: rgba(220, 38, 38, 0.4);
}
.aud-v2__diff-after {
  color: rgb(var(--slate-12));
}
.aud-v2__diff-row--changed {
  background: rgba(245, 158, 11, 0.06);
}
.aud-v2__diff-row--changed .aud-v2__diff-after {
  font-weight: 600;
  color: rgb(var(--emerald-11));
}
.aud-v2__diff-row--changed .aud-v2__diff-before {
  color: rgb(var(--ruby-11));
}
</style>
