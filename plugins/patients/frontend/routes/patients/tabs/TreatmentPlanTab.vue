<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tp-tab">
    <!-- ── Cabeçalho ── -->
    <div class="tp-tab-header hide-on-print">
      <div>
        <h3 class="tp-tab-title">Plano de Tratamento</h3>
        <p class="tp-tab-subtitle">
          Planejamento clínico, orçamentos propostos e status de execução.
        </p>
      </div>
      <button class="tp-btn-new" @click="createTreatmentPlan">
        <i class="i-lucide-plus tp-btn-new-icon" />
        Novo Plano
      </button>
    </div>

    <div class="tp-content-grid">
      <!-- ── Formulário de Diagnóstico (novo plano) ── -->
      <div class="tp-card hide-on-print">
        <div class="tp-card-header">
          <div class="tp-card-header-icon tp-card-header-icon--blue">
            <i class="i-lucide-search" />
          </div>
          <div>
            <span class="tp-card-title">Diagnóstico e Hipótese Inicial</span>
            <span class="tp-card-subtitle"
              >Preencha para criar um novo plano de tratamento</span
            >
          </div>
        </div>
        <div class="tp-card-body">
          <div class="tp-field">
            <label class="tp-field-label"
              >Justificativa Clínica / Queixa Principal do Novo Plano</label
            >
            <textarea
              v-model="globalDiagnosisDescription"
              class="tp-field-input"
              rows="2"
              placeholder="Paciente apresenta escurecimento generalizado nos dentes e má oclusão leve..."
            />
          </div>
          <div class="tp-field">
            <label class="tp-field-label"
              >Hipótese Diagnóstica / CID do Novo Plano</label
            >
            <input
              v-model="globalDiagnosisTitle"
              type="text"
              class="tp-field-input"
              placeholder="Ex: Esmalte escurecido (K03.7) + má oclusão leve"
            />
          </div>
        </div>
      </div>

      <!-- ── Empty State ── -->
      <div
        v-if="!treatmentPlans || treatmentPlans.length === 0"
        class="tp-empty"
      >
        <div class="tp-empty-icon">
          <i class="i-lucide-clipboard-list" />
        </div>
        <p class="tp-empty-text">Nenhum plano de tratamento criado ainda.</p>
        <p class="tp-empty-hint">
          Preencha os campos acima e clique em "Novo Plano".
        </p>
      </div>

      <!-- ── Planos ── -->
      <div
        v-for="plan in treatmentPlans"
        :key="plan.id"
        class="tp-plan page-break-inside-avoid print-card"
      >
        <!-- Cabeçalho do plano -->
        <div class="tp-plan-head">
          <div class="tp-plan-head-left">
            <div class="tp-plan-head-icon">
              <i class="i-lucide-list-checks" />
            </div>
            <div>
              <span class="tp-plan-name">Plano de Tratamento</span>
              <span class="tp-plan-cid">{{
                plan.title || 'Sem hipótese definida'
              }}</span>
            </div>
          </div>
          <div class="tp-plan-actions hide-on-print">
            <!-- Aprovado -->
            <span
              v-if="plan.status === 'aprovado' || plan.status === 'approved'"
              class="tp-badge tp-badge--green"
            >
              <i class="i-lucide-check-circle tp-badge-icon" /> Aprovado
            </span>
            <!-- Proposto -->
            <template v-else-if="plan.status === 'proposto'">
              <button
                class="tp-action-btn"
                @click="
                  editingPlanId === plan.id
                    ? savePlan(plan)
                    : (editingPlanId = plan.id)
                "
              >
                <i
                  :class="
                    editingPlanId === plan.id
                      ? 'i-lucide-save'
                      : 'i-lucide-pencil'
                  "
                  class="tp-action-btn-icon"
                />
                {{
                  editingPlanId === plan.id ? 'Salvar Plano' : 'Editar Plano'
                }}
              </button>
              <button
                class="tp-action-btn tp-action-btn--green"
                @click="approvePlan(plan.id)"
              >
                <i class="i-lucide-check-circle tp-action-btn-icon" /> Aprovar
              </button>
              <button
                class="tp-action-btn tp-action-btn--danger"
                @click="requestDeletePlan(plan.id)"
              >
                <i class="i-lucide-trash-2 tp-action-btn-icon" />
              </button>
            </template>
          </div>
        </div>

        <!-- Diagnóstico e Hipótese -->
        <div class="tp-section">
          <div class="tp-section-label">
            <i class="i-lucide-search tp-section-icon tp-section-icon--blue" />
            Diagnóstico e Hipótese
          </div>

          <!-- Modo edição -->
          <div v-if="editingPlanId === plan.id" class="tp-section-body">
            <div class="tp-field">
              <label class="tp-field-label"
                >Justificativa Clínica / Queixa Principal</label
              >
              <textarea
                v-model="plan.description"
                class="tp-field-input"
                rows="2"
              />
            </div>
            <div class="tp-field">
              <label class="tp-field-label">Hipótese Diagnóstica / CID</label>
              <input v-model="plan.title" type="text" class="tp-field-input" />
            </div>
          </div>

          <!-- Modo leitura -->
          <div v-else class="tp-section-body tp-diag-grid">
            <div class="tp-diag-item">
              <span class="tp-diag-label"
                >Justificativa / Queixa Principal</span
              >
              <p class="tp-diag-value">
                {{
                  plan.description ||
                  'O paciente não informou a queixa principal.'
                }}
              </p>
            </div>
            <div class="tp-diag-item">
              <span class="tp-diag-label">Hipótese / CID</span>
              <p class="tp-diag-value tp-diag-value--accent">
                {{ plan.title || 'Nenhum CID informado.' }}
              </p>
            </div>
          </div>
        </div>

        <!-- Procedimentos Planejados -->
        <div class="tp-section">
          <div class="tp-section-label">
            <i
              class="i-lucide-clipboard-list tp-section-icon tp-section-icon--amber"
            />
            Procedimentos Planejados
            <button
              v-if="plan.status === 'proposto'"
              class="tp-add-btn hide-on-print"
              @click="openItemModal(plan)"
            >
              <i class="i-lucide-plus tp-add-btn-icon" /> Adicionar
            </button>
          </div>

          <div class="tp-section-body">
            <table class="tp-table">
              <thead class="tp-table-head">
                <tr>
                  <th class="tp-th">Procedimento</th>
                  <th class="tp-th">Região/Elemento</th>
                  <th class="tp-th tp-th--center">Sessões</th>
                  <th class="tp-th tp-th--right">Valor Un.</th>
                  <th class="tp-th tp-th--right">Subtotal</th>
                  <th class="tp-th tp-th--center hide-on-print">Status</th>
                  <th
                    v-if="plan.status === 'proposto'"
                    class="tp-th tp-th--right hide-on-print"
                  >
                    Ação
                  </th>
                </tr>
              </thead>
              <tbody>
                <tr
                  v-if="
                    !plan.treatment_items || plan.treatment_items.length === 0
                  "
                >
                  <td colspan="7" class="tp-td-empty">
                    Nenhum procedimento adicionado a este plano.
                  </td>
                </tr>
                <tr
                  v-for="item in plan.treatment_items"
                  :key="item.id"
                  class="tp-tr"
                >
                  <td class="tp-td tp-td--name">
                    {{ item.procedure_name || item.procedure_code }}
                  </td>
                  <td class="tp-td tp-td--muted">
                    {{ item.region || item.tooth_number || '-' }}
                  </td>
                  <td class="tp-td tp-td--muted tp-td--center">
                    {{ item.sessions_planned }}
                  </td>
                  <td class="tp-td tp-td--muted tp-td--right">
                    {{ formatCurrency(item.unit_price) }}
                  </td>
                  <td class="tp-td tp-td--strong tp-td--right">
                    {{
                      formatCurrency(
                        (item.unit_price || 0) * (item.sessions_planned || 1)
                      )
                    }}
                  </td>
                  <td class="tp-td tp-td--center hide-on-print">
                    <span
                      class="tp-status"
                      :class="
                        item.status === 'aprovado' || item.status === 'approved'
                          ? 'tp-status--green'
                          : 'tp-status--blue'
                      "
                    >
                      {{
                        item.status === 'aprovado' || item.status === 'approved'
                          ? 'Aprovado'
                          : 'Proposto'
                      }}
                    </span>
                  </td>
                  <td
                    v-if="plan.status === 'proposto'"
                    class="tp-td tp-td--right hide-on-print"
                  >
                    <div class="tp-row-actions">
                      <button
                        class="tp-icon-btn"
                        title="Editar"
                        @click="openItemModal(plan, item)"
                      >
                        <i class="i-lucide-pencil" />
                      </button>
                      <button
                        class="tp-icon-btn tp-icon-btn--danger"
                        title="Remover"
                        @click="requestDeleteItem(plan.id, item.id)"
                      >
                        <i class="i-lucide-trash" />
                      </button>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>

            <!-- Total estimado -->
            <div
              v-if="plan.treatment_items && plan.treatment_items.length > 0"
              class="tp-total"
            >
              <span class="tp-total-label">Total Estimado</span>
              <span class="tp-total-value">{{
                formatCurrency(
                  plan.treatment_items.reduce(
                    (sum, item) =>
                      sum +
                      (item.unit_price || 0) * (item.sessions_planned || 1),
                    0
                  )
                )
              }}</span>
            </div>
          </div>
        </div>

        <!-- Observações e Previsão -->
        <div class="tp-section">
          <div class="tp-section-label">
            <i
              class="i-lucide-calendar-clock tp-section-icon tp-section-icon--purple"
            />
            Observações e Previsão
          </div>
          <div class="tp-section-body tp-diag-grid">
            <div class="tp-diag-item">
              <span class="tp-diag-label">Previsão de Conclusão</span>
              <template v-if="editingPlanId === plan.id">
                <input
                  v-model="plan.estimated_duration"
                  type="text"
                  class="tp-field-input tp-field-input--sm"
                  placeholder="Ex: Aprox. 45 dias"
                />
              </template>
              <p v-else class="tp-diag-value">
                {{ plan.estimated_duration || 'Não informada' }}
              </p>
            </div>
            <div class="tp-diag-item">
              <span class="tp-diag-label">Profissional Responsável</span>
              <p class="tp-diag-value">
                {{ plan.professional_name || 'Profissional da Conta' }}
              </p>
            </div>
          </div>

          <!-- Footer do plano -->
          <div class="tp-plan-footer">
            <div class="tp-approval-info">
              <i
                class="i-lucide-shield-check tp-approval-icon"
                :class="
                  plan.status === 'aprovado' || plan.status === 'approved'
                    ? 'tp-approval-icon--green'
                    : 'tp-approval-icon--muted'
                "
              />
              <span>{{
                plan.status === 'aprovado' || plan.status === 'approved'
                  ? 'Plano aprovado em ' +
                    formatDate(plan.approved_at || new Date())
                  : 'Plano pendente de aprovação.'
              }}</span>
            </div>
            <div class="hide-on-print">
              <a
                v-if="plan.pdf_url"
                :href="plan.pdf_url"
                target="_blank"
                rel="noopener noreferrer"
                class="tp-action-btn"
              >
                <i class="i-lucide-file-text tp-action-btn-icon" />
                Visualizar PDF
              </a>
              <button v-else class="tp-action-btn" @click="printPlan(plan)">
                <i class="i-lucide-printer tp-action-btn-icon" />
                Imprimir Plano
              </button>
            </div>
          </div>
        </div>
      </div>
      <!-- fim v-for -->
    </div>
  </div>
