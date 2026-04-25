<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header padrão STYLE.md -->
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
        <button
          class="btn-secondary flex items-center gap-2"
          @click="toggleFilterPanel"
        >
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
            <button class="proc-filter-close" @click="showFilterPanel = false">
              <i class="i-lucide-x w-3.5 h-3.5" />
            </button>
          </div>
          <div class="flex flex-col gap-3">
            <div class="proc-filter-group">
              <label class="proc-filter-label">Procedimento</label>
              <input
                v-model="sessionHistoryFilter.procedure_name"
                type="text"
                class="proc-filter-input"
                placeholder="Ex: Toxina Botulínica"
              />
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
      <div class="reg-section">
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
                >Procedimento Realizado
                <span class="reg-required">*</span></label
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
            <button
              class="btn-secondary flex items-center gap-2"
              @click="openBeforeAfterPhotos"
            >
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
                      patient.responsibleProfessional ||
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
                      <div class="proc-cell-primary">
                        {{ prod.name }}
                      </div>
                      <div class="proc-cell-secondary flex gap-3 mt-0.5">
                        <span
                          v-if="prod.quantity"
                          class="flex items-center gap-1"
                        >
                          <i class="i-lucide-box w-3 h-3" />
                          {{ prod.quantity
                          }}{{ prod.unit ? ' ' + prod.unit : '' }}
                        </span>
                        <span v-if="prod.batch" class="flex items-center gap-1">
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

    <div class="page-footer-spacer" />
  </div>
</template>
