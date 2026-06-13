<script setup>
/**
 * LGPD — Solicitações de anonimização (canon F-33 §parte 2).
 *
 * Workflow: paciente solicita exclusão → ADMIN aprova → executa
 * anonimização (substitui nome/CPF/email/telefone/endereço por hash
 * irreversível, MAS preserva lançamentos financeiros pelo patient_id).
 *
 * Permissões: ADMIN+AUDITOR+GERENTE veem; criar requer ADMIN/GERENTE;
 * approve/reject/execute requer ADMIN.
 *
 * UX:
 *   • Filtros por status + período
 *   • KPIs dos contadores (pending/approved/executed/rejected)
 *   • Tabela com ações condicionais (Aprovar/Rejeitar pra pending,
 *     Executar/Cancelar pra approved)
 *   • Botão "Nova solicitação" → modal busca paciente + motivo
 *   • Confirmação obrigatória pra ações irreversíveis (Executar)
 */
/* global axios */
import { ref, computed, onMounted, watch } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import DatePickerBR from '@plugins/beclinic_core/frontend/components/DatePickerBR.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import ProfessionalChip from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ProfessionalChip.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import FinancialV2 from '../api/financialV2';
import '@plugins/financial/frontend/styles/financial.scss';

const route = window.location.pathname;
// Extrai accountId da URL (padrão Chatwoot/Klivy /app/accounts/:id/...).
const ACCOUNT_ID = route.match(/accounts\/(\d+)/)?.[1];

const notifyError = msg => useNotification.error(msg);
const notifySuccess = msg => useNotification.success(msg);

const data = ref([]);
const meta = ref({});
const loading = ref(false);
const acting = ref(null); // request id sendo processado

const filters = ref({
  status: '',
  from: '',
  to: '',
});
const currentPage = ref(1);
const perPage = ref(25);

// Modais de confirmação por ação
const showApprove = ref(false);
const showReject = ref(false);
const showExecute = ref(false);
const showCancel = ref(false);
const targetRequest = ref(null);
const rejectionReason = ref('');

// Modal "Nova solicitação" — recepção/ADMIN cria em nome do paciente
// (paciente solicita por telefone/email/etc., funcionário registra aqui).
const showNewModal = ref(false);
const newRequest = ref({ patient_id: null, reason: '' });
const creating = ref(false);
const patientSearch = ref('');
const patientResults = ref([]);
const searchingPatients = ref(false);
let searchDebounce = null;

const patientOptions = computed(() =>
  patientResults.value.map(p => ({
    value: p.id,
    label: `${p.name}${p.cpf ? ' · ' + p.cpf : ''}`,
  })),
);

// Busca paciente por nome/CPF/telefone. Endpoint v1 do plugins/patients —
// aceita `q` (ILIKE em name + LIKE em phone/cpf se contém 3+ dígitos).
// Resposta: { payload: [...], meta: {...} }
async function searchPatients(query) {
  if (!query || query.length < 2) {
    patientResults.value = [];
    return;
  }
  searchingPatients.value = true;
  try {
    // `axios` é o global do Chatwoot (com auth headers configurados);
    // sem isso o request volta 401.
    const { data } = await axios.get(
      `/api/v1/accounts/${ACCOUNT_ID}/patients`,
      { params: { q: query, per_page: 20 } },
    );
    const list = data?.payload || data?.data || (Array.isArray(data) ? data : []);
    patientResults.value = list;
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[LgpdV2] busca paciente falhou', err);
    patientResults.value = [];
  } finally {
    searchingPatients.value = false;
  }
}

watch(patientSearch, (val) => {
  clearTimeout(searchDebounce);
  searchDebounce = setTimeout(() => searchPatients(val), 250);
});

function openNew() {
  newRequest.value = { patient_id: null, reason: '' };
  patientSearch.value = '';
  patientResults.value = [];
  showNewModal.value = true;
}

