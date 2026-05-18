<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * ProceduresTab — Aba "Procedimentos / Sessões" do prontuário do paciente.
 *
 * Registro detalhado de aplicações, produtos utilizados e sessões clínicas.
 * Form para nova sessão (procedimento, área, produto, lote, intercorrências,
 * resultado, retorno) + histórico filtrável (procedimento + intervalo de datas).
 *
 * Auto-suficiente: lê patientId da rota e faz seu próprio fetch.
 *
 * Recebe `patient` como prop apenas para fallback de `responsibleProfessional`
 * quando o log de sessão não tem `professional_name`. Emite `open-exams` quando
 * o usuário clica em "Fotos Antes/Depois" para o pai trocar a aba ativa.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor).
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import SessionLogsAPI from '@plugins/patients/frontend/api/patients/sessionLogs';

const props = defineProps({
  patient: { type: Object, required: true },
});
const emit = defineEmits(['open-exams']);

const route = useRoute();

const BRT = 'America/Sao_Paulo';

// ── State ──────────────────────────────────────────────────
const sessionLogs = ref([]);
const isSessionsLoading = ref(false);
const isSavingSession = ref(false);
const sessionHistoryFilter = ref({
  procedure_name: '',
  date_from: '',
  date_to: '',
});
const showFilterPanel = ref(false);

const newSession = ref({
  procedure_name: '',
  area_treated: '',
  product_name: '',
  quantity: '',
  batch: '',
  complications: '',
  result_observed: '',
  return_needed: false,
  return_in_days: null,
  performed_at: new Date().toISOString().split('T')[0],
  duration_minutes: 30,
});

const showConfirmDeleteSession = ref(false);
const sessionToDelete = ref(null);

// ── Computeds ──────────────────────────────────────────────
const uniqueProceduresLogged = computed(() => {
  const names = sessionLogs.value
    .map(log => log.procedure_name || log.treatment_plan_title)
    .filter(Boolean);
  return [...new Set(names)].sort();
});

// ── Actions ────────────────────────────────────────────────
const resetSessionForm = () => {
  newSession.value = {
    procedure_name: '',
    area_treated: '',
    product_name: '',
    quantity: '',
    batch: '',
    complications: '',
    result_observed: '',
    return_needed: false,
    return_in_days: null,
    performed_at: new Date().toISOString().split('T')[0],
    duration_minutes: 30,
  };
};

const fetchSessionLogs = async () => {
  isSessionsLoading.value = true;
  try {
    const { data } = await SessionLogsAPI.get(route.params.patientId);
    sessionLogs.value = Array.isArray(data)
      ? data
      : data?.data || data?.payload || [];
  } catch (error) {
    useAlert('Erro ao carregar sessões.');
  } finally {
    isSessionsLoading.value = false;
  }
};

const saveSession = async () => {
  if (!newSession.value.performed_at) {
    useAlert('Informe a data da sessão.');
    return;
  }
  isSavingSession.value = true;
  try {
    const payload = {
      performed_at: newSession.value.performed_at,
      procedure_name: newSession.value.procedure_name,
      duration_minutes: newSession.value.duration_minutes || 30,
      complications: newSession.value.complications || null,
      result_observed: newSession.value.result_observed || null,
      return_needed: !!newSession.value.return_in_days,
      return_in_days: newSession.value.return_in_days || null,
      areas_treated: newSession.value.area_treated
        ? [
            {
              region: newSession.value.area_treated,
              description: newSession.value.procedure_name,
            },
          ]
        : [],
      products_used: newSession.value.product_name
        ? [
            {
              name: newSession.value.product_name,
              quantity: newSession.value.quantity || '1',
              unit: 'un',
              batch: newSession.value.batch || null,
            },
          ]
        : [],
    };
    await SessionLogsAPI.create(route.params.patientId, payload);
    useAlert('Sessão registrada com sucesso!');
    resetSessionForm();
    await fetchSessionLogs();
  } catch (error) {
    const msg = error?.response?.data?.error || 'Erro ao registrar sessão.';
    useAlert(msg);
  } finally {
    isSavingSession.value = false;
  }
};