</template>

<style scoped>
/* ================================================================
   TREATMENT PLAN TAB — tp-* design system
   Light/dark dual-theme via rgb(var(--slate-N))
   Zero hardcoded dark colors. Zero box-shadow.
   ================================================================ */

/* ── Layout geral ── */
.tp-tab {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.tp-content-grid {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

/* ── Cabeçalho da aba ── */
.tp-tab-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  margin-bottom: 20px;
}

.tp-tab-title {
  font-size: 20px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0;
}

.tp-tab-subtitle {
  font-size: 13px;
  color: rgb(var(--slate-9));
  margin: 4px 0 0;
}

/* ── Botão Novo Plano ── */
.tp-btn-new {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: #3b82f6;
  color: #fff;
  border: none;
  border-radius: 8px;
  padding: 8px 16px;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  box-shadow: none;
  transition: background 0.15s;
  flex-shrink: 0;
}
.tp-btn-new:hover {
  background: #2563eb;
}
.tp-btn-new-icon {
  width: 14px;
  height: 14px;
  flex-shrink: 0;
}

/* ── Card genérico (formulário diagnóstico) ── */
.tp-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
}

.tp-card-header {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 14px 18px;
  border-bottom: 1px solid rgb(var(--slate-4));
}

.tp-card-header-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 34px;
  height: 34px;
  border-radius: 8px;
  flex-shrink: 0;
  font-size: 16px;
}
.tp-card-header-icon--blue {
  background: rgba(59, 130, 246, 0.12);
  color: #2563eb;
}

