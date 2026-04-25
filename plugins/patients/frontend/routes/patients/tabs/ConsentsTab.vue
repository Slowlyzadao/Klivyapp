<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Consentimentos e Assinaturas
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Gestão jurídica de termos — LGPD, autorizações de imagem,
          procedimentos estéticos e mais.
        </p>
      </div>
      <div class="flex items-center gap-3">
        <button
          class="btn-primary flex items-center gap-2"
          :class="
            showConsentModal
              ? 'bg-slate-600 hover:bg-slate-500'
              : 'bg-emerald-600 hover:bg-emerald-500'
          "
          @click="
            showConsentModal ? (showConsentModal = false) : openConsentModal()
          "
        >
          <i
            :class="
              showConsentModal ? 'i-lucide-x w-4 h-4' : 'i-lucide-plus w-4 h-4'
            "
          />
          {{ showConsentModal ? 'Cancelar' : 'Novo Consentimento' }}
        </button>
      </div>
    </div>

    <!-- KPIs de status -->
    <div class="consent-kpi-grid mb-5">
      <div class="consent-kpi-card">
        <div class="consent-kpi-icon consent-kpi-icon--neutral">
          <i class="i-lucide-files w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label">Total</p>
          <p class="consent-kpi-value">{{ consentStats.total }}</p>
        </div>
      </div>
      <div class="consent-kpi-card consent-kpi-card--green">
        <div class="consent-kpi-icon consent-kpi-icon--green">
          <i class="i-lucide-check-circle w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label consent-kpi-label--green">Assinados</p>
          <p class="consent-kpi-value consent-kpi-value--green">
            {{ consentStats.signed }}
          </p>
        </div>
      </div>
      <div class="consent-kpi-card consent-kpi-card--amber">
        <div class="consent-kpi-icon consent-kpi-icon--amber">
          <i class="i-lucide-clock w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label consent-kpi-label--amber">Pendentes</p>
          <p class="consent-kpi-value consent-kpi-value--amber">
            {{ consentStats.pending }}
          </p>
        </div>
      </div>
      <div class="consent-kpi-card consent-kpi-card--red">
        <div class="consent-kpi-icon consent-kpi-icon--red">
          <i class="i-lucide-alert-triangle w-4 h-4" />
        </div>
        <div>
          <p class="consent-kpi-label consent-kpi-label--red">Vencidos</p>
          <p class="consent-kpi-value consent-kpi-value--red">
            {{ consentStats.expired }}
          </p>
        </div>
      </div>
    </div>

    <!-- FORMULÁRIO INLINE: Novo Consentimento -->
    <div v-if="showConsentModal" class="reg-section mb-5">
      <div class="reg-section-toggle consent-form-header">
        <div class="reg-section-toggle-left">
          <div class="reg-section-icon reg-icon-green">
            <i class="i-lucide-plus-circle w-4 h-4" />
          </div>
          <div>
            <span class="reg-section-title">Novo Consentimento</span>
            <span class="reg-section-subtitle"
              >Preencha os dados e o conteúdo do termo</span
            >
          </div>
        </div>
        <button
          class="docs-modal-close"
          title="Fechar"
          @click="showConsentModal = false"
        >
          <i class="i-lucide-x w-4 h-4" />
        </button>
      </div>

      <div class="reg-section-body">
        <!-- Linha 1: Tipo + Título + Validade -->
        <div class="grid grid-cols-12 gap-4">
          <div class="col-span-4 form-group">
            <label class="form-label"
              >Tipo de Consentimento <span class="reg-required">*</span></label
            >
            <select
              v-model="newConsentForm.consent_type"
              class="form-input"
              @change="onConsentTypeChange"
            >
              <option value="" disabled>Selecione o tipo...</option>
              <option
                v-for="type in CONSENT_TYPES"
                :key="type.value"
                :value="type.value"
              >
                {{ type.label }}
              </option>
            </select>
            <p
              v-if="consentTypeDetail"
              class="text-xs text-slate-500 mt-1.5 leading-snug"
            >
              {{ consentTypeDetail.description }}
            </p>
          </div>
          <div class="col-span-5 form-group">
            <label class="form-label">Título do Documento</label>
            <input
              v-model="newConsentForm.title"
              type="text"
              placeholder="Ex: Termo de Consentimento para Botox"
              class="form-input"
            />
          </div>
          <div class="col-span-3 form-group">
            <label class="form-label">Validade</label>
            <select
              v-model="newConsentForm.expires_in_months"
              class="form-input"
            >
              <option :value="1">1 mês</option>
              <option :value="3">3 meses</option>
              <option :value="6">6 meses</option>
              <option :value="12">12 meses (1 ano)</option>
              <option :value="24">24 meses (2 anos)</option>
              <option :value="60">60 meses (5 anos)</option>
              <option :value="0">Sem vencimento</option>
            </select>
          </div>
        </div>

        <!-- Observações -->
        <div class="form-group">
          <label class="form-label"
            >Observações Adicionais
            <span class="text-slate-600">(opcional)</span></label
          >
          <input
            v-model="newConsentForm.observations"
            type="text"
            placeholder="Ex: Aplicação na região frontal e glabela — sessão 1/3"
            class="form-input"
          />
        </div>

        <!-- Conteúdo do Termo -->
        <div class="form-group">
          <div class="flex items-center justify-between mb-1.5">
            <label class="form-label"
              >Conteúdo do Termo
              <span class="text-slate-600 font-normal ml-1"
                >(editável — clique para personalizar)</span
              >
            </label>
            <span v-if="newConsentForm.body" class="text-xs text-slate-600">
              {{ newConsentForm.body.length }} caracteres
            </span>
          </div>
          <textarea
            v-model="newConsentForm.body"
            rows="20"
            placeholder="Selecione um tipo de consentimento acima para pré-preencher o template..."
            class="form-input font-mono leading-relaxed resize-y"
            style="min-height: 400px"
          />
        </div>

        <!-- Ações -->
        <div
          class="flex items-center justify-between pt-2 border-t border-white/5"
        >
          <p class="text-xs text-slate-500 flex items-center gap-1.5">
            <i class="i-lucide-info w-3 h-3" />
            O consentimento será criado como
            <strong class="text-amber-400">pendente</strong> até ser assinado
          </p>
          <div class="flex gap-3">
            <button class="btn-secondary" @click="showConsentModal = false">
              Cancelar
            </button>
            <button
              class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"
              :disabled="consentModalLoading || !newConsentForm.consent_type"
              @click="createConsent"
            >
              <i
                v-if="consentModalLoading"
                class="i-lucide-loader-2 animate-spin w-4 h-4"
              />
              <i v-else class="i-lucide-file-plus w-4 h-4" />
              {{ consentModalLoading ? 'Criando...' : 'Criar Consentimento' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Loading state -->
    <div v-if="consentLoading" class="flex items-center justify-center py-16">
      <div
        class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
      />
    </div>

    <!-- Empty state -->
    <div v-else-if="!consents || consents.length === 0" class="reg-section">
      <div class="proc-empty-state">
        <div class="proc-empty-icon">
          <i class="i-lucide-file-signature w-5 h-5" />
        </div>
        <p class="proc-empty-text">Nenhum consentimento registrado</p>
        <p class="proc-empty-hint">
          Clique em "Novo Consentimento" para adicionar o primeiro termo
        </p>
      </div>
    </div>

    <!-- Tabela de Consentimentos -->
    <div v-else class="reg-section">
      <div class="reg-section-toggle consent-form-header">
        <div class="reg-section-toggle-left">
          <div class="reg-section-icon reg-icon-purple">
            <i class="i-lucide-file-signature w-4 h-4" />
          </div>
          <div>
            <span class="reg-section-title">Termos Registrados</span>
            <span class="reg-section-subtitle"
              >Histórico de consentimentos do paciente</span
            >
          </div>
        </div>
        <span class="proc-count-badge">{{ consents.length }}</span>
      </div>

      <div class="proc-table-wrap">
        <table class="proc-table">
          <thead>
            <tr class="proc-table-head">
              <th>Documento</th>
              <th>Categoria</th>
              <th>Validade</th>
              <th>Status</th>
              <th class="text-right">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="consent in consents"
              :key="consent.id"
              class="proc-table-row"
            >
              <!-- Documento -->
              <td class="proc-table-cell">
                <div class="flex items-center gap-3">
                  <div class="consent-doc-icon">
                    <i class="i-lucide-file-signature w-3.5 h-3.5" />
                  </div>
                  <div>
                    <p class="proc-cell-primary">
                      {{ consent.title || 'Termo de Consentimento' }}
                    </p>
                    <p class="proc-cell-secondary">
                      <i class="i-lucide-calendar w-2.5 h-2.5 mr-0.5" />
                      {{
                        consent.created_at
                          ? formatDate(consent.created_at)
                          : '—'
                      }}
                      <span v-if="consent.version"
class="ml-2 text-slate-600"
                        >v{{ consent.version }}</span
                      >
                    </p>
                  </div>
                </div>
              </td>

              <!-- Categoria -->
              <td class="proc-table-cell">
                <span class="proc-cell-secondary">{{
                  consentTypeLabel(consent.document_type)
                }}</span>
              </td>

              <!-- Validade -->
              <td class="proc-table-cell">
                <span
                  v-if="consent.expires_at"
                  class="proc-cell-secondary flex items-center gap-1"
                >
                  <i class="i-lucide-timer w-2.5 h-2.5" />
                  {{ formatDate(consent.expires_at) }}
                </span>
                <span v-else class="proc-cell-secondary">—</span>
              </td>

              <!-- Status -->
              <td class="proc-table-cell">
                <div class="flex flex-col gap-1 items-start">
                  <span
                    class="docs-status-badge"
                    :class="consentStatusLabel(consent.status).cls"
                  >
                    <i
                      :class="consentStatusLabel(consent.status).icon"
                      class="w-3 h-3 mr-1"
                    />
                    {{ consentStatusLabel(consent.status).label.toUpperCase() }}
                  </span>
                  <span
                    v-if="consent.integrity_hash"
                    class="text-[10px] text-slate-500 flex items-center gap-1"
                  >
                    <i class="i-lucide-fingerprint w-2.5 h-2.5" />
                    Hash: {{ consent.integrity_hash?.slice(0, 8) }}...
                  </span>
                  <span
                    v-if="consent.signed_at"
                    class="text-[10px] text-slate-500 flex items-center gap-1"
                  >
                    <i class="i-lucide-clock w-2.5 h-2.5" />
                    {{ formatDate(consent.signed_at) }}
                  </span>
                </div>
              </td>

              <!-- Ações -->
              <td class="proc-table-cell text-right">
                <div class="consent-actions-group">
                  <button
                    class="consent-action-btn"
                    title="Visualizar termo"
                    @click="viewConsent(consent)"
                  >
                    <i class="i-lucide-eye w-3.5 h-3.5" />
                    <span>Ver</span>
                  </button>
                  <template
                    v-if="
                      ![
                        'signed',
                        'assinado_localmente',
                        'assinado_remotamente',
                        'revogado',
                      ].includes(consent.status)
                    "
                  >
                    <button
                      class="consent-action-btn consent-action-btn--blue"
                      title="Enviar link de assinatura por WhatsApp"
                      @click="sendConsentRemote(consent.id)"
                    >
                      <i class="i-lucide-smartphone w-3.5 h-3.5" />
                      <span>Enviar</span>
                    </button>
                    <button
                      class="consent-action-btn consent-action-btn--green"
                      title="Assinar presencialmente"
                      @click="signConsentNow(consent.id)"
                    >
                      <i class="i-lucide-pen-tool w-3.5 h-3.5" />
                      <span>Assinar</span>
                    </button>
                  </template>
                  <template
                    v-if="
                      [
                        'signed',
                        'assinado_localmente',
                        'assinado_remotamente',
                      ].includes(consent.status)
                    "
                  >
                    <button
                      class="consent-action-btn consent-action-btn--purple"
                      title="Ver integridade"
                      @click="viewConsent(consent)"
                    >
                      <i class="i-lucide-shield-check w-3.5 h-3.5" />
                      <span>Hash</span>
                    </button>
                    <button
                      class="consent-action-btn consent-action-btn--danger"
                      title="Revogar consentimento"
                      @click="revokeConsent(consent.id)"
                    >
                      <i class="i-lucide-x-circle w-3.5 h-3.5" />
                      <span>Revogar</span>
                    </button>
                  </template>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- MODAL: Assinatura Digital -->
    <div
      v-if="showSignModal"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/80 backdrop-blur-md"
      @click.self="showSignModal = false"
    >
      <div class="consent-sign-modal">
        <div class="docs-modal-header">
          <div class="flex items-center gap-3">
            <div class="consent-modal-icon consent-modal-icon--green">
              <i class="i-lucide-pen-tool w-4 h-4" />
            </div>
            <div>
              <h4 class="text-base font-semibold text-slate-100">
                Assinatura Digital
              </h4>
              <p class="text-xs text-slate-500 mt-0.5">
                Assine com o dedo ou mouse no campo abaixo
              </p>
            </div>
          </div>
          <button class="docs-modal-close" @click="showSignModal = false">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <div class="docs-modal-body">
          <!-- Canvas de assinatura -->
          <div class="consent-canvas-wrap">
            <canvas
              ref="signatureCanvas"
              width="600"
              height="200"
              class="consent-canvas"
              @mousedown="startDrawing"
              @mousemove="draw"
              @mouseup="stopDrawing"
              @mouseleave="stopDrawing"
              @touchstart.prevent="startDrawing"
              @touchmove.prevent="draw"
              @touchend="stopDrawing"
            />
            <div v-if="!hasSignature" class="consent-canvas-hint">
              <i class="i-lucide-pen-line w-5 h-5 mb-1" />
              <p>Assine aqui</p>
            </div>
          </div>

          <div class="consent-canvas-footer">
            <button class="consent-clear-btn" @click="clearSignature">
              <i class="i-lucide-rotate-ccw w-3 h-3" /> Limpar
            </button>
            <p class="consent-hash-hint">
              <i class="i-lucide-shield w-3 h-3" />
              Hash SHA-256 gerado automaticamente
            </p>
          </div>
        </div>

        <div class="docs-modal-footer">
          <button class="btn-secondary" @click="showSignModal = false">
            Cancelar
          </button>
          <button
            class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2 disabled:opacity-50"
            :disabled="consentModalLoading || !hasSignature"
            @click="confirmSign"
          >
            <i
              v-if="consentModalLoading"
              class="i-lucide-loader-2 animate-spin w-4 h-4"
            />
            <i v-else class="i-lucide-check-circle w-4 h-4" />
            Confirmar Assinatura
          </button>
        </div>
      </div>
    </div>

    <!-- MODAL: Visualizar Consentimento -->
    <div
      v-if="showViewModal && consentInView"
      class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/75 backdrop-blur-md"
      @click.self="showViewModal = false"
    >
      <div class="consent-view-modal">
        <div class="docs-modal-header">
          <div class="flex items-center gap-3">
            <div class="consent-modal-icon consent-modal-icon--purple">
              <i class="i-lucide-file-signature w-4 h-4" />
            </div>
            <div>
              <h4 class="text-base font-semibold text-slate-100">
                {{ consentInView.title || 'Termo de Consentimento' }}
              </h4>
              <div class="flex items-center gap-3 mt-0.5">
                <span
                  class="docs-status-badge"
                  :class="consentStatusLabel(consentInView.status).cls"
                >
                  {{ consentStatusLabel(consentInView.status).label }}
                </span>
                <span class="text-xs text-slate-500">{{
                  formatDate(consentInView.created_at)
                }}</span>
              </div>
            </div>
          </div>
          <button class="docs-modal-close" @click="showViewModal = false">
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </div>

        <div class="docs-modal-body">
          <!-- Conteúdo do termo -->
          <div class="consent-view-body">
            <p class="consent-view-text">
              {{ consentInView.body || '(Conteúdo não disponível)' }}
            </p>
          </div>

          <!-- Dados de auditoria -->
          <div
            v-if="
              [
                'signed',
                'assinado_localmente',
                'assinado_remotamente',
              ].includes(consentInView.status)
            "
            class="consent-audit-block"
          >
            <p class="consent-audit-title">Auditoria Forense</p>
            <div class="consent-audit-row consent-audit-row--green">
              <i class="i-lucide-check-circle w-3.5 h-3.5" />
              Assinado em {{ formatDate(consentInView.signed_at) }}
            </div>
            <div v-if="consentInView.integrity_hash" class="consent-audit-row">
              <i
                class="i-lucide-fingerprint w-3.5 h-3.5 flex-shrink-0 mt-0.5"
              />
              <span class="font-mono break-all">{{
                consentInView.integrity_hash
              }}</span>
            </div>
            <div
              v-if="consentInView.signed_ip"
              class="consent-audit-row consent-audit-row--muted"
            >
              <i class="i-lucide-map-pin w-3.5 h-3.5" />
              IP: {{ consentInView.signed_ip }}
            </div>

            <!-- Assinatura visual -->
            <div
              v-if="
                consentInView.signature_image_url ||
                consentInView.signature_blob
              "
              class="consent-sig-preview"
            >
              <p class="consent-sig-label">Assinatura registrada:</p>
              <div class="consent-sig-frame">
                <img
                  :src="
                    consentInView.signature_image_url ||
                    consentInView.signature_blob
                  "
                  alt="Assinatura"
                  class="consent-sig-img"
                />
              </div>
            </div>
          </div>
        </div>

        <div class="docs-modal-footer">
          <button
            v-if="
              ![
                'signed',
                'assinado_localmente',
                'assinado_remotamente',
                'revogado',
              ].includes(consentInView.status)
            "
            class="btn-primary bg-emerald-600 hover:bg-emerald-500 flex items-center gap-2"
            @click="
              signConsentNow(consentInView.id);
              showViewModal = false;
            "
          >
            <i class="i-lucide-pen-tool w-4 h-4" /> Assinar Agora
          </button>
          <button class="btn-secondary" @click="showViewModal = false">
            Fechar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
