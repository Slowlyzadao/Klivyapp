<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * DocumentsTab — Aba "Documentos" do prontuário.
 *
 * Geração de receitas, atestados, pedidos de exame, encaminhamentos, etc.
 * Lista documentos gerados, permite download, envio via WhatsApp e exclusão.
 * Auto-suficiente: lê patientId da rota e faz seu próprio fetch.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor — ver CHANGELOG).
 */
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import DocumentsAPI from '@plugins/patients/frontend/api/patients/documents';

const route = useRoute();

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};

// ── State ──────────────────────────────────────────────────
const documents = ref([]);
const showDocModal = ref(false);
const docModalLoading = ref(false);
const showDeleteDocModal = ref(false);
const pendingDeleteDocId = ref(null);

const docForm = ref({
  document_type: 'atestado',
  title: '',
  cid: '',
  dias_afastamento: '',
  observacoes: '',
  medicamentos: '',
  posologia: '',
  exames_solicitados: '',
  encaminhado_para: '',
  especialidade: '',
  conteudo_livre: '',
});

const DOC_TYPE_LABELS = {
  receita: 'Receita Médica',
  atestado: 'Atestado Médico',
  pedido_exame: 'Pedido de Exame',
  declaracao: 'Declaração',
  relatorio_clinico: 'Relatório Clínico',
  encaminhamento: 'Encaminhamento',
  contrato: 'Contrato',
  orcamento: 'Orçamento',
  instrucao_procedimento: 'Instruções de Procedimento',
  questionario: 'Questionário',
  outro: 'Outro',
};

const DOC_STATUS_CONFIG = {
  gerado: {
    label: 'Gerado',
    cls: 'bg-blue-500/15 text-blue-400 border-blue-500/25',
  },
  pendente_assinatura: {
    label: 'Aguard. Assinatura',
    cls: 'bg-amber-500/15 text-amber-400 border-amber-500/25',
  },
  assinado: {
    label: 'Assinado',
    cls: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/25',
  },
  enviado: {
    label: 'Enviado',
    cls: 'bg-purple-500/15 text-purple-400 border-purple-500/25',
  },
  arquivado: {
    label: 'Arquivado',
    cls: 'bg-slate-500/15 text-slate-400 border-slate-500/25',
  },
};

// ── Actions ────────────────────────────────────────────────
const openDocModal = () => {
  docForm.value = {
    document_type: 'atestado',
    title: '',
    cid: '',
    dias_afastamento: '',
    observacoes: '',
    medicamentos: '',
    posologia: '',
    exames_solicitados: '',
    encaminhado_para: '',
    especialidade: '',
    conteudo_livre: '',
  };
  showDocModal.value = true;
};

const fetchDocuments = async () => {
  try {
    const res = await DocumentsAPI.get(route.params.patientId);
    // API responds with { data: [...], meta: { total_count, ... } }
    documents.value = res.data?.data || res.data || [];
  } catch (error) {
    // ignore
  }
};

const generateDocument = async () => {
  docModalLoading.value = true;
  try {
    const form = docForm.value;

    const variables = {};
    if (form.document_type === 'atestado') {
      if (form.cid) variables.cid = form.cid;
      if (form.dias_afastamento)
        variables.dias_afastamento = form.dias_afastamento;
    } else if (form.document_type === 'receita') {
      if (form.medicamentos) variables.medicamentos = form.medicamentos;
      if (form.posologia) variables.posologia = form.posologia;
    } else if (form.document_type === 'pedido_exame') {
      if (form.exames_solicitados)
        variables.exames_solicitados = form.exames_solicitados;
    } else if (form.document_type === 'encaminhamento') {
      if (form.encaminhado_para)
        variables.encaminhado_para = form.encaminhado_para;
      if (form.especialidade) variables.especialidade = form.especialidade;
    } else if (form.conteudo_livre) variables.conteudo = form.conteudo_livre;
    if (form.observacoes) variables.observacoes = form.observacoes;

    const payload = {
      document_type: form.document_type,
      title:
        form.title || DOC_TYPE_LABELS[form.document_type] || form.document_type,
      variables,
    };

    const res = await DocumentsAPI.generate(route.params.patientId, payload);
    const docData = res.data;

    showDocModal.value = false;
    await fetchDocuments();

    if (docData?.url) {
      window.open(docData.url, '_blank');
    }
  } catch (error) {
    useAlert('Erro ao gerar documento. Verifique os dados e tente novamente.');
  } finally {
    docModalLoading.value = false;
  }
};

