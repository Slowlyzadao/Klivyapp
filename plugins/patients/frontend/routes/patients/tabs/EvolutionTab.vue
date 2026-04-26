<script setup>
import { computed } from 'vue';

const props = defineProps({
  currentNote: { type: Object, required: true },
  clinicalNotes: { type: Array, default: () => [] },
  isSavingNote: { type: Boolean, default: false },
  formatDate: { type: Function, required: true },
  canCreate: { type: Boolean, default: false },
  canSign: { type: Boolean, default: false },
  canDelete: { type: Boolean, default: false },
  noCreateMsg: {
    type: String,
    default: 'Você não tem permissão para criar evoluções',
  },
});

const emit = defineEmits([
  'update:currentNote',
  'save',
  'request-delete',
  'edit-note',
]);

const note = computed({
  get: () => props.currentNote,
  set: val => emit('update:currentNote', val),
});

function updateNote(field, value) {
  emit('update:currentNote', { ...props.currentNote, [field]: value });
}

const canSubmit = computed(
  () =>
    !props.isSavingNote &&
    (props.currentNote.assessment || props.currentNote.conduct)
);
</script>

<template>
  <div class="evo-root">
    <!-- Banner de bloqueio quando o usuário não pode criar evoluções -->
    <div
      v-if="!canCreate"
      class="mb-4 px-3 py-2 rounded-md border border-dashed border-n-slate-5 bg-n-slate-2 text-xs text-n-slate-11 flex items-center gap-2"
    >
      <i class="i-lucide-lock w-3.5 h-3.5" />
      {{ noCreateMsg }}
    </div>

    <!-- ══════════════════════════════════════
         SEÇÃO 1 — FORMULÁRIO DE ATENDIMENTO
    ══════════════════════════════════════ -->
    <div
      class="evo-form-card"
      :inert="!canCreate"
      :class="{ 'opacity-60': !canCreate }"
    >
      <!-- Cabeçalho do card -->
      <div class="evo-form-card-head">
        <div class="evo-form-card-head-info">
          <div class="evo-icon-wrap evo-icon-wrap--cyan">
            <i class="i-lucide-stethoscope" />
          </div>
          <div>
            <h4 class="evo-form-card-title">Atendimento Atual</h4>
            <p class="evo-form-card-desc">
              Preencha os dados do atendimento de hoje
            </p>
          </div>
        </div>
        <div class="evo-form-card-head-badge">
          <i class="i-lucide-clock-4 evo-badge-icon" />
          <span>Em andamento</span>
        </div>
      </div>

      <!-- Corpo do formulário -->
      <div class="evo-form-body">
        <!-- Linha 1: Modelo + Profissional -->
        <div class="evo-form-row">
          <div class="evo-form-group">
            <label class="evo-label">
              <i class="i-lucide-layout-template evo-label-icon" />
              Modelo de Evolução
            </label>
            <select
              class="evo-select"
              :value="currentNote.note_template"
              @change="updateNote('note_template', $event.target.value)"
            >
              <option value="Evolução Padrão">Evolução Padrão</option>
              <option value="Primeira Consulta Estética">
                Primeira Consulta Estética
              </option>
              <option value="Revisão / Retorno">Revisão / Retorno</option>
              <option value="Sessão de Laser">Sessão de Laser</option>
            </select>
          </div>
          <div class="evo-form-group">
            <label class="evo-label">
              <i class="i-lucide-user-check evo-label-icon" />
              Profissional Responsável
            </label>
            <select class="evo-select" disabled>
              <option selected>Você (Usuário Logado)</option>
            </select>
          </div>
        </div>

        <!-- Queixa -->
        <div class="evo-form-section">
          <div class="evo-section-title">
            <span class="evo-section-dot evo-section-dot--blue" />
            Queixa do Dia
          </div>
          <input
            class="evo-input"
            type="text"
            placeholder="Qual o principal relato do paciente hoje?"
            :value="currentNote.complaint_of_day"
            @input="updateNote('complaint_of_day', $event.target.value)"
          />
        </div>

        <!-- Avaliação -->
        <div class="evo-form-section">
          <div class="evo-section-title">
            <span class="evo-section-dot evo-section-dot--purple" />
            Avaliação Clínica
          </div>
          <textarea
            class="evo-textarea"
            rows="3"
            placeholder="Descreva os achados clínicos, exame físico e observações relevantes..."
            :value="currentNote.assessment"
            @input="updateNote('assessment', $event.target.value)"
          />
        </div>

        <!-- Conduta -->
        <div class="evo-form-section">
          <div class="evo-section-title">
            <span class="evo-section-dot evo-section-dot--green" />
            Conduta Realizada
          </div>
          <textarea
            class="evo-textarea"
            rows="3"
            placeholder="Quais procedimentos foram realizados hoje? Produtos, técnicas, dosagens..."
            :value="currentNote.conduct"
            @input="updateNote('conduct', $event.target.value)"
          />
        </div>

        <!-- Intercorrências + Orientações -->
        <div class="evo-form-row">
          <div class="evo-form-section">
            <div class="evo-section-title">
              <span class="evo-section-dot evo-section-dot--amber" />
              Intercorrências / Observações
            </div>
            <textarea
              class="evo-textarea evo-textarea--sm"
              rows="2"
              placeholder="Houve alguma intercorrência? (opcional)"
              :value="currentNote.complications"
              @input="updateNote('complications', $event.target.value)"
            />
          </div>
          <div class="evo-form-section">
            <div class="evo-section-title">
              <span class="evo-section-dot evo-section-dot--cyan" />
              Orientações ao Paciente
            </div>
            <textarea
              class="evo-textarea evo-textarea--sm"
              rows="2"
              placeholder="Cuidados pós-procedimento, medicações, recomendações..."
              :value="currentNote.guidance_given"
              @input="updateNote('guidance_given', $event.target.value)"
            />
          </div>
        </div>

        <!-- Footer: retorno + botões -->
        <div class="evo-form-footer">
          <div class="evo-retorno">
            <label class="evo-label">
              <i class="i-lucide-calendar-check evo-label-icon" />
              Retorno
            </label>
            <div class="evo-retorno-wrap">
              <input
                class="evo-input evo-input--number"
                type="number"
                min="0"
                placeholder="15"
                :value="currentNote.return_recommended"
                @input="updateNote('return_recommended', $event.target.value)"
              />
              <span class="evo-retorno-unit">dias</span>
            </div>
          </div>

          <div class="evo-form-actions">
            <button
              v-if="canCreate"
              class="evo-btn evo-btn--ghost"
              :disabled="isSavingNote"
              @click="emit('save', false)"
            >
              <i class="i-lucide-save evo-btn-icon" />
              Salvar Rascunho
            </button>
            <button
              v-if="canSign"
              class="evo-btn evo-btn--primary"
              :disabled="!canSubmit"
              @click="emit('save', true)"
            >
              <i class="i-lucide-lock evo-btn-icon" />
              Assinar e Salvar
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ══════════════════════════════════════
         SEÇÃO 2 — HISTÓRICO (TIMELINE)
    ══════════════════════════════════════ -->
    <div class="evo-history">
      <!-- Cabeçalho do histórico -->
      <div class="evo-history-head">
        <div class="evo-icon-wrap evo-icon-wrap--purple">
          <i class="i-lucide-history" />
        </div>
        <div>
          <h4 class="evo-form-card-title">Histórico de Atendimentos</h4>
          <p class="evo-form-card-desc">
            {{ clinicalNotes.length }} evolução{{
              clinicalNotes.length !== 1 ? 'ões' : ''
            }}
            registrada{{ clinicalNotes.length !== 1 ? 's' : '' }}
          </p>
        </div>
      </div>

      <!-- Empty state -->
      <div v-if="clinicalNotes.length === 0" class="evo-empty">
        <div class="evo-empty-icon-wrap">
          <i class="i-lucide-file-clock" />
        </div>
        <p class="evo-empty-title">Nenhuma evolução registrada</p>
        <p class="evo-empty-desc">
          Preencha o formulário acima e clique em "Assinar e Salvar" para
          registrar o primeiro atendimento.
        </p>
      </div>

      <!-- Timeline de notas -->
      <div v-else class="evo-timeline">
        <div
          v-for="(note, index) in clinicalNotes"
          :key="note.id"
          class="evo-timeline-item"
          :class="
            note.signed_at
              ? 'evo-timeline-item--signed'
              : 'evo-timeline-item--draft'
          "
        >
          <!-- Linha vertical da timeline -->
          <div class="evo-timeline-line">
            <div
              class="evo-timeline-dot"
              :class="
                note.signed_at
                  ? 'evo-timeline-dot--signed'
                  : 'evo-timeline-dot--draft'
              "
            >
              <i
                :class="note.signed_at ? 'i-lucide-check' : 'i-lucide-pencil'"
                class="evo-timeline-dot-icon"
              />
            </div>
            <div
              v-if="index < clinicalNotes.length - 1"
              class="evo-timeline-connector"
            />
          </div>

          <!-- Card da nota -->
          <div
            class="evo-note-card"
            :class="
              note.signed_at ? 'evo-note-card--signed' : 'evo-note-card--draft'
            "
          >
            <!-- Header do card -->
            <div class="evo-note-card-head">
              <div class="evo-note-card-head-left">
                <div class="evo-note-card-date">
                  <i class="i-lucide-calendar evo-note-date-icon" />
                  {{ formatDate(note.note_date || note.created_at) }}
                </div>
                <span
                  class="evo-note-status"
                  :class="
                    note.signed_at
                      ? 'evo-note-status--signed'
                      : 'evo-note-status--draft'
                  "
                >
                  {{ note.signed_at ? '✓ Assinada' : '✎ Rascunho' }}
                </span>
                <span
                  v-if="note.signed_by_id || note.professional"
                  class="evo-note-author"
                >
                  <i class="i-lucide-user evo-note-author-icon" />
                  {{
                    note.signed_by?.name ||
                    note.professional?.name ||
                    'Profissional'
                  }}
                </span>
              </div>
              <div
                v-if="!note.signed_at && (canCreate || canDelete)"
                class="evo-note-card-actions"
              >
                <button
                  v-if="canCreate"
                  class="evo-note-action-btn"
                  title="Editar evolução"
                  @click="emit('edit-note', note)"
                >
                  <i class="i-lucide-pencil" />
                </button>
                <button
                  v-if="canDelete"
                  class="evo-note-action-btn evo-note-action-btn--danger"
                  title="Excluir evolução"
                  @click="emit('request-delete', note.id)"
                >
                  <i class="i-lucide-trash-2" />
                </button>
              </div>
            </div>

            <!-- Campos da nota -->
            <div class="evo-note-fields">
              <div v-if="note.complaint_of_day" class="evo-note-field-item">
                <div class="evo-note-field-chip evo-note-field-chip--blue">
                  Queixa
                </div>
                <p class="evo-note-field-text">{{ note.complaint_of_day }}</p>
              </div>
              <div v-if="note.assessment" class="evo-note-field-item">
                <div class="evo-note-field-chip evo-note-field-chip--purple">
                  Avaliação
                </div>
                <p class="evo-note-field-text">{{ note.assessment }}</p>
              </div>
              <div v-if="note.conduct" class="evo-note-field-item">
                <div class="evo-note-field-chip evo-note-field-chip--green">
                  Conduta
                </div>
                <p class="evo-note-field-text">{{ note.conduct }}</p>
              </div>
              <div v-if="note.complications" class="evo-note-field-item">
                <div class="evo-note-field-chip evo-note-field-chip--amber">
                  Intercorrência
                </div>
                <p class="evo-note-field-text">{{ note.complications }}</p>
              </div>
              <div v-if="note.guidance_given" class="evo-note-field-item">
                <div class="evo-note-field-chip evo-note-field-chip--cyan">
                  Orientações
                </div>
                <p class="evo-note-field-text">{{ note.guidance_given }}</p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ═══════════════════════════════
   ROOT / LAYOUT