async function submitNew() {
  if (!newRequest.value.patient_id) {
    notifyError('Selecione o paciente.');
    return;
  }
  if (!newRequest.value.reason?.trim()) {
    notifyError('Informe o motivo da solicitação.');
    return;
  }
  creating.value = true;
  try {
    await FinancialV2.lgpdRequests.create({
      lgpd_request: {
        patient_id: newRequest.value.patient_id,
        reason: newRequest.value.reason.trim(),
      },
    });
    notifySuccess('Solicitação criada — aguardando aprovação ADMIN.');
    showNewModal.value = false;
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.errors?.join('; ') || 'Falha ao criar solicitação.');
  } finally {
    creating.value = false;
  }
}

const STATUS_OPTIONS = [
  { value: '',          label: 'Todos os status' },
  { value: 'pending',   label: 'Pendente' },
  { value: 'approved',  label: 'Aprovada' },
  { value: 'executed',  label: 'Executada' },
  { value: 'rejected',  label: 'Rejeitada' },
  { value: 'cancelled', label: 'Cancelada' },
];

const STATUS_BADGE = {
  pending:   { color: 'amber',   label: 'Pendente',   icon: 'i-lucide-clock' },
  approved:  { color: 'blue',    label: 'Aprovada',   icon: 'i-lucide-check' },
  executed:  { color: 'emerald', label: 'Executada',  icon: 'i-lucide-shield-check' },
  rejected:  { color: 'ruby',    label: 'Rejeitada',  icon: 'i-lucide-x' },
  cancelled: { color: 'slate',   label: 'Cancelada',  icon: 'i-lucide-ban' },
};

const summary = computed(() => meta.value.summary || {});
const hasFilter = computed(() =>
  filters.value.status || filters.value.from || filters.value.to,
);

async function load() {
  loading.value = true;
  try {
    const params = { page: currentPage.value, per_page: perPage.value };
    if (filters.value.status) params.status = filters.value.status;
    if (filters.value.from) params.from = filters.value.from;
    if (filters.value.to) params.to = filters.value.to;

    const { data: response } = await FinancialV2.lgpdRequests.index(params);
    data.value = response?.data || [];
    meta.value = response?.meta || {};
  } catch (err) {
    notifyError(err?.response?.data?.error === 'forbidden'
      ? 'Acesso negado. Apenas ADMIN/AUDITOR/GERENTE.'
      : 'Falha ao carregar solicitações LGPD.');
  } finally {
    loading.value = false;
  }
}

watch(filters, () => { currentPage.value = 1; load(); }, { deep: true });
watch([currentPage, perPage], load);
onMounted(load);