.tp-card-title {
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  line-height: 1.3;
}
.tp-card-subtitle {
  display: block;
  font-size: 12px;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}

.tp-card-body {
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 18px;
}

/* ── Campos de formulário ── */
.tp-field {
  display: flex;
  flex-direction: column;
  gap: 5px;
}

.tp-field-label {
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-11));
}

.tp-field-input {
  width: 100%;
  box-sizing: border-box;
  padding: 8px 12px;
  border: 1px solid rgb(var(--border-strong));
  border-radius: 8px;
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-12));
  font-size: 14px;
  font-family: inherit;
  outline: none;
  box-shadow: none;
  resize: vertical;
  transition: border-color 0.15s;
}
.tp-field-input:focus {
  border-color: rgb(var(--blue-9));
}
.tp-field-input::placeholder {
  color: rgb(var(--slate-8));
}
.tp-field-input--sm {
  font-size: 13px;
  padding: 6px 10px;
}

/* ── Empty state ── */
.tp-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 8px;
  padding: 40px 24px;
  background: rgb(var(--slate-2));
  border: 1px dashed rgb(var(--slate-5));
  border-radius: 12px;
  text-align: center;
}
.tp-empty-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 44px;
  height: 44px;
  border-radius: 10px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
  color: rgb(var(--slate-8));
  font-size: 20px;
}
.tp-empty-text {
  font-size: 14px;
  font-weight: 500;
  color: rgb(var(--slate-10));
  margin: 0;
}
.tp-empty-hint {
  font-size: 12px;
  color: rgb(var(--slate-8));
  margin: 0;
}

