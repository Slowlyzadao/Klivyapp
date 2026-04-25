<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          Questionário Clínico
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          Histórico de saúde, queixa principal, alergias e restrições.
          <span
            v-if="currentAnamnesis.status === 'finalized'"
            class="ml-2 inline-flex items-center gap-1 text-amber-400 text-xs bg-amber-500/10 px-2 py-0.5 rounded-full border border-amber-500/20"
          >
            <i class="i-lucide-lock w-3 h-3" /> Somente leitura (Assinada)
          </span>
        </p>
      </div>
      <div class="flex items-center gap-3">
        <span v-if="currentAnamnesis.updated_at" class="text-xs text-slate-500">
          Última alteração:
          {{ formatDate(currentAnamnesis.updated_at) }}
        </span>

        <a
          v-if="currentAnamnesis.pdf_url"
          :href="currentAnamnesis.pdf_url"
          target="_blank"
          rel="noopener noreferrer"
          class="btn-secondary flex items-center gap-2"
        >
          <i class="i-lucide-file-text" /> Visualizar PDF
        </a>

        <button
          v-if="currentAnamnesis.status === 'finalized'"
          class="btn-secondary flex items-center gap-2"
          @click="startNewAnamnesis"
        >
          <i class="i-lucide-plus" /> Nova Anamnese
        </button>

        <button
          v-else
          class="btn-secondary flex items-center gap-2"
          :disabled="isSavingAnamnesis"
          @click="saveAnamnesis(false)"
        >
          <i class="i-lucide-save" /> Salvar Rascunho
        </button>

        <button
          v-if="currentAnamnesis.status !== 'finalized'"
          class="btn-primary flex items-center gap-2"
          :disabled="isSavingAnamnesis"
          @click="saveAnamnesis(true)"
        >
          <i class="i-lucide-lock" /> Assinar e Finalizar
        </button>
      </div>
    </div>

    <!-- Seções da Anamnese -->
    <div class="reg-form-grid">
      <!-- ── SEÇÃO 1: MOTIVO DA CONSULTA ── -->
      <div class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-cyan">
              <i class="i-lucide-stethoscope w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Motivo da Consulta</span>
              <span class="reg-section-subtitle"
                >Especialidade, queixa principal e objetivo</span
              >
            </div>
          </div>
        </div>
        <div class="reg-section-body">
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label">Especialidade / Foco Principal</label>
              <select
                v-model="currentAnamnesis.specialty"
                class="form-input"
                :disabled="currentAnamnesis.status === 'finalized'"
              >
                <option value="Odontologia Geral">Odontologia Geral</option>
                <option value="Estética Facial">Estética Facial</option>
                <option value="Dermatologia">Dermatologia</option>
                <option value="Avaliação Clínica">Avaliação Clínica</option>
              </select>
            </div>
          </div>
          <div class="form-group">
            <label class="form-label">
              Queixa Principal
              <span class="reg-required">*</span>
            </label>
            <textarea
              v-model="currentAnamnesis.chief_complaint"
              class="form-input form-textarea"
              rows="3"
              placeholder="Descreva com as palavras do paciente o que o trouxe à clínica..."
              :disabled="currentAnamnesis.status === 'finalized'"
            />
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 2: HISTÓRICO DE SAÚDE ── -->
      <div class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-blue">
              <i class="i-lucide-activity w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Histórico de Saúde</span>
              <span class="reg-section-subtitle"
                >Doenças preexistentes e condições sistêmicas</span
              >
            </div>
          </div>
        </div>
        <div class="reg-section-body">
          <div class="anm-check-grid">
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.hypertension"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label"
                >Hipertensão ou problemas cardiovasculares</span
              >
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.pregnant"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label">Gestante / Lactante</span>
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.diabetes"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label">Diabetes</span>
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.oncology"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label"
                >Tratamento oncológico (Atual ou prévio)</span
              >
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.bleeding_disorder"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label"
                >Distúrbios de coagulação / hemorragia</span
              >
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.hepatitis"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label">Hepatite / Doenças hepáticas</span>
            </label>
          </div>
          <div class="form-group">
            <label class="form-label">Outras Doenças ou Condições</label>
            <input
              v-model="currentAnamnesis.medical_history.other"
              type="text"
              class="form-input"
              placeholder="Especifique detalhadamente se houver..."
              :disabled="currentAnamnesis.status === 'finalized'"
            />
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 3: ALERGIAS E MEDICAMENTOS ── -->
      <div class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-red">
              <i class="i-lucide-pill w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Alergias e Medicamentos</span>
              <span class="reg-section-subtitle"
                >Alergias conhecidas e uso contínuo</span
              >
            </div>
          </div>
        </div>
        <div class="reg-section-body">
          <div class="reg-field-grid-2">
            <div class="form-group">
              <label class="form-label anm-label-danger">
                <i class="i-lucide-triangle-alert w-3.5 h-3.5" />
                Alergias Conhecidas
                <span class="reg-required">*</span>
              </label>
              <input
                v-model="allergyInput"
                type="text"
                class="form-input anm-input-danger"
                placeholder="Ex: Dipirona, Iodo — separadas por vírgula"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div
                v-if="currentAnamnesis.allergies?.length"
                class="anm-tags-row"
              >
                <span
                  v-for="(alg, idx) in currentAnamnesis.allergies"
                  :key="idx"
                  class="anm-tag anm-tag--red"
                >
                  {{ alg.name }}
                </span>
              </div>
            </div>
            <div class="form-group">
              <label class="form-label">Medicamentos de Uso Contínuo</label>
              <input
                v-model="medicationInput"
                type="text"
                class="form-input"
                placeholder="Ex: Losartana 50mg, AAS..."
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div
                v-if="currentAnamnesis.current_medications?.length"
                class="anm-tags-row"
              >
                <span
                  v-for="(med, idx) in currentAnamnesis.current_medications"
                  :key="idx"
                  class="anm-tag anm-tag--blue"
                >
                  {{ med.name }}
                </span>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 4: HISTÓRICO CIRÚRGICO ── -->
      <div class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-orange">
              <i class="i-lucide-scissors w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title"
                >Histórico Cirúrgico e Implantes</span
              >
              <span class="reg-section-subtitle"
                >Cirurgias recentes, implantes e reações a anestesia</span
              >
            </div>
          </div>
        </div>
        <div class="reg-section-body">
          <div class="anm-check-col">
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.has_recent_surgeries"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label"
                >Realizou cirurgias nos últimos 6 meses?</span
              >
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.has_implants"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label"
                >Possui implantes, próteses ou marcapasso?</span
              >
            </label>
            <label class="check-item">
              <input
                v-model="currentAnamnesis.medical_history.has_anesthesia_complications"
                type="checkbox"
                :disabled="currentAnamnesis.status === 'finalized'"
              />
              <div class="check-item-box" />
              <span class="check-item-label"
                >Teve complicações ou reações com anestesia no passado?</span
              >
            </label>
          </div>
          <div class="form-group">
            <label class="form-label">Detalhes das Intervenções Recentes</label>
            <textarea
              v-model="currentAnamnesis.surgical_history"
              class="form-input form-textarea"
              rows="2"
              placeholder="Especifique os procedimentos, áreas e reações adversas..."
              :disabled="currentAnamnesis.status === 'finalized'"
            />
          </div>
        </div>
      </div>

      <!-- ── SEÇÃO 5: HÁBITOS E ESTILO DE VIDA ── -->
      <div class="reg-section">
        <div class="reg-section-toggle" style="cursor: default">
          <div class="reg-section-toggle-left">
            <div class="reg-section-icon reg-icon-green">
              <i class="i-lucide-leaf w-4 h-4" />
            </div>
            <div>
              <span class="reg-section-title">Hábitos e Estilo de Vida</span>
              <span class="reg-section-subtitle"
                >Tabagismo, álcool, atividade física e observações</span
              >
            </div>
          </div>
        </div>
        <div class="reg-section-body">
          <div class="reg-field-grid-3">
            <div class="form-group">
              <label class="form-label">Fumante?</label>
              <select
                v-model="currentAnamnesis.relevant_habits.smoker"
                class="form-input"
                :disabled="currentAnamnesis.status === 'finalized'"
              >
                <option value="Não">Não</option>
                <option value="Sim, regular">Sim, regular</option>
                <option value="Sim, socialmente">Sim, socialmente</option>
                <option value="Ex-fumante">Ex-fumante</option>
              </select>
            </div>
            <div class="form-group">
              <label class="form-label">Consumo de Álcool</label>
              <select
                v-model="currentAnamnesis.relevant_habits.alcohol"
                class="form-input"
                :disabled="currentAnamnesis.status === 'finalized'"
              >
                <option value="Não consome">Não consome</option>
                <option value="Ocasionalmente">Ocasionalmente</option>
                <option value="Frequentemente">Frequentemente</option>
              </select>
            </div>
            <div class="form-group">
              <label class="form-label">Prática de Esportes</label>
              <select
                v-model="currentAnamnesis.relevant_habits.sports"
                class="form-input"
                :disabled="currentAnamnesis.status === 'finalized'"
              >
                <option value="Sedentário">Sedentário</option>
                <option value="Atividade moderada">Atividade moderada</option>
                <option value="Atleta / Alta intensidade">
                  Atleta / Alta intensidade
                </option>
              </select>
            </div>
          </div>
          <div class="anm-notes-card">
            <div class="flex items-center gap-2 mb-3">
              <i class="i-lucide-shield-alert w-4 h-4 text-amber-400" />
              <span
                class="text-xs font-semibold text-amber-400 uppercase tracking-wider"
                >Observações Confidenciais</span
              >
            </div>
            <textarea
              v-model="currentAnamnesis.additional_notes"
              class="form-input form-textarea anm-notes-input"
              rows="3"
              placeholder="Contraindicações, restrições específicas da prática clínica..."
              :disabled="currentAnamnesis.status === 'finalized'"
            />
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