const registerSession = () => {
  document
    .querySelector('.session-form-card')
    ?.scrollIntoView({ behavior: 'smooth', block: 'start' });
};

const requestDeleteSessionLog = logId => {
  sessionToDelete.value = logId;
  showConfirmDeleteSession.value = true;
};

const cancelDeleteSessionLog = () => {
  showConfirmDeleteSession.value = false;
  sessionToDelete.value = null;
};

const confirmDeleteSessionLog = async () => {
  if (!sessionToDelete.value) return;
  try {
    await SessionLogsAPI.delete(route.params.patientId, sessionToDelete.value);
    useAlert('Registro removido com sucesso.');
    await fetchSessionLogs();
  } catch (error) {
    useAlert('Erro ao remover sessão.');
  } finally {
    cancelDeleteSessionLog();
  }
};

const toggleFilterPanel = () => {
  showFilterPanel.value = !showFilterPanel.value;
};

const applySessionFilter = async () => {
  isSessionsLoading.value = true;
  try {
    const params = {};
    if (sessionHistoryFilter.value.procedure_name)
      params.procedure_name = sessionHistoryFilter.value.procedure_name;
    if (sessionHistoryFilter.value.date_from)
      params.from = sessionHistoryFilter.value.date_from;
    if (sessionHistoryFilter.value.date_to)
      params.to = sessionHistoryFilter.value.date_to;
    const { data } = await SessionLogsAPI.get(route.params.patientId, params);
    sessionLogs.value = Array.isArray(data)
      ? data
      : data?.data || data?.payload || [];
    showFilterPanel.value = false;
    useAlert(`${sessionLogs.value.length} sessão(ões) encontrada(s).`);
  } catch (error) {
    useAlert('Erro ao filtrar histórico.');
  } finally {
    isSessionsLoading.value = false;
  }
};

const clearSessionFilter = async () => {
  sessionHistoryFilter.value = {
    procedure_name: '',
    date_from: '',
    date_to: '',
  };
  showFilterPanel.value = false;
  await fetchSessionLogs();
};

const openBeforeAfterPhotos = () => {
  emit('open-exams');
};