═══════════════════════════════ */
.evo-root {
  display: flex;
  flex-direction: column;
  gap: 20px;
}

/* ═══════════════════════════════
   CARD DO FORMULÁRIO
═══════════════════════════════ */
.evo-form-card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  overflow: hidden;
}

.evo-form-card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  background: rgb(var(--slate-2));
  border-bottom: 1px solid rgb(var(--slate-4));
  gap: 12px;
}

.evo-form-card-head-info {
  display: flex;
  align-items: center;
  gap: 12px;
}

.evo-form-card-title {
  font-size: 15px;
  font-weight: 700;
  color: rgb(var(--slate-12));
  margin: 0;
  line-height: 1.3;
}

.evo-form-card-desc {
  font-size: 12px;
  color: rgb(var(--slate-9));
  margin: 2px 0 0;
}

/* Badge "Em andamento" */
.evo-form-card-head-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  font-weight: 600;
  padding: 3px 10px;
  border-radius: 99px;
  background: rgba(6, 182, 212, 0.08);
  border: 1px solid rgba(6, 182, 212, 0.2);
  color: #0891b2;
  white-space: nowrap;
}
.evo-badge-icon {
  width: 11px;
  height: 11px;
}

/* ═══════════════════════════════
   ÍCONES COLORIDOS
═══════════════════════════════ */
.evo-icon-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 10px;
  font-size: 17px;
  flex-shrink: 0;
}
.evo-icon-wrap--cyan {
  background: rgba(6, 182, 212, 0.12);
  color: #0891b2;
}
.evo-icon-wrap--purple {
  background: rgba(124, 58, 237, 0.12);
  color: #7c3aed;
}