function formatDateTimeBR(iso) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleString('pt-BR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

function statusBadge(status) {
  return STATUS_BADGE[status] || { color: 'slate', label: status, icon: 'i-lucide-circle' };
}

function askApprove(req)   { targetRequest.value = req; showApprove.value = true; }
function askReject(req)    { targetRequest.value = req; rejectionReason.value = ''; showReject.value = true; }
function askExecute(req)   { targetRequest.value = req; showExecute.value = true; }
function askCancel(req)    { targetRequest.value = req; showCancel.value = true; }

async function performAction(action, payload = {}) {
  const req = targetRequest.value;
  if (!req) return;
  acting.value = req.id;
  try {
    await FinancialV2.lgpdRequests[action](req.id, payload);
    notifySuccess(actionSuccessMessage(action));
    closeAllModals();
    await load();
  } catch (err) {
    notifyError(err?.response?.data?.error || `Falha ao ${actionLabel(action)}.`);
  } finally {
    acting.value = null;
  }
}

function actionSuccessMessage(action) {
  return ({
    approve: 'Solicitação aprovada.',
    reject:  'Solicitação rejeitada.',
    execute: 'Anonimização executada — dados pessoais removidos. Lançamentos financeiros preservados.',
    cancel:  'Solicitação cancelada.',
  })[action] || 'Ação concluída.';
}
function actionLabel(action) {
  return ({ approve: 'aprovar', reject: 'rejeitar', execute: 'executar anonimização', cancel: 'cancelar' })[action] || action;
}

async function confirmApprove() { await performAction('approve'); }
async function confirmReject() {
  if (!rejectionReason.value.trim()) {
    notifyError('Informe o motivo da rejeição.');
    return;
  }
  await performAction('reject', { rejection_reason: rejectionReason.value.trim() });
}
async function confirmExecute() { await performAction('execute'); }
async function confirmCancel() { await performAction('cancel'); }

function closeAllModals() {
  showApprove.value = false;
  showReject.value = false;
  showExecute.value = false;
  showCancel.value = false;
  targetRequest.value = null;
  rejectionReason.value = '';
}

function clearFilters() {
  filters.value = { status: '', from: '', to: '' };
}

function patientLabel(req) {
  return req.patient?.name || `Paciente ID #${req.patient?.id || '?'}`;
}

// PR audit 2026-05-21: `embedded=true` esconde o header próprio quando esta
// page é renderizada como tab dentro de SettingsV2 (evita duplicação com o
// header "Configurações financeiras"). Ver SettingsV2.vue para contexto.
defineProps({ embedded: { type: Boolean, default: false } });
</script>

<template>
  <div class="finv2-page" :class="{ 'finv2-page--embedded': embedded }">
    <header v-if="!embedded" class="finv2-page__header">
      <div class="finv2-page__header-text">
        <h1 class="finv2-page__title">LGPD — Anonimização</h1>
        <p class="finv2-page__subtitle">
          Workflow de solicitações de anonimização de paciente. Apenas ADMIN
          aprova/executa. Lançamentos financeiros do paciente são preservados
          (FK mantida) — só os dados pessoais somem (hash irreversível).
        </p>
      </div>
      <div class="finv2-page__header-actions">
        <BeclinicButton
          variant="solid"
          color="blue"
          icon="i-lucide-plus"
          label="Nova solicitação"
          size="sm"
          @click="openNew"
        />
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
            <span class="finv2-kpi__label">Pendentes</span>
            <strong class="finv2-kpi__value">{{ summary.pending || 0 }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--neutral">
            <i class="i-lucide-check w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Aprovadas (a executar)</span>
            <strong class="finv2-kpi__value">{{ summary.approved || 0 }}</strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--positive">
            <i class="i-lucide-shield-check w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Executadas</span>
            <strong class="finv2-kpi__value finv2-kpi__value--positive">
              {{ summary.executed || 0 }}
            </strong>
          </div>
        </div>
        <div class="finv2-kpi">
          <div class="finv2-kpi__icon finv2-kpi__icon--danger">
            <i class="i-lucide-x w-4 h-4" />
          </div>
          <div class="finv2-kpi__content">
            <span class="finv2-kpi__label">Rejeitadas</span>
            <strong class="finv2-kpi__value finv2-kpi__value--danger">
              {{ summary.rejected || 0 }}
            </strong>
          </div>
        </div>
      </div>

      <!-- Filtros -->
      <div class="lgpd-v2__filters">
        <div class="lgpd-v2__filter">
          <FormSelect v-model="filters.status" :options="STATUS_OPTIONS" placeholder="Status" />
        </div>
        <div class="lgpd-v2__filter lgpd-v2__filter--date">
          <DatePickerBR v-model="filters.from" placeholder="Data inicial" />
        </div>
        <div class="lgpd-v2__filter lgpd-v2__filter--date">
          <DatePickerBR v-model="filters.to" placeholder="Data final" :min="filters.from || null" />
        </div>
        <button v-if="hasFilter" type="button" class="lgpd-v2__clear" @click="clearFilters">
          <i class="i-lucide-x w-3.5 h-3.5" /> Limpar
        </button>
      </div>

      <!-- Tabela -->
      <div class="finv2-table-wrap finv2-hide-mobile">
        <table class="finv2-table">
          <thead>
            <tr>
              <th>Paciente</th>
              <th>Status</th>
              <th>Solicitada</th>
              <th>Aprovada</th>
              <th>Executada</th>
              <th>Motivo</th>
              <th class="lgpd-v2__th-actions">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr v-if="loading">
              <td colspan="7">
                <div class="finv2-state"><div class="finv2-spinner" /><span>Carregando…</span></div>
              </td>
            </tr>
            <tr v-else-if="data.length === 0">
              <td colspan="7">
                <div class="finv2-state">
                  <div class="finv2-state__icon-wrap"><i class="i-lucide-shield w-7 h-7" /></div>
                  <p class="finv2-state__title">Nenhuma solicitação no filtro</p>
                  <p class="finv2-state__hint">Solicitações de anonimização aparecem aqui.</p>
                </div>
              </td>
            </tr>
            <tr v-for="r in data" v-else :key="r.id">
              <td>
                <ProfessionalChip
                  v-if="r.patient"
                  :name="patientLabel(r)"
                  :avatar-url="r.patient.avatar_url || ''"
                  size="sm"
                />
                <span v-else class="finv2-table__td-muted">—</span>
              </td>
              <td>
                <Badge
                  :label="statusBadge(r.status).label"
                  :color="statusBadge(r.status).color"
                  :icon="statusBadge(r.status).icon"
                  size="xs"
                />
              </td>
              <td class="finv2-table__td-date">{{ formatDateTimeBR(r.requested_at) }}</td>
              <td class="finv2-table__td-date">
                {{ formatDateTimeBR(r.approved_at) }}
                <div v-if="r.approved_by" class="lgpd-v2__by">por {{ r.approved_by.name }}</div>
              </td>
              <td class="finv2-table__td-date">
                {{ formatDateTimeBR(r.executed_at) }}
                <div v-if="r.executed_by" class="lgpd-v2__by">por {{ r.executed_by.name }}</div>
              </td>
              <td class="finv2-table__td-muted lgpd-v2__reason">
                {{ r.reason || r.rejection_reason || '—' }}
              </td>
              <td class="lgpd-v2__td-actions">
                <template v-if="r.status === 'pending'">
                  <Tooltip label="Aprovar">
                    <BeclinicButton size="xs" variant="ghost" color="blue" icon="i-lucide-check" @click="askApprove(r)" />
                  </Tooltip>
                  <Tooltip label="Rejeitar">
                    <BeclinicButton size="xs" variant="ghost" color="ruby" icon="i-lucide-x" @click="askReject(r)" />
                  </Tooltip>
                  <Tooltip label="Cancelar">
                    <BeclinicButton size="xs" variant="ghost" color="slate" icon="i-lucide-ban" @click="askCancel(r)" />
                  </Tooltip>
                </template>
                <template v-else-if="r.status === 'approved'">
                  <Tooltip label="Executar anonimização (irreversível)">
                    <BeclinicButton size="xs" variant="solid" color="ruby" icon="i-lucide-shield-x"
                                    label="Executar" @click="askExecute(r)" />
                  </Tooltip>
                  <Tooltip label="Cancelar">
                    <BeclinicButton size="xs" variant="ghost" color="slate" icon="i-lucide-ban" @click="askCancel(r)" />
                  </Tooltip>
                </template>
                <span v-else class="finv2-table__td-muted">—</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <Pagination
        v-model:current-page="currentPage"
        v-model:per-page="perPage"
        :total-count="meta.total || 0"
        item-label="solicitações"
      />

      <!-- Aviso final -->
      <div class="lgpd-v2__note">
        <i class="i-lucide-shield-alert w-4 h-4" />
        <span>
          <strong>Atenção:</strong> a execução substitui nome, CPF, email,
          telefone e endereço do paciente por hashes irreversíveis.
          <strong>Não há como desfazer.</strong>
          Lançamentos financeiros e clínicos permanecem ligados ao paciente
          (apenas o nome aparece como "Paciente Anonimizado #ID").
        </span>
      </div>
    </div>

    <!-- Modais -->
    <ConfirmDangerModal
      v-model:show="showApprove"
      title="Aprovar solicitação?"
      :message="targetRequest ? `Aprovar a solicitação de ${patientLabel(targetRequest)}? Após aprovação, ADMIN ainda precisa executar manualmente — não anonimiza automaticamente.` : ''"
      confirm-label="Aprovar"
      :loading="acting === targetRequest?.id"
      @confirm="confirmApprove"
    />

    <ConfirmDangerModal
      v-model:show="showReject"
      title="Rejeitar solicitação?"
      :message="targetRequest ? `Rejeitar a solicitação de ${patientLabel(targetRequest)}? Informe o motivo abaixo (obrigatório).` : ''"
      confirm-label="Rejeitar"
      :loading="acting === targetRequest?.id"
      @confirm="confirmReject"
    >
      <textarea
        v-model="rejectionReason"
        class="finv2-input lgpd-v2__rejection-input"
        rows="3"
        placeholder="Motivo da rejeição (ex.: não há vínculo com este paciente, dados ainda em retenção fiscal obrigatória, etc.)"
      />
    </ConfirmDangerModal>

    <ConfirmDangerModal
      v-model:show="showExecute"
      title="EXECUTAR anonimização?"
      :message="targetRequest ? `Esta ação é IRREVERSÍVEL. Os dados pessoais de ${patientLabel(targetRequest)} (nome, CPF, email, telefone, endereço, etc.) serão substituídos por hashes irreversíveis. Os lançamentos financeiros e clínicos serão preservados, mas sem mais possibilidade de identificar a pessoa. Confirmar?` : ''"
      confirm-label="Sim, executar agora"
      :loading="acting === targetRequest?.id"
      @confirm="confirmExecute"
    />

    <ConfirmDangerModal
      v-model:show="showCancel"
      title="Cancelar solicitação?"
      :message="targetRequest ? `Cancelar a solicitação de ${patientLabel(targetRequest)}? Pode ser reaberta criando uma nova depois.` : ''"
      confirm-label="Cancelar solicitação"
      :loading="acting === targetRequest?.id"
      @confirm="confirmCancel"
    />

    <!-- Modal Nova solicitação — recepção/ADMIN registra em nome do paciente.
         Sem close-on-outside-click intencionalmente: evita perder o texto do
         motivo se o usuário clicar fora por engano. Fecha só pelo X ou Cancelar. -->
    <Teleport to="body">
      <div v-if="showNewModal" class="lgpd-v2__new-backdrop">
        <div class="lgpd-v2__new-modal" role="dialog" aria-modal="true">
          <header class="lgpd-v2__new-header">
            <h2 class="lgpd-v2__new-title">
              <i class="i-lucide-shield-plus w-4 h-4" /> Nova solicitação LGPD
            </h2>
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-x"
              @click="showNewModal = false"
            />
          </header>
          <div class="lgpd-v2__new-body">
            <p class="lgpd-v2__new-hint">
              O paciente solicitou exclusão por canal externo
              (telefone/email/WhatsApp/papel). Registre a solicitação aqui —
              um ADMIN vai aprovar e executar a anonimização.
            </p>

            <label class="lgpd-v2__new-field">
              <span class="lgpd-v2__new-label">Buscar paciente *</span>
              <input
                v-model="patientSearch"
                type="search"
                class="finv2-input"
                placeholder="Digite nome ou CPF (mín. 2 caracteres)…"
              />
              <span v-if="searchingPatients" class="lgpd-v2__new-search-hint">Buscando…</span>
            </label>

            <label v-if="patientOptions.length > 0" class="lgpd-v2__new-field">
              <span class="lgpd-v2__new-label">Paciente *</span>
              <FormSelect
                v-model="newRequest.patient_id"
                :options="patientOptions"
                placeholder="Selecione o paciente"
                searchable
              />
            </label>

            <label class="lgpd-v2__new-field">
              <span class="lgpd-v2__new-label">Motivo da solicitação *</span>
              <textarea
                v-model="newRequest.reason"
                class="finv2-input lgpd-v2__new-textarea"
                rows="3"
                placeholder="Ex.: paciente solicitou exclusão dos dados via email em 10/05/2026 conforme LGPD Art. 18"
              />
            </label>
          </div>
          <footer class="lgpd-v2__new-footer">
            <BeclinicButton
              variant="ghost"
              color="slate"
              label="Cancelar"
              :disabled="creating"
              @click="showNewModal = false"
            />
            <BeclinicButton
              variant="solid"
              color="blue"
              icon="i-lucide-check"
              label="Criar solicitação"
              :is-loading="creating"
              :disabled="!newRequest.patient_id || !newRequest.reason?.trim()"
              @click="submitNew"
            />
          </footer>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped lang="scss">
.lgpd-v2__filters {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 10px;
}
.lgpd-v2__filter { min-width: 0; flex: 0 0 200px; }
.lgpd-v2__filter--date { flex: 0 0 160px; }
@media (max-width: 640px) {
  .lgpd-v2__filter, .lgpd-v2__filter--date { flex: 1 1 100%; }
}
.lgpd-v2__clear {
  display: inline-flex; align-items: center; gap: 4px;
  padding: 8px 12px; border-radius: 8px;
  border: 1px solid rgb(var(--slate-5));
  background: rgb(var(--slate-2));
  font-size: 12px; color: rgb(var(--slate-11));
  cursor: pointer;
  &:hover { background: rgb(var(--slate-3)); }
}

.lgpd-v2__by {
  font-size: 11px;
  color: rgb(var(--slate-9));
}

.lgpd-v2__reason {
  max-width: 300px;
  overflow: hidden;
  text-overflow: ellipsis;
}

.lgpd-v2__th-actions { width: 200px; text-align: right; }
.lgpd-v2__td-actions {
  text-align: right;
  white-space: nowrap;
  display: flex;
  justify-content: flex-end;
  gap: 4px;
}

.lgpd-v2__note {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 12px 14px;
  border-radius: 10px;
  background: rgba(220, 38, 38, 0.08);
  border: 1px solid rgba(220, 38, 38, 0.32);
  border-left: 3px solid #dc2626;
  font-size: 13px;
  color: rgb(var(--slate-12));
  line-height: 1.5;
  i { margin-top: 2px; flex-shrink: 0; color: #dc2626; }
  strong { color: rgb(var(--ruby-11)); font-weight: 600; }
}

.lgpd-v2__rejection-input {
  width: 100%;
  margin-top: 8px;
  height: auto;
  padding: 10px 12px;
  resize: vertical;
}

/* ── Modal Nova solicitação ──────────────────────────────────── */
.lgpd-v2__new-backdrop {
  position: fixed; inset: 0;
  background: rgba(15, 23, 42, 0.6);
  backdrop-filter: blur(4px);
  display: flex; align-items: center; justify-content: center;
  z-index: 9999; padding: 16px;
}
.lgpd-v2__new-modal {
  width: min(560px, 100%);
  max-height: calc(100vh - 32px);
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 16px;
  display: flex; flex-direction: column;
  overflow: hidden;
  box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.4);
}
.lgpd-v2__new-header {
  display: flex; justify-content: space-between; align-items: center;
  padding: 18px 20px;
  border-bottom: 1px solid rgb(var(--slate-4));
}
.lgpd-v2__new-title {
  margin: 0; font-size: 16px; font-weight: 600;
  color: rgb(var(--slate-12));
  display: flex; align-items: center; gap: 8px;
}
.lgpd-v2__new-body {
  flex: 1; overflow-y: auto;
  padding: 18px 20px;
  display: flex; flex-direction: column; gap: 14px;
}
.lgpd-v2__new-hint {
  margin: 0;
  padding: 10px 12px;
  background: rgb(var(--slate-2));
  border-left: 3px solid rgb(var(--blue-8));
  border-radius: 6px;
  font-size: 12.5px;
  color: rgb(var(--slate-11));
  line-height: 1.5;
}
.lgpd-v2__new-field { display: flex; flex-direction: column; gap: 5px; }
.lgpd-v2__new-label {
  font-size: 12px; font-weight: 500; color: rgb(var(--slate-11));
}
.lgpd-v2__new-search-hint {
  font-size: 11px; color: rgb(var(--slate-9)); margin-top: 4px;
}
.lgpd-v2__new-textarea {
  height: auto; padding: 10px 12px; resize: vertical;
}
.lgpd-v2__new-footer {
  display: flex; justify-content: flex-end; gap: 8px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
}
</style>