onMounted(() => {
  fetchSessionLogs();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Procedimentos e Sessões
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Registro detalhado de aplicações, produtos utilizados e sessões
          clínicas.
        </p>
      </div>
      <div class="flex items-center gap-3" style="position: relative">
        <button class="geral-header-btn" @click="toggleFilterPanel">
          <i class="i-lucide-sliders-horizontal w-4 h-4" />
          Filtrar
        </button>
        <button
          class="btn-primary flex items-center gap-2"
          @click="registerSession"
        >
          <i class="i-lucide-plus w-4 h-4" />
          Registrar Sessão
        </button>

        <!-- Painel de Filtro dropdown -->
        <div v-if="showFilterPanel" class="proc-filter-panel">
          <div class="flex items-center justify-between mb-4">
            <h5
              class="text-sm font-semibold"
              style="color: rgb(var(--slate-12))"
            >
              Filtrar Histórico
            </h5>
            <button
              class="proc-filter-close"
              @click="showFilterPanel = false"
            >
              <i class="i-lucide-x w-3.5 h-3.5" />
            </button>
          </div>
          <div class="flex flex-col gap-3">
            <div class="proc-filter-group">
              <label class="proc-filter-label">Procedimento</label>
              <select
                v-model="sessionHistoryFilter.procedure_name"
                class="proc-filter-input"
              >
                <option value="">Todos os procedimentos</option>
                <option
                  v-for="proc in uniqueProceduresLogged"
                  :key="proc"
                  :value="proc"
                >
                  {{ proc }}
                </option>
              </select>
            </div>
            <div class="proc-filter-date-grid">
              <div class="proc-filter-group">
                <label class="proc-filter-label">Data Inicial</label>
                <input
                  v-model="sessionHistoryFilter.date_from"
                  type="date"
                  class="proc-filter-input"
                />
              </div>
              <div class="proc-filter-group">
                <label class="proc-filter-label">Data Final</label>
                <input
                  v-model="sessionHistoryFilter.date_to"
                  type="date"
                  class="proc-filter-input"
                />
              </div>
            </div>
            <div class="proc-filter-actions">
              <button
                class="proc-filter-btn proc-filter-btn--secondary"
                @click="clearSessionFilter"
              >
                Limpar
              </button>
              <button
                class="proc-filter-btn proc-filter-btn--primary"
                @click="applySessionFilter"
              >
                Aplicar
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- reg-form-grid: Formulário + Histórico como reg-sections -->
    <div class="reg-form-grid">
      <!-- Formulário: Registrar Novo Procedimento -->
      <div class="reg-section session-form-card">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-cyan">
              <i class="i-lucide-syringe w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Registrar Novo Procedimento</span>
              <span class="reg-section-subtitle"
                >Preencha os campos abaixo e salve a sessão clínica</span
              >
            </div>
          </div>
          <div class="flex items-center gap-3">
            <span class="text-xs text-slate-500">Data da sessão:</span>
            <input
              v-model="newSession.performed_at"
              type="date"
              class="form-input proc-date-input"
            />
          </div>
        </div>

        <div class="reg-section-body">
          <!-- Linha 1: Procedimento + Área + Retorno -->
          <div class="reg-field-grid-3">
            <div class="form-group">
              <label class="form-label"
                >Procedimento Realizado <span class="reg-required">*</span></label
              >
              <input
                v-model="newSession.procedure_name"
                type="text"
                class="form-input"
                placeholder="Ex: Aplicação de Toxina Botulínica"
              />
            </div>
            <div class="form-group">
              <label class="form-label">Área Tratada</label>
              <input
                v-model="newSession.area_treated"
                type="text"
                class="form-input"
                placeholder="Ex: Terço superior da face"
              />
            </div>
            <div class="form-group">
              <label class="form-label">Retorno em (Dias)</label>
              <input
                v-model="newSession.return_in_days"
                type="number"
                class="form-input"
                placeholder="Ex: 15, 30"
                min="1"
              />
            </div>
          </div>

          <!-- Linha 2: Produto + Quantidade + Lote -->
          <div class="reg-field-grid-3">
            <div class="form-group">
              <label class="form-label">Produto Utilizado</label>
              <input
                v-model="newSession.product_name"
                type="text"
                class="form-input"
                placeholder="Ex: Botox (Allergan)"
              />
            </div>
            <div class="form-group">
              <label class="form-label">Quantidade / Dose</label>
              <input
                v-model="newSession.quantity"
                type="text"
                class="form-input"
                placeholder="Ex: 50U"
              />
            </div>
            <div class="form-group">
              <label class="form-label">Lote / Validade</label>
              <input
                v-model="newSession.batch"
                type="text"
                class="form-input"
                placeholder="Ex: ABC1234 | 10/2026"
              />
            </div>
          </div>

          <!-- Linha 3: Intercorrências + Resultado -->
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">Intercorrências no Procedimento</label>
              <textarea
                v-model="newSession.complications"
                class="form-input form-textarea"
                rows="3"
                placeholder="Relato de hematomas, dor além do esperado, etc..."
              />
            </div>
            <div class="form-group">
              <label class="form-label">Resultado Imediato Observado</label>
              <textarea
                v-model="newSession.result_observed"
                class="form-input form-textarea"
                rows="3"
                placeholder="Paciente tolerou bem, assimetria corrigida..."
              />
            </div>
          </div>

          <!-- Ações do formulário -->
          <div class="proc-form-actions">
            <button class="geral-header-btn" @click="openBeforeAfterPhotos">
              <i class="i-lucide-image w-4 h-4" />
              Fotos Antes/Depois
            </button>
            <button
              class="btn-primary flex items-center gap-2"
              :disabled="isSavingSession"
              @click="saveSession"
            >
              <i
                v-if="isSavingSession"
                class="i-lucide-loader-2 w-4 h-4 animate-spin"
              />
              <i v-else class="i-lucide-save w-4 h-4" />
              {{ isSavingSession ? 'Salvando...' : 'Salvar Procedimento' }}
            </button>
          </div>
        </div>
      </div>

      <!-- Histórico de Sessões -->
      <div class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-purple">
              <i class="i-lucide-history w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Histórico de Sessões</span>
              <span class="reg-section-subtitle"
                >Todas as sessões clínicas registradas para este paciente</span
              >
            </div>
          </div>
          <div class="flex items-center gap-2">
            <span
              v-if="isSessionsLoading"
              class="text-xs text-slate-500 flex items-center gap-1.5"
            >
              <i class="i-lucide-loader-2 w-3.5 h-3.5 animate-spin" />
              Carregando...
            </span>
            <span class="proc-count-badge">{{ sessionLogs.length }}</span>
          </div>
        </div>

        <!-- Estado vazio -->
        <div
          v-if="!sessionLogs || sessionLogs.length === 0"
          class="proc-empty-state"
        >
          <div class="proc-empty-icon">
            <i class="i-lucide-clipboard-x w-5 h-5" />
          </div>
          <p class="proc-empty-text">Nenhuma sessão registrada ainda.</p>
          <p class="proc-empty-hint">
            Use o formulário acima para registrar a primeira sessão clínica.
          </p>
        </div>

        <!-- Tabela de sessões -->
        <div v-else class="proc-table-wrap">
          <table class="proc-table">
            <thead>
              <tr class="proc-table-head">
                <th>Data / Profissional</th>
                <th>Procedimento / Área</th>
                <th>Produto / Lote</th>
                <th>Resultado / Intercorrências</th>
                <th class="text-right">Ações</th>
              </tr>
            </thead>
            <tbody>
              <tr
                v-for="log in sessionLogs"
                :key="log.id"
                class="proc-table-row"
              >
                <td class="proc-table-cell">
                  <div class="proc-cell-primary">
                    {{
                      new Date(
                        log.performed_at || log.created_at
                      ).toLocaleDateString('pt-BR', { timeZone: BRT })
                    }}
                  </div>
                  <div class="proc-cell-secondary">
                    {{
                      log.professional_name ||
                      patient?.responsibleProfessional ||
                      '—'
                    }}
                  </div>
                </td>

                <td class="proc-table-cell">
                  <div class="proc-cell-primary">
                    {{
                      log.procedure_name ||
                      log.treatment_plan_title ||
                      'Procedimento'
                    }}
                  </div>
                  <div
                    v-if="log.areas_treated && log.areas_treated.length"
                    class="proc-cell-secondary flex items-center gap-1 mt-0.5"
                  >
                    <i class="i-lucide-map-pin w-3 h-3 shrink-0" />
                    <span>{{
                      log.areas_treated
                        .map(a => a.region || a.description)
                        .filter(Boolean)
                        .join(', ')
                    }}</span>
                  </div>
                </td>

                <td class="proc-table-cell">
                  <template
                    v-if="log.products_used && log.products_used.length"
                  >
                    <div
                      v-for="(prod, idx) in log.products_used"
                      :key="idx"
                      class="proc-product-item"
                    >
                      <div class="proc-cell-primary">{{ prod.name }}</div>
                      <div
                        class="proc-cell-secondary flex gap-3 mt-0.5"
                      >
                        <span
                          v-if="prod.quantity"
                          class="flex items-center gap-1"
                        >
                          <i class="i-lucide-box w-3 h-3" />
                          {{ prod.quantity
                          }}{{ prod.unit ? ' ' + prod.unit : '' }}
                        </span>
                        <span
                          v-if="prod.batch"
                          class="flex items-center gap-1"
                        >
                          <i class="i-lucide-barcode w-3 h-3" />
                          {{ prod.batch }}
                        </span>
                      </div>
                    </div>
                  </template>
                  <span v-else class="text-slate-600 text-xs">—</span>
                </td>

                <td class="proc-table-cell proc-cell-resultado">
                  <div v-if="log.result_observed" class="proc-result-row">
                    <i class="i-lucide-check-circle w-3.5 h-3.5 shrink-0" />
                    <span>{{ log.result_observed }}</span>
                  </div>
                  <div v-if="log.complications" class="proc-result-row">
                    <i class="i-lucide-alert-triangle w-3.5 h-3.5 shrink-0" />
                    <span>{{ log.complications }}</span>
                  </div>
                  <div v-if="log.return_in_days" class="proc-result-row">
                    <i class="i-lucide-calendar-clock w-3.5 h-3.5 shrink-0" />
                    <span>Retorno em {{ log.return_in_days }} dias</span>
                  </div>
                  <span
                    v-if="
                      !log.result_observed &&
                      !log.complications &&
                      !log.return_needed &&
                      !log.return_in_days
                    "
                    class="text-slate-600 text-xs"
                    >—</span
                  >
                </td>

                <td class="proc-table-cell text-right">
                  <button
                    class="proc-action-btn"
                    title="Remover"
                    @click="requestDeleteSessionLog(log.id)"
                  >
                    <i class="i-lucide-trash-2 w-3.5 h-3.5" />
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <!-- Modal Excluir Sessão -->
    <div
      v-if="showConfirmDeleteSession"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999]"
      style="background: rgba(0, 0, 0, 0.4)"
      @click.self="cancelDeleteSessionLog"
    >
      <div
        class="delete-modal-card rounded-2xl w-full max-w-[420px] overflow-hidden"
        style="
          background: rgb(var(--slate-1));
          border: 1px solid rgb(var(--slate-4));
          box-shadow: 0 25px 50px -12px rgba(0, 0, 0, 0.15);
        "
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3
                class="font-medium m-0 text-lg leading-tight"
                style="color: rgb(var(--slate-12))"
              >
                Excluir Registro de Sessão?
              </h3>
              <p
                class="m-0 text-sm leading-relaxed"
                style="color: rgb(var(--slate-10))"
              >
                Deseja remover este registro de sessão? Esta ação não pode ser
                desfeita.
              </p>
            </div>
          </div>
        </div>
        <div
          class="px-6 py-4 flex justify-end gap-3"
          style="border-top: 1px solid rgb(var(--slate-4))"
        >
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium cursor-pointer"
            style="
              background: transparent;
              border: 1px solid #cbd5e1;
              color: #475569;
            "
            @click="cancelDeleteSessionLog"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold border-0 cursor-pointer"
            style="background: #ef4444; color: #ffffff"
            @click="confirmDeleteSessionLog"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* Painel de filtro dropdown */
.proc-filter-panel {
  position: absolute;
  right: 0;
  top: calc(100% + 8px);
  z-index: 40;
  width: 360px;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  box-shadow: 0 10px 40px rgba(0, 0, 0, 0.15);
  padding: 16px;
}

.proc-filter-close {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 24px;
  height: 24px;
  border-radius: 6px;
  color: rgb(var(--slate-9));
  background: transparent;
  border: none;
  cursor: pointer;
  transition: background 0.15s, color 0.15s;
}
.proc-filter-close:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.proc-filter-group {
  display: flex;
  flex-direction: column;
  gap: 5px;
  width: 100%;
}

.proc-filter-label {
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-11));
}