/* ═══════════════════════════════
   FORMULÁRIO
═══════════════════════════════ */
.evo-form-body {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding: 0;
}

.evo-form-section {
  padding: 14px 20px;
  border-bottom: 1px solid rgb(var(--slate-3));
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.evo-form-section:last-child {
  border-bottom: none;
}

.evo-form-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
}
.evo-form-row > .evo-form-group,
.evo-form-row > .evo-form-section {
  border-right: 1px solid rgb(var(--slate-3));
}
.evo-form-row > .evo-form-group:last-child,
.evo-form-row > .evo-form-section:last-child {
  border-right: none;
}

.evo-form-group {
  padding: 14px 20px;
  border-bottom: 1px solid rgb(var(--slate-3));
  display: flex;
  flex-direction: column;
  gap: 8px;
}

/* Label com ícone */
.evo-label {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
}
.evo-label-icon {
  width: 11px;
  height: 11px;
  flex-shrink: 0;
}

/* Título de seção com pontinho colorido */
.evo-section-title {
  display: flex;
  align-items: center;
  gap: 7px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
}
.evo-section-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  flex-shrink: 0;
}
.evo-section-dot--blue {
  background: #3b82f6;
}
.evo-section-dot--purple {
  background: #7c3aed;
}
.evo-section-dot--green {
  background: #16a34a;
}
.evo-section-dot--amber {
  background: #d97706;
}
.evo-section-dot--cyan {
  background: #0891b2;
}

