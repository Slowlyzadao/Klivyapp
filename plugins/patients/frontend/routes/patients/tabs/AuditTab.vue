<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * AuditTab — Aba "Auditoria e Permissões" do prontuário do paciente.
 *
 * Lista de logs imutáveis (acessos, edições, assinaturas) com filtros por
 * tipo de ação, intervalo de datas e paginação. Exporta o prontuário em PDF.
 * Auto-suficiente: lê patientId da rota e faz seu próprio fetch.
 *
 * Recebe `patient-name` como prop apenas para nomear o PDF exportado.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor — ver CHANGELOG).
 */
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import AuditLogsAPI from '@plugins/patients/frontend/api/patients/auditLogs';

const props = defineProps({
  patientName: { type: String, default: '' },
});

const route = useRoute();

const BRT = 'America/Sao_Paulo';

// ── State ──────────────────────────────────────────────────
const auditLogs = ref([]);
const expandedLogs = ref(new Set());
const isAuditLoading = ref(false);
const isExportingPdf = ref(false);
const auditMeta = ref({ total_count: 0, current_page: 1, total_pages: 1 });
const auditFilters = ref({
  action_type: '',
  actor_id: '',
  start_date: '',
  end_date: '',
  page: 1,
});

const AUDIT_ACTION_OPTIONS = [
  { value: '', label: 'Todas as ações' },
  { value: 'view', label: 'Visualização' },
  { value: 'create', label: 'Criação' },
  { value: 'update', label: 'Edição' },
  { value: 'delete', label: 'Exclusão' },
  { value: 'sign', label: 'Assinatura' },
  { value: 'export', label: 'Exportação' },
  { value: 'finalize', label: 'Finalização' },
  { value: 'approve', label: 'Aprovação' },
  { value: 'pay', label: 'Pagamento' },
  { value: 'print', label: 'Impressão' },
];

// ── Helpers ────────────────────────────────────────────────
const getInitials = name => {
  if (!name) return '';
  return name.charAt(0).toUpperCase();
};

const toggleLogDetails = logId => {
  if (expandedLogs.value.has(logId)) {
    expandedLogs.value.delete(logId);
  } else {
    expandedLogs.value.add(logId);
  }
  // Forçar reactividade num Set (não dispara mudança ao mutar)
  expandedLogs.value = new Set(expandedLogs.value);
};

const formatAuditAction = action => {
  const map = {
    view: {
      label: 'VISUALIZAÇÃO',
      color: 'bg-slate-700/50 text-slate-300 border-slate-600/50',
      icon: 'i-lucide-eye',
    },
    create: {
      label: 'CRIAÇÃO',
      color: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
      icon: 'i-lucide-plus',
    },
    update: {
      label: 'EDIÇÃO',
      color: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
      icon: 'i-lucide-edit-2',
    },
    delete: {
      label: 'EXCLUSÃO',
      color: 'bg-red-500/10 text-red-400 border-red-500/20',
      icon: 'i-lucide-trash-2',
    },
    sign: {
      label: 'ASSINATURA',
      color: 'bg-violet-500/10 text-violet-400 border-violet-500/20',
      icon: 'i-lucide-pen-tool',
    },
    export: {
      label: 'EXPORTAÇÃO',
      color: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
      icon: 'i-lucide-download',
    },
    finalize: {
      label: 'FINALIZAÇÃO',
      color: 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20',
      icon: 'i-lucide-check-circle',
    },
    approve: {
      label: 'APROVAÇÃO',
      color: 'bg-teal-500/10 text-teal-400 border-teal-500/20',
      icon: 'i-lucide-thumbs-up',
    },
    pay: {
      label: 'PAGAMENTO',
      color: 'bg-green-500/10 text-green-400 border-green-500/20',
      icon: 'i-lucide-circle-dollar-sign',
    },
    print: {
      label: 'IMPRESSÃO',
      color: 'bg-cyan-500/10 text-cyan-400 border-cyan-500/20',
      icon: 'i-lucide-printer',
    },
  };
  return (
    map[action] || {
      label: (action || 'AÇÃO').toUpperCase(),
      color: 'bg-slate-700/50 text-slate-300 border-slate-600/50',
      icon: 'i-lucide-activity',
    }
  );
};