.proc-filter-input {
  box-sizing: border-box;
  width: 100%;
  padding: 8px 12px;
  font-size: 13px;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 6px;
  outline: none;
  min-width: 0;
}
.proc-filter-input:focus {
  border-color: #3b82f6;
}

.proc-filter-date-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  width: 100%;
}

.proc-filter-actions {
  display: flex;
  gap: 8px;
  margin-top: 4px;
}

.proc-filter-btn {
  flex: 1;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 12px;
  font-weight: 600;
  padding: 8px;
  border-radius: 6px;
  cursor: pointer;
  transition: background 0.15s;
  box-shadow: none;
}
.proc-filter-btn--secondary {
  background: transparent;
  color: #475569;
  border: 1px solid #cbd5e1;
}
.proc-filter-btn--secondary:hover {
  background: #f1f5f9;
  color: #334155;
  border-color: #94a3b8;
}
.proc-filter-btn--primary {
  background: #3b82f6;
  color: #fff;
  border: none;
}
.proc-filter-btn--primary:hover {
  background: #2563eb;
}

/* Input de data no header do formulário */
.proc-date-input {
  width: auto;
  min-width: 140px;
  font-size: 13px;
  padding: 7px 10px;
}

/* Ações do formulário (Fotos + Salvar) */
.proc-form-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  margin-top: 24px;
  padding-top: 20px;
  border-top: 1px solid rgba(255, 255, 255, 0.05);
}
</style>