/* ── Card do plano ── */
.tp-plan {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
}

/* Cabeçalho do plano */
.tp-plan-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 14px 18px;
  background: rgb(var(--slate-2));
  border-bottom: 1px solid rgb(var(--slate-4));
  gap: 12px;
}

.tp-plan-head-left {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.tp-plan-head-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 8px;
  background: rgba(22, 163, 74, 0.12);
  color: #16a34a;
  font-size: 15px;
  flex-shrink: 0;
}

.tp-plan-name {
  display: block;
  font-size: 14px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  line-height: 1.3;
}

.tp-plan-cid {
  display: block;
  font-size: 12px;
  color: rgb(var(--slate-9));
  margin-top: 1px;
}

.tp-plan-actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-shrink: 0;
}

/* ── Badges de status ── */
.tp-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 11px;
  font-weight: 600;
  padding: 3px 10px;
  border-radius: 99px;
}
.tp-badge--green {
  background: rgba(22, 163, 74, 0.1);
  color: #16a34a;
  border: 1px solid rgba(22, 163, 74, 0.2);
}
.tp-badge-icon {
  width: 12px;
  height: 12px;
}

/* ── Botões de ação do plano ── */
.tp-action-btn {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 13px;
  font-weight: 500;
  padding: 5px 12px;
  border-radius: 7px;
  border: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-10));
  cursor: pointer;
  transition:
    background 0.12s,
    color 0.12s,
    border-color 0.12s;
  text-decoration: none;
  white-space: nowrap;
}
.tp-action-btn:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
  border-color: rgb(var(--slate-5));
}
.tp-action-btn--green {
  color: #16a34a;
  border-color: rgba(22, 163, 74, 0.22);
  background: rgba(22, 163, 74, 0.06);
}
.tp-action-btn--green:hover {
  background: rgba(22, 163, 74, 0.12);
}
.tp-action-btn--danger {
  color: #dc2626;
  border-color: rgba(220, 38, 38, 0.18);
  background: transparent;
}
.tp-action-btn--danger:hover {
  background: rgba(220, 38, 38, 0.07);
}
.tp-action-btn-icon {
  width: 13px;
  height: 13px;
  flex-shrink: 0;
}

/* ── Seções internas do plano ── */
.tp-section {
  border-top: 1px solid rgb(var(--slate-4));
}

.tp-section-label {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: rgb(var(--slate-9));
  padding: 10px 18px;
}

.tp-section-icon {
  width: 13px;
  height: 13px;
  flex-shrink: 0;
}
.tp-section-icon--blue {
  color: #3b82f6;
}
.tp-section-icon--amber {
  color: #d97706;
}
.tp-section-icon--purple {
  color: #7c3aed;
}