const generateDetailedAuditText = log => {
  const actor = log.actor_name ? `O usuário ${log.actor_name}` : 'O sistema';

  const resourceNames = {
    Anamnesis: 'Anamnese',
    TreatmentPlan: 'Plano de Tratamento',
    TreatmentItem: 'Procedimento',
    ClinicalNote: 'Evolução/Nota Clínica',
    FinancialEstimate: 'Orçamento',
    Transaction: 'Transação Financeira',
    Patient: 'Cadastro do Paciente',
    ExamMedia: 'Exame/Mídia',
    Document: 'Documento',
    ConsentRecord: 'Consentimento',
    SessionLog: 'Sessão de Procedimento',
    Recall: 'Recall',
    CriticalAlert: 'Alerta Crítico',
  };

  const resourceName =
    resourceNames[log.resource_type] || log.resource_type || 'Prontuário';

  switch (log.action) {
    case 'view':
      return `${actor} acessou e visualizou os dados de ${resourceName}.`;
    case 'create':
      return `${actor} criou um novo registro em ${resourceName}.`;
    case 'update':
      return `${actor} editou e alterou informações em ${resourceName}.`;
    case 'delete':
      return `${actor} excluiu o registro de ${resourceName}.`;
    case 'sign':
      return `${actor} assinou o ${resourceName}.`;
    case 'finalize':
      return `${actor} assinou e finalizou o registro de ${resourceName}. O documento tornou-se imutável.`;
    case 'approve':
      return `${actor} aprovou o ${resourceName}.`;
    case 'export':
      return `${actor} exportou o arquivo PDF de ${resourceName}.`;
    case 'pay':
      return `${actor} registrou pagamento em ${resourceName}.`;
    case 'print':
      return `${actor} emitiu impressão/receita para ${resourceName}.`;
    default:
      return `${actor} executou a ação: ${log.action} em ${resourceName}.`;
  }
};

const formatAuditDateTime = isoStr => {
  if (!isoStr) return '—';
  const d = new Date(isoStr);
  return d.toLocaleString('pt-BR', {
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    timeZone: BRT,
  });
};

// ── Actions ────────────────────────────────────────────────
const fetchAuditLogs = async () => {
  try {
    isAuditLoading.value = true;
    const params = {
      page: auditFilters.value.page,
      per_page: 15,
    };
    if (auditFilters.value.action_type)
      params.action_type = auditFilters.value.action_type;
    if (auditFilters.value.actor_id)
      params.actor_id = auditFilters.value.actor_id;
    if (auditFilters.value.start_date)
      params.start_date = auditFilters.value.start_date;
    if (auditFilters.value.end_date)
      params.end_date = auditFilters.value.end_date;

    const response = await AuditLogsAPI.get(route.params.patientId, params);
    auditLogs.value = response.data?.audit_logs || [];
    auditMeta.value = response.data?.meta || {
      total_count: 0,
      current_page: 1,
      total_pages: 1,
    };
  } catch (error) {
    useAlert('Erro ao carregar logs de auditoria.');
  } finally {
    isAuditLoading.value = false;
  }
};

const applyAuditFilters = () => {
  auditFilters.value.page = 1;
  fetchAuditLogs();
};

const clearAuditFilters = () => {
  auditFilters.value = {
    action_type: '',
    actor_id: '',
    start_date: '',
    end_date: '',
    page: 1,
  };
  fetchAuditLogs();
};

const auditPagePrev = () => {
  if (auditFilters.value.page > 1) {
    auditFilters.value.page -= 1;
    fetchAuditLogs();
  }
};

