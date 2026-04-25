<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
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
        <button
          class="btn-primary flex items-center gap-2"
          @click="openDocModal"
        >
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
      <div v-if="!documents || documents.length === 0" class="proc-empty-state">
        <div class="proc-empty-icon">
          <i class="i-lucide-file-x w-5 h-5" />
        </div>
        <p class="proc-empty-text">Nenhum documento gerado ainda.</p>
        <button
          class="proc-empty-hint"
          style="color: #60a5fa; cursor: pointer"
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
            <tr v-for="doc in documents" :key="doc.id" class="proc-table-row">
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
                    (DOC_STATUS_CONFIG[doc.status] || DOC_STATUS_CONFIG.gerado)
                      .cls
                  "
                >
                  {{
                    (DOC_STATUS_CONFIG[doc.status] || DOC_STATUS_CONFIG.gerado)
                      .label
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
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/75 backdrop-blur-md"
      @click.self="
        showDeleteDocModal = false;
        pendingDeleteDocId = null;
      "
    >
      <div class="docs-modal" style="max-width: 400px">
        <div class="docs-modal-header">
          <div class="flex items-center gap-3">
            <div
              class="docs-modal-icon"
              style="background: rgba(239, 68, 68, 0.12); color: #f87171"
            >
              <i class="i-lucide-trash-2 w-4 h-4" />
            </div>
            <div>
              <h4 class="text-base font-semibold text-slate-100">
                Excluir Documento
              </h4>
              <p class="text-xs text-slate-500 mt-0.5">
                Esta ação não pode ser desfeita.
              </p>
            </div>
          </div>
          <button
            class="docs-modal-close"
            @click="
              showDeleteDocModal = false;
              pendingDeleteDocId = null;
            "
          >
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>
        <div class="docs-modal-body" style="padding: 20px 24px 4px">
          <p class="text-sm text-slate-400">
            Tem certeza que deseja excluir este documento? O arquivo PDF será
            removido permanentemente.
          </p>
        </div>
        <div class="docs-modal-footer">
          <button
            class="btn-secondary"
            @click="
              showDeleteDocModal = false;
              pendingDeleteDocId = null;
            "
          >
            Cancelar
          </button>
          <button
            class="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium bg-red-600 hover:bg-red-500 text-white transition-colors"
            @click="confirmDeleteDocument"
          >
            <i class="i-lucide-trash-2 w-3.5 h-3.5" /> Excluir
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