.tp-add-btn {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  font-weight: 500;
  padding: 4px 10px;
  border-radius: 6px;
  border: 1px solid rgb(var(--slate-4));
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-10));
  cursor: pointer;
  margin-left: auto;
  transition:
    background 0.12s,
    color 0.12s;
  white-space: nowrap;
}
.tp-add-btn:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}
.tp-add-btn-icon {
  width: 12px;
  height: 12px;
}

.tp-section-body {
  padding: 14px 18px;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

/* Grid de diagnóstico (2 colunas) */
.tp-diag-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.tp-diag-item {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.tp-diag-label {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
}

.tp-diag-value {
  font-size: 13px;
  font-weight: 400;
  color: rgb(var(--slate-11));
  margin: 0;
  line-height: 1.5;
}
.tp-diag-value--accent {
  color: #2563eb;
  font-weight: 500;
}

/* ── Tabela de procedimentos ── */
.tp-table {
  width: 100%;
  border-collapse: collapse;
}

.tp-table-head {
  background: rgb(var(--slate-3));
  border-bottom: 1px solid rgb(var(--slate-4));
}

.tp-th {
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
  padding: 9px 12px;
  text-align: left;
  white-space: nowrap;
}
.tp-th--center {
  text-align: center;
}
.tp-th--right {
  text-align: right;
}

.tp-tr {
  border-bottom: 1px solid rgb(var(--slate-3));
  transition: background 0.1s;
}
.tp-tr:last-child {
  border-bottom: none;
}
.tp-tr:hover {
  background: rgb(var(--slate-3));
}

.tp-td {
  font-size: 13px;
  padding: 10px 12px;
  color: rgb(var(--slate-11));
}
.tp-td--name {
  font-weight: 500;
  color: rgb(var(--slate-12));
}
.tp-td--muted {
  color: rgb(var(--slate-9));
}
.tp-td--strong {
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.tp-td--center {
  text-align: center;
}
.tp-td--right {
  text-align: right;
}

.tp-td-empty {
  font-size: 13px;
  color: rgb(var(--slate-8));
  text-align: center;
  padding: 24px 12px;
}

/* Status badge na tabela */
.tp-status {
  display: inline-flex;
  align-items: center;
  font-size: 11px;
  font-weight: 600;
  padding: 2px 9px;
  border-radius: 99px;
}
.tp-status--blue {
  background: rgba(59, 130, 246, 0.1);
  color: #2563eb;
  border: 1px solid rgba(59, 130, 246, 0.18);
}
.tp-status--green {
  background: rgba(22, 163, 74, 0.1);
  color: #16a34a;
  border: 1px solid rgba(22, 163, 74, 0.18);
}

/* Botões de ação inline na tabela */
.tp-row-actions {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 4px;
}

.tp-icon-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  border: 1px solid rgb(var(--slate-4));
  background: transparent;
  color: rgb(var(--slate-8));
  cursor: pointer;
  font-size: 13px;
  transition:
    background 0.12s,
    color 0.12s;
}
.tp-icon-btn:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}
.tp-icon-btn--danger:hover {
  background: rgba(220, 38, 38, 0.07);
  color: #dc2626;
  border-color: rgba(220, 38, 38, 0.18);
}

/* ── Total estimado ── */
.tp-total {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 12px;
  padding: 12px 16px;
  background: rgb(var(--slate-2));
  border-top: 1px solid rgb(var(--slate-4));
  border-radius: 0 0 8px 8px;
}

.tp-total-label {
  font-size: 12px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
}

.tp-total-value {
  font-size: 16px;
  font-weight: 700;
  color: #2563eb;
}

/* ── Footer do plano ── */
.tp-plan-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 12px 0 0;
  border-top: 1px solid rgb(var(--slate-4));
  margin-top: 4px;
  gap: 12px;
}

.tp-approval-info {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 12px;
  color: rgb(var(--slate-9));
}

.tp-approval-icon {
  width: 13px;
  height: 13px;
  flex-shrink: 0;
}
.tp-approval-icon--green {
  color: #16a34a;
}
.tp-approval-icon--muted {
  color: rgb(var(--slate-8));
}

/* ── Print ── */
@media print {
  .hide-on-print {
    display: none !important;
  }
  .tp-plan {
    border: 1px solid #ccc !important;
    background: white !important;
  }
  .tp-table-head {
    background: #f8fafc !important;
  }
  .tp-total {
    background: #f8fafc !important;
  }
}
</style>