const downloadDocument = async doc => {
  if (!doc?.id) return;
  try {
    const res = await DocumentsAPI.download(route.params.patientId, doc.id);
    if (res.data?.url) {
      window.open(res.data.url, '_blank');
    }
  } catch {
    useAlert('Erro ao baixar o documento.');
  }
};

const sendWhatsAppDocument = async documentId => {
  if (!documentId) return;
  try {
    await DocumentsAPI.sendWhatsApp(route.params.patientId, documentId);
    useAlert('Documento enviado via WhatsApp com sucesso!');
  } catch {
    useAlert('Erro ao enviar documento via WhatsApp.');
  }
};

const deleteDocument = documentId => {
  if (!documentId) return;
  pendingDeleteDocId.value = documentId;
  showDeleteDocModal.value = true;
};

const confirmDeleteDocument = async () => {
  const id = pendingDeleteDocId.value;
  if (!id) return;
  try {
    await DocumentsAPI.delete(route.params.patientId, id);
    documents.value = documents.value.filter(d => d.id !== id);
  } catch {
    useAlert('Erro ao excluir o documento.');
  } finally {
    showDeleteDocModal.value = false;
    pendingDeleteDocId.value = null;
  }
};

onMounted(() => {
  fetchDocuments();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">Documentos</h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Receitas, atestados, pedidos de exame, encaminhamentos e outros
          documentos clínicos.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button class="btn-primary flex items-center gap-2" @click="openDocModal">
          <i class="i-lucide-file-plus w-4 h-4" /> Gerar Documento
        </button>
      </div>
    </div>

    <!-- Tabela de Documentos -->
    <div class="reg-section">
      <!-- Header da seção -->
      <div class="reg-section-toggle" style="cursor: default">
        <div class="reg-section-toggle-left">
          <div class="reg-section-icon reg-icon-purple">
            <i class="i-lucide-file-text w-4 h-4" />
          </div>
          <div>
            <span class="reg-section-title">Documentos Gerados</span>
            <span class="reg-section-subtitle"
              >PDF gerados e disponíveis para download ou envio via
              WhatsApp</span
            >
          </div>
        </div>
        <span class="proc-count-badge">{{ documents?.length || 0 }}</span>
      </div>

      <!-- Empty state -->
      <div
        v-if="!documents || documents.length === 0"
        class="proc-empty-state"
      >
        <div class="proc-empty-icon">
          <i class="i-lucide-file-x w-5 h-5" />
        </div>
        <p class="proc-empty-text">Nenhum documento gerado ainda.</p>
        <button
          class="proc-empty-hint text-blue-400 cursor-pointer"
          @click="openDocModal"
        >
          Gerar primeiro documento →
        </button>
      </div>

      <!-- Tabela -->
      <div v-else class="proc-table-wrap">
        <table class="proc-table">
          <thead>
            <tr class="proc-table-head">
              <th>Documento</th>
              <th>Tipo</th>
              <th>Data</th>
              <th>Profissional</th>
              <th>Status</th>
              <th class="text-right">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="doc in documents"
              :key="doc.id"
              class="proc-table-row"
            >
              <!-- Nome -->
              <td class="proc-table-cell">
                <div class="flex items-center gap-3">
                  <div class="docs-file-icon">
                    <i class="i-lucide-file-text w-3.5 h-3.5" />
                  </div>
                  <div>
                    <p class="proc-cell-primary">
                      {{ doc.title || 'Documento' }}
                    </p>
                    <p class="proc-cell-secondary">v{{ doc.version || 1 }}</p>
                  </div>
                </div>
              </td>
              <!-- Tipo -->
              <td class="proc-table-cell">
                <span class="proc-cell-secondary">
                  {{
                    DOC_TYPE_LABELS[doc.document_type] ||
                    doc.document_type ||
                    '—'
                  }}
                </span>
              </td>
              <!-- Data -->
              <td class="proc-table-cell">
                <span class="proc-cell-secondary">{{
                  doc.created_at ? formatDate(doc.created_at) : '—'
                }}</span>
              </td>
              <!-- Profissional -->
              <td class="proc-table-cell">
                <span class="proc-cell-secondary">{{
                  doc.generated_by?.name || 'Sistema'
                }}</span>
              </td>
              <!-- Status -->
              <td class="proc-table-cell">
                <span
                  class="docs-status-badge"
                  :class="
                    (
                      DOC_STATUS_CONFIG[doc.status] || DOC_STATUS_CONFIG.gerado
                    ).cls
                  "
                >
                  {{
                    (
                      DOC_STATUS_CONFIG[doc.status] || DOC_STATUS_CONFIG.gerado
                    ).label
                  }}
                </span>
              </td>
              <!-- Ações -->
              <td class="proc-table-cell text-right">
                <div class="flex items-center justify-end gap-1">
                  <button
                    class="proc-action-btn"
                    title="Baixar documento"
                    @click="downloadDocument(doc)"
                  >
                    <i class="i-lucide-download w-3.5 h-3.5" />
                  </button>
                  <button
                    class="proc-action-btn docs-action-wa"
                    title="Enviar via WhatsApp"
                    @click="sendWhatsAppDocument(doc.id)"
                  >
                    <i class="i-lucide-message-circle w-3.5 h-3.5" />
                  </button>
                  <button
                    class="proc-action-btn"
                    title="Excluir documento"
                    @click="deleteDocument(doc.id)"
                  >
                    <i class="i-lucide-trash-2 w-3.5 h-3.5" />
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Modal: Gerar Documento -->
    <div
      v-if="showDocModal"
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md"
      @click.self="showDocModal = false"
    >
      <div class="docs-modal">
        <!-- Header -->
        <div class="docs-modal-header">
          <div class="flex items-center gap-3">
            <div class="docs-modal-icon">
              <i class="i-lucide-file-plus w-4 h-4" />
            </div>
            <div>
              <h4 class="text-base font-semibold text-slate-100">
                Gerar Documento Clínico
              </h4>
              <p class="text-xs text-slate-500 mt-0.5">
                O PDF será gerado e baixado automaticamente.
              </p>
            </div>
          </div>
          <button class="docs-modal-close" @click="showDocModal = false">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <!-- Body -->
        <div class="docs-modal-body">
          <!-- Tipo de documento -->
          <div class="form-group">
            <label class="form-label"
              >Tipo de Documento <span class="reg-required">*</span></label
            >
            <select v-model="docForm.document_type" class="form-input">
              <option
                v-for="(label, key) in DOC_TYPE_LABELS"
                :key="key"
                :value="key"
              >
                {{ label }}
              </option>
            </select>
          </div>

          <!-- Título -->
          <div class="form-group">
            <label class="form-label"
              >Título <span class="text-slate-600">(opcional)</span></label
            >
            <input
              v-model="docForm.title"
              type="text"
              :placeholder="DOC_TYPE_LABELS[docForm.document_type]"
              class="form-input"
            />
          </div>

          <!-- ATESTADO -->
          <template v-if="docForm.document_type === 'atestado'">
            <div class="reg-field-grid-2">
              <div class="form-group">
                <label class="form-label">CID</label>
                <input
                  v-model="docForm.cid"
                  type="text"
                  placeholder="Ex: M54.5"
                  class="form-input"
                />
              </div>
              <div class="form-group">
                <label class="form-label">Dias de afastamento</label>
                <input
                  v-model="docForm.dias_afastamento"
                  type="number"
                  min="1"
                  placeholder="Ex: 2"
                  class="form-input"
                />
              </div>
            </div>
          </template>

          <!-- RECEITA -->
          <template v-if="docForm.document_type === 'receita'">
            <div class="form-group">
              <label class="form-label">Medicamentos</label>
              <textarea
                v-model="docForm.medicamentos"
                rows="3"
                placeholder="Ex: Dipirona 500mg, Ibuprofeno 400mg..."
                class="form-input"
              />
            </div>
            <div class="form-group">
              <label class="form-label">Posologia</label>
              <textarea
                v-model="docForm.posologia"
                rows="2"
                placeholder="Ex: Tomar 1 comprimido de 8 em 8 horas por 5 dias..."
                class="form-input"
              />
            </div>
          </template>

          <!-- PEDIDO DE EXAME -->
          <template v-if="docForm.document_type === 'pedido_exame'">
            <div class="form-group">
              <label class="form-label">Exames solicitados</label>
              <textarea
                v-model="docForm.exames_solicitados"
                rows="3"
                placeholder="Ex: Hemograma completo, Glicemia em jejum, TSH..."
                class="form-input"
              />
            </div>
          </template>

          <!-- ENCAMINHAMENTO -->
          <template v-if="docForm.document_type === 'encaminhamento'">
            <div class="reg-field-grid-2">
              <div class="form-group">
                <label class="form-label">Encaminhar para</label>
                <input
                  v-model="docForm.encaminhado_para"
                  type="text"
                  placeholder="Nome do especialista / clínica"
                  class="form-input"
                />
              </div>
              <div class="form-group">
                <label class="form-label">Especialidade</label>
                <input
                  v-model="docForm.especialidade"
                  type="text"
                  placeholder="Ex: Ortopedia"
                  class="form-input"
                />
              </div>
            </div>
          </template>

          <!-- CAMPOS LIVRES -->
          <template
            v-if="
              [
                'relatorio_clinico',
                'declaracao',
                'instrucao_procedimento',
                'contrato',
                'orcamento',
                'questionario',
                'outro',
              ].includes(docForm.document_type)
            "
          >
            <div class="form-group">
              <label class="form-label">Conteúdo</label>
              <textarea
                v-model="docForm.conteudo_livre"
                rows="5"
                placeholder="Descreva o conteúdo do documento..."
                class="form-input"
              />
            </div>
          </template>

          <!-- Observações -->
          <div class="form-group">
            <label class="form-label">Observações adicionais</label>
            <textarea
              v-model="docForm.observacoes"
              rows="2"
              placeholder="Informações complementares..."
              class="form-input"
            />
          </div>
        </div>

        <!-- Footer -->
        <div class="docs-modal-footer">
          <button class="btn-secondary" @click="showDocModal = false">
            Cancelar
          </button>
          <button
            class="btn-primary flex items-center gap-2"
            :disabled="docModalLoading"
            @click="generateDocument"
          >
            <i class="i-lucide-file-plus w-4 h-4" />
            {{ docModalLoading ? 'Gerando PDF...' : 'Gerar e Baixar PDF' }}
          </button>
        </div>
      </div>
    </div>

    <!-- Modal: Confirmar Exclusão de Documento -->
    <div
      v-if="showDeleteDocModal"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999]"
      style="background: rgba(0, 0, 0, 0.4)"
      @click.self="
        showDeleteDocModal = false;
        pendingDeleteDocId = null;
      "
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
                Excluir Documento?
              </h3>
              <p
                class="m-0 text-sm leading-relaxed"
                style="color: rgb(var(--slate-10))"
              >
                Tem certeza que deseja excluir este documento? O arquivo PDF
                será removido permanentemente. Esta ação não pode ser desfeita.
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
            @click="
              showDeleteDocModal = false;
              pendingDeleteDocId = null;
            "
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold border-0 cursor-pointer"
            style="background: #ef4444; color: #ffffff"
            @click="confirmDeleteDocument"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