const auditPageNext = () => {
  if (auditFilters.value.page < auditMeta.value.total_pages) {
    auditFilters.value.page += 1;
    fetchAuditLogs();
  }
};

const exportPdf = async () => {
  try {
    isExportingPdf.value = true;
    const patientId = route.params.patientId;
    const response = await AuditLogsAPI.export(patientId);
    const blob = new Blob([response.data], { type: 'application/pdf' });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    const name = props.patientName?.replace(/\s+/g, '_') || 'paciente';
    link.href = url;
    link.setAttribute('download', `prontuario_${name}_${patientId}.pdf`);
    document.body.appendChild(link);
    link.click();
    link.remove();
    window.URL.revokeObjectURL(url);
    useAlert('Prontuário exportado com sucesso!');
  } catch (error) {
    useAlert('Erro ao exportar o prontuário. Verifique suas permissões.');
  } finally {
    isExportingPdf.value = false;
  }
};

onMounted(() => {
  fetchAuditLogs();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-6">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Auditoria e Segurança
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Rastreabilidade com valor legal de todos os acessos, edições e
          assinaturas no prontuário.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button
          class="geral-header-btn disabled:opacity-50 disabled:cursor-not-allowed"
          :disabled="isExportingPdf"
          @click="exportPdf"
        >
          <i
            v-if="isExportingPdf"
            class="i-lucide-loader-2 animate-spin w-3.5 h-3.5"
          />
          <i v-else class="i-lucide-download w-3.5 h-3.5" />
          {{
            isExportingPdf ? 'Gerando PDF...' : 'Exportar Prontuário PDF'
          }}
        </button>
      </div>
    </div>

    <!-- Barra de filtros -->
    <div class="aud-filter-bar mb-5">
      <div class="aud-filter-field">
        <label class="aud-filter-label">Tipo de Ação</label>
        <select
          v-model="auditFilters.action_type"
          class="form-input text-sm"
        >
          <option
            v-for="opt in AUDIT_ACTION_OPTIONS"
            :key="opt.value"
            :value="opt.value"
          >
            {{ opt.label }}
          </option>
        </select>
      </div>
      <div class="aud-filter-field">
        <label class="aud-filter-label">Data Início</label>
        <input
          v-model="auditFilters.start_date"
          type="date"
          class="form-input text-sm"
        />
      </div>
      <div class="aud-filter-field">
        <label class="aud-filter-label">Data Fim</label>
        <input
          v-model="auditFilters.end_date"
          type="date"
          class="form-input text-sm"
        />
      </div>
      <div class="aud-filter-actions">
        <button
          class="btn-primary flex items-center gap-1.5"
          @click="applyAuditFilters"
        >
          <i class="i-lucide-filter w-3.5 h-3.5" /> Filtrar
        </button>
        <button
          class="btn-secondary aud-clear-btn"
          title="Limpar filtros"
          @click="clearAuditFilters"
        >
          <i class="i-lucide-x w-4 h-4" />
        </button>
      </div>
    </div>

    <!-- Tabela de Logs -->
    <div class="aud-table-wrap">
      <!-- Loading -->
      <div v-if="isAuditLoading" class="aud-loading">
        <i class="i-lucide-loader-2 animate-spin w-5 h-5" />
        <span>Carregando logs de auditoria...</span>
      </div>

      <!-- Tabela -->
      <div v-else class="overflow-x-auto">
        <table class="aud-table">
          <thead>
            <tr class="aud-thead-row">
              <th class="aud-th">Data / Hora</th>
              <th class="aud-th">Ação</th>
              <th class="aud-th">Usuário / Perfil</th>
              <th class="aud-th">Módulo &amp; Detalhes</th>
              <th class="aud-th">IP</th>
              <th class="aud-th aud-th--center">Info</th>
            </tr>
          </thead>
          <tbody>
            <!-- Estado vazio -->
            <tr v-if="auditLogs.length === 0">
              <td colspan="6" class="aud-empty-cell">
                <div class="aud-empty-state">
                  <i class="i-lucide-shield-off w-6 h-6" />
                  <p>
                    Nenhum log de auditoria encontrado para este paciente.
                  </p>
                  <p class="aud-empty-hint">
                    Tente ajustar os filtros ou verifique suas permissões.
                  </p>
                </div>
              </td>
            </tr>

            <!-- Linhas de log -->
            <template v-for="log in auditLogs" :key="log.id">
              <tr class="aud-row">
                <!-- Data/Hora -->
                <td class="aud-td aud-td--mono aud-td--dim">
                  {{ formatAuditDateTime(log.occurred_at) }}
                </td>

                <!-- Tipo de ação -->
                <td class="aud-td">
                  <span
                    class="aud-action-badge"
                    :class="formatAuditAction(log.action).color"
                  >
                    <i
                      class="w-3 h-3"
                      :class="formatAuditAction(log.action).icon"
                    />
                    {{ formatAuditAction(log.action).label }}
                  </span>
                </td>

                <!-- Usuário / Perfil -->
                <td class="aud-td">
                  <div class="aud-user-cell">
                    <div class="aud-avatar">
                      {{ getInitials(log.actor_name) }}
                    </div>
                    <div>
                      <p class="aud-user-name">
                        {{ log.actor_name || 'Sistema' }}
                      </p>
                      <p class="aud-user-role">
                        {{ log.actor_role || '—' }}
                      </p>
                    </div>
                  </div>
                </td>

                <!-- Módulo & Detalhes -->
                <td class="aud-td aud-td--details">
                  <span class="aud-module-name">{{
                    log.resource_type || 'Ficha'
                  }}</span>
                  <span v-if="log.resource_id" class="aud-module-id"
                    >#{{ log.resource_id }}</span
                  >

                  <!-- Diff de campos alterados -->
                  <div
                    v-if="
                      log.changed_fields &&
                      Object.keys(log.changed_fields).length > 0
                    "
                    class="aud-diff"
                  >
                    <div
                      v-for="(vals, field) in log.changed_fields"
                      :key="field"
                      class="aud-diff-row"
                    >
                      <span class="aud-diff-field">{{ field }}:</span>
                      <span class="aud-diff-old">{{
                        vals[0] !== null ? vals[0] : 'vazio'
                      }}</span>
                      <i
                        class="i-lucide-arrow-right w-2.5 h-2.5 text-slate-600"
                      />
                      <span class="aud-diff-new">{{
                        vals[1] !== null ? vals[1] : 'vazio'
                      }}</span>
                    </div>
                  </div>

                  <!-- Snapshot new_value -->
                  <div
                    v-else-if="log.new_value"
                    class="aud-snapshot"
                    :title="JSON.stringify(log.new_value)"
                  >
                    {{ JSON.stringify(log.new_value).slice(0, 80)
                    }}{{
                      JSON.stringify(log.new_value).length > 80 ? '…' : ''
                    }}
                  </div>
                </td>

                <!-- IP -->
                <td class="aud-td aud-td--mono aud-td--dim">
                  {{ log.ip_address || '—' }}
                </td>

                <!-- Ver detalhes -->
                <td class="aud-td aud-td--center">
                  <button
                    class="aud-detail-btn"
                    :title="
                      expandedLogs.has(log.id)
                        ? 'Recolher detalhes'
                        : 'Ver detalhes completos'
                    "
                    @click="toggleLogDetails(log.id)"
                  >
                    <i
                      class="w-4 h-4"
                      :class="
                        expandedLogs.has(log.id)
                          ? 'i-lucide-eye-off'
                          : 'i-lucide-eye'
                      "
                    />
                  </button>
                </td>
              </tr>

              <!-- Linha expandida -->
              <tr v-if="expandedLogs.has(log.id)" class="aud-expanded-row">
                <td colspan="6" class="aud-expanded-cell">
                  <div class="aud-expanded-body">
                    <i class="i-lucide-info w-4 h-4 aud-expanded-icon" />
                    <div>
                      <p class="aud-expanded-title">
                        Registro de Ação Detalhado
                      </p>
                      <p class="aud-expanded-text">
                        {{ generateDetailedAuditText(log) }}
                      </p>

                      <!-- Diff completo -->
                      <div
                        v-if="
                          log.action === 'update' &&
                          log.changed_fields &&
                          Object.keys(log.changed_fields).length > 0
                        "
                        class="aud-expanded-diff"
                      >
                        <p class="aud-expanded-diff-title">
                          Histórico de Alterações (De → Para)
                        </p>
                        <ul class="aud-expanded-diff-list">
                          <li
                            v-for="(vals, field) in log.changed_fields"
                            :key="field"
                            class="aud-expanded-diff-item"
                          >
                            <span class="aud-diff-f">{{ field }}</span>
                            <span class="aud-diff-o">{{
                              vals[0] !== null ? vals[0] : 'nulo'
                            }}</span>
                            <i
                              class="i-lucide-arrow-right w-3 h-3 text-slate-600"
                            />
                            <span class="aud-diff-n">{{
                              vals[1] !== null ? vals[1] : 'nulo'
                            }}</span>
                          </li>
                        </ul>
                      </div>
                    </div>
                  </div>
                </td>
              </tr>
            </template>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Rodapé: nota de imutabilidade + paginação -->
    <div class="aud-footer mt-5">
      <p class="aud-footer-note">
        <i class="i-lucide-lock w-3 h-3" />
        Registros imutáveis — gravados permanentemente no banco.
        <span class="aud-footer-total"
          >Total: {{ auditMeta.total_count }} eventos</span
        >
      </p>
      <div class="aud-pagination">
        <span class="aud-page-info"
          >Página {{ auditMeta.current_page }} de
          {{ auditMeta.total_pages }}</span
        >
        <div class="flex gap-2">
          <button
            class="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="auditFilters.page <= 1 || isAuditLoading"
            @click="auditPagePrev"
          >
            ← Anterior
          </button>
          <button
            class="btn-secondary disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="
              auditFilters.page >= auditMeta.total_pages || isAuditLoading
            "
            @click="auditPageNext"
          >
            Próxima →
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ============================================================
   AUDITORIA TAB — aud-* design system
   ============================================================ */

.aud-filter-bar {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr auto;
  align-items: flex-end;
  gap: 12px;
  background: rgba(255, 255, 255, 0.02);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 12px;
  padding: 16px;
}
.aud-filter-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}
.aud-filter-label {
  font-size: 12px;
  font-weight: 500;
  color: #64748b;
  line-height: 1;
}
.aud-filter-actions {
  display: flex;
  align-items: flex-end;
  gap: 8px;
}
.aud-clear-btn {
  width: 38px;
  height: 38px;
  padding: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

/* Tabela wrapper */
.aud-table-wrap {
  background: rgba(255, 255, 255, 0.02);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 12px;
  overflow: hidden;
}
.aud-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 10px;
  padding: 48px;
  color: #475569;
  font-size: 14px;
}
.aud-table {
  width: 100%;
  text-align: left;
  font-size: 13px;
  border-collapse: collapse;
}

.aud-thead-row {
  background: rgba(255, 255, 255, 0.025);
  border-bottom: 1px solid rgba(255, 255, 255, 0.06);
}
.aud-th {
  padding: 11px 16px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: #475569;
  white-space: nowrap;
}
.aud-th--center {
  text-align: center;
}

.aud-row {
  border-bottom: 1px solid rgba(255, 255, 255, 0.04);
  transition: background 0.12s;
}
.aud-row:last-child {
  border-bottom: none;
}
.aud-row:hover {
  background: rgba(255, 255, 255, 0.025);
}

.aud-td {
  padding: 13px 16px;
  vertical-align: middle;
}
.aud-td--mono {
  font-family: ui-monospace, monospace;
  font-size: 11px;
}
.aud-td--dim {
  color: #475569;
}
.aud-td--center {
  text-align: center;
}
.aud-td--details {
  max-width: 280px;
}

.aud-action-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 2px 8px;
  border-radius: 5px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  border-width: 1px;
  border-style: solid;
  white-space: nowrap;
}