/* Inputs */
.evo-input,
.evo-select,
.evo-textarea {
  width: 100%;
  box-sizing: border-box;
  padding: 9px 12px;
  font-size: 13px;
  font-family: inherit;
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  outline: none;
  box-shadow: none !important;
  transition:
    border-color 0.15s,
    background 0.15s;
}
.evo-input:focus,
.evo-select:focus,
.evo-textarea:focus {
  border-color: #3b82f6;
  background: rgb(var(--slate-1));
}
.evo-input::placeholder,
.evo-textarea::placeholder {
  color: rgb(var(--slate-7));
}
.evo-select:disabled,
.evo-input:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

.evo-textarea {
  resize: vertical;
  min-height: 80px;
  line-height: 1.55;
}
.evo-textarea--sm {
  min-height: 70px;
}
.evo-input--number {
  max-width: 80px;
  text-align: center;
}

/* Footer do formulário */
.evo-form-footer {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  gap: 16px;
  padding: 16px 20px;
  background: rgb(var(--slate-2));
  border-top: 1px solid rgb(var(--slate-4));
}

.evo-retorno {
  display: flex;
  flex-direction: column;
  gap: 7px;
}
.evo-retorno-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
}
.evo-retorno-unit {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-9));
  white-space: nowrap;
}

.evo-form-actions {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* Botões */
.evo-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  font-size: 13px;
  font-weight: 600;
  padding: 8px 16px;
  border-radius: 8px;
  cursor: pointer;
  box-shadow: none !important;
  transition:
    background 0.15s,
    opacity 0.15s;
  border: none;
  white-space: nowrap;
}
.evo-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
}
.evo-btn-icon {
  width: 13px;
  height: 13px;
  flex-shrink: 0;
}

.evo-btn--ghost {
  background: transparent;
  border: 1px solid rgb(var(--slate-4));
  color: rgb(var(--slate-10));
}
.evo-btn--ghost:hover:not(:disabled) {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.evo-btn--primary {
  background: #3b82f6;
  color: #fff;
  border: none;
}
.evo-btn--primary:hover:not(:disabled) {
  background: #2563eb;
}

/* ═══════════════════════════════
   HISTÓRICO
═══════════════════════════════ */
.evo-history {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  overflow: hidden;
}

.evo-history-head {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 16px 20px;
  background: rgb(var(--slate-2));
  border-bottom: 1px solid rgb(var(--slate-4));
}

/* Empty state */
.evo-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 10px;
  padding: 52px 24px;
  text-align: center;
}
.evo-empty-icon-wrap {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 52px;
  height: 52px;
  border-radius: 14px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
  color: rgb(var(--slate-8));
  font-size: 24px;
}
.evo-empty-title {
  font-size: 15px;
  font-weight: 600;
  color: rgb(var(--slate-10));
  margin: 0;
}
.evo-empty-desc {
  font-size: 13px;
  color: rgb(var(--slate-8));
  margin: 0;
  max-width: 380px;
  line-height: 1.5;
}

/* ═══════════════════════════════
   TIMELINE
═══════════════════════════════ */
.evo-timeline {
  display: flex;
  flex-direction: column;
  padding: 20px;
  gap: 0;
}