.aud-user-cell {
  display: flex;
  align-items: center;
  gap: 9px;
}
.aud-avatar {
  width: 28px;
  height: 28px;
  border-radius: 99px;
  background: rgba(59, 130, 246, 0.12);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  font-size: 10px;
  font-weight: 700;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}
.aud-user-name {
  font-size: 12px;
  font-weight: 500;
  color: #cbd5e1;
  line-height: 1.3;
}
.aud-user-role {
  font-size: 10px;
  color: #475569;
  text-transform: capitalize;
  line-height: 1.3;
}

.aud-module-name {
  font-size: 12px;
  font-weight: 500;
  color: #e2e8f0;
}
.aud-module-id {
  font-size: 11px;
  color: #475569;
  margin-left: 3px;
}
.aud-diff {
  margin-top: 6px;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.aud-diff-row {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
}
.aud-diff-field {
  color: #64748b;
  font-weight: 500;
}
.aud-diff-old {
  color: #475569;
  text-decoration: line-through;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.aud-diff-new {
  color: #4ade80;
  max-width: 120px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.aud-snapshot {
  margin-top: 4px;
  font-size: 10px;
  color: #475569;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.aud-detail-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 7px;
  background: none;
  border: none;
  color: #475569;
  cursor: pointer;
  transition: background 0.12s, color 0.12s;
}
.aud-detail-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
}

.aud-expanded-row {
  background: rgba(59, 130, 246, 0.04);
}
.aud-expanded-cell {
  padding: 14px 16px;
  border-left: 2px solid rgba(59, 130, 246, 0.3);
}
.aud-expanded-body {
  display: flex;
  align-items: flex-start;
  gap: 10px;
}
.aud-expanded-icon {
  color: #60a5fa;
  margin-top: 1px;
  flex-shrink: 0;
}
.aud-expanded-title {
  font-size: 13px;
  font-weight: 500;
  color: #e2e8f0;
  margin-bottom: 4px;
}
.aud-expanded-text {
  font-size: 12px;
  color: #94a3b8;
  line-height: 1.5;
}
.aud-expanded-diff {
  margin-top: 12px;
  background: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.06);
  border-radius: 8px;
  padding: 12px 14px;
}
.aud-expanded-diff-title {
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: #475569;
  margin-bottom: 8px;
}
.aud-expanded-diff-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.aud-expanded-diff-item {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
}
.aud-diff-f {
  color: #64748b;
  font-family: ui-monospace, monospace;
  width: 96px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  flex-shrink: 0;
}
.aud-diff-o {
  color: #475569;
  text-decoration: line-through;
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.aud-diff-n {
  color: #4ade80;
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.aud-empty-cell {
  padding: 48px 24px;
}
.aud-empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  color: #475569;
  text-align: center;
  font-size: 13px;
}
.aud-empty-hint {
  font-size: 11px;
  color: #334155;
}

.aud-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  flex-wrap: wrap;
}
.aud-footer-note {
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  color: #334155;
}
.aud-footer-total {
  margin-left: 8px;
  color: #1e293b;
}
.aud-pagination {
  display: flex;
  align-items: center;
  gap: 12px;
}
.aud-page-info {
  font-size: 11px;
  color: #475569;
  white-space: nowrap;
}
</style>