.evo-timeline-item {
  display: flex;
  gap: 16px;
  align-items: flex-start;
}

.evo-timeline-line {
  display: flex;
  flex-direction: column;
  align-items: center;
  flex-shrink: 0;
  padding-top: 2px;
}

.evo-timeline-dot {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 50%;
  flex-shrink: 0;
  z-index: 1;
}
.evo-timeline-dot--signed {
  background: rgba(22, 163, 74, 0.12);
  border: 2px solid rgba(22, 163, 74, 0.3);
  color: #16a34a;
}
.evo-timeline-dot--draft {
  background: rgba(234, 179, 8, 0.12);
  border: 2px solid rgba(234, 179, 8, 0.3);
  color: #b45309;
}

.evo-timeline-dot-icon {
  width: 12px;
  height: 12px;
}

.evo-timeline-connector {
  width: 2px;
  flex: 1;
  min-height: 20px;
  background: rgb(var(--slate-4));
  margin: 4px 0;
}

/* Card da nota na timeline */
.evo-note-card {
  flex: 1;
  border-radius: 10px;
  border: 1px solid rgb(var(--slate-4));
  overflow: hidden;
  margin-bottom: 16px;
}
.evo-note-card--signed {
  border-left: 3px solid #16a34a;
}
.evo-note-card--draft {
  border-left: 3px solid #d97706;
}

.evo-note-card-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 10px 14px;
  background: rgb(var(--slate-2));
  border-bottom: 1px solid rgb(var(--slate-3));
  gap: 10px;
  flex-wrap: wrap;
}

.evo-note-card-head-left {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
  flex: 1;
  min-width: 0;
}

.evo-note-card-date {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-10));
}
.evo-note-date-icon {
  width: 11px;
  height: 11px;
  flex-shrink: 0;
}

.evo-note-status {
  display: inline-flex;
  align-items: center;
  font-size: 11px;
  font-weight: 700;
  padding: 2px 9px;
  border-radius: 99px;
}
.evo-note-status--signed {
  background: rgba(22, 163, 74, 0.1);
  color: #16a34a;
  border: 1px solid rgba(22, 163, 74, 0.2);
}
.evo-note-status--draft {
  background: rgba(234, 179, 8, 0.1);
  color: #b45309;
  border: 1px solid rgba(234, 179, 8, 0.2);
}

.evo-note-author {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 12px;
  color: rgb(var(--slate-8));
}
.evo-note-author-icon {
  width: 11px;
  height: 11px;
}

/* Botões de ação */
.evo-note-card-actions {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
}
.evo-note-action-btn {
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
  box-shadow: none !important;
}
.evo-note-action-btn:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}
.evo-note-action-btn--danger:hover {
  background: rgba(220, 38, 38, 0.08);
  color: #dc2626;
  border-color: rgba(220, 38, 38, 0.2);
}

/* Campos da nota */
.evo-note-fields {
  display: flex;
  flex-direction: column;
  padding: 12px 14px;
  gap: 0;
}

.evo-note-field-item {
  display: flex;
  gap: 12px;
  padding: 8px 0;
  border-bottom: 1px solid rgb(var(--slate-3));
  align-items: flex-start;
}
.evo-note-field-item:last-child {
  border-bottom: none;
  padding-bottom: 0;
}

.evo-note-field-chip {
  display: inline-flex;
  align-items: center;
  font-size: 10px;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 4px;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  white-space: nowrap;
  flex-shrink: 0;
  margin-top: 1px;
  min-width: 76px;
  justify-content: center;
}
.evo-note-field-chip--blue {
  background: rgba(59, 130, 246, 0.1);
  color: #1d4ed8;
  border: 1px solid rgba(59, 130, 246, 0.2);
}
.evo-note-field-chip--purple {
  background: rgba(124, 58, 237, 0.1);
  color: #6d28d9;
  border: 1px solid rgba(124, 58, 237, 0.2);
}
.evo-note-field-chip--green {
  background: rgba(22, 163, 74, 0.1);
  color: #15803d;
  border: 1px solid rgba(22, 163, 74, 0.2);
}
.evo-note-field-chip--amber {
  background: rgba(234, 179, 8, 0.1);
  color: #b45309;
  border: 1px solid rgba(234, 179, 8, 0.2);
}
.evo-note-field-chip--cyan {
  background: rgba(6, 182, 212, 0.1);
  color: #0e7490;
  border: 1px solid rgba(6, 182, 212, 0.2);
}

.evo-note-field-text {
  font-size: 13px;
  color: rgb(var(--slate-11));
  line-height: 1.55;
  margin: 0;
  flex: 1;
}
</style>
