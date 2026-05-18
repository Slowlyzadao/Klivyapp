<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<script setup>
/**
 * AnamnesisTab — Aba "Anamnese / Questionário Clínico" do prontuário.
 *
 * Histórico de saúde, queixa principal, alergias, medicamentos, hábitos.
 * Suporta rascunho ("Salvar") e finalização ("Assinar e Finalizar" → torna
 * o registro imutável e gera PDF assinado).
 *
 * Auto-suficiente: lê patientId da rota e faz seu próprio fetch ao montar.
 *
 * Componente extraído de Record.vue (Fase 5 do refactor — ver CHANGELOG).
 */
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import AnamnesisAPI from '@plugins/patients/frontend/api/patients/anamnesis';

const route = useRoute();

const formatDate = dateStr => {
  if (!dateStr) return '—';
  return formatDateBR(dateStr) || '—';
};

// ── Defaults ──────────────────────────────────────────────
const EMPTY_ANAMNESIS = () => ({
  id: null,
  specialty: 'Odontologia Geral',
  chief_complaint: '',
  medical_history: {
    hypertension: false,
    diabetes: false,
    bleeding_disorder: false,
    pregnant: false,
    oncology: false,
    hepatitis: false,
    other: '',
    has_recent_surgeries: false,
    has_implants: false,
    has_anesthesia_complications: false,
  },
  allergies: [],
  current_medications: [],
  contraindications: [],
  surgical_history: '',
  family_history: '',
  relevant_habits: {
    smoker: 'Não',
    alcohol: 'Não consome',
    sports: 'Sedentário',
  },
  pregnancy: {},
  additional_notes: '',
  status: 'draft',
});

// JSON round-trip: safe com Vue Proxies (structuredClone falha em Proxies reativos);
// os dados da anamnese são 100% JSON-seguros (sem Date/Map/Set).
const deepCloneAnamnesis = value => JSON.parse(JSON.stringify(value));

const normalizeAnamnesisFromServer = remote => {
  const base = EMPTY_ANAMNESIS();
  const clone = deepCloneAnamnesis(remote || {});
  return {
    ...base,
    ...clone,
    medical_history: {
      ...base.medical_history,
      ...(clone.medical_history ?? {}),
    },
    relevant_habits: {
      ...base.relevant_habits,
      ...(clone.relevant_habits ?? {}),
    },
    pregnancy: { ...base.pregnancy, ...(clone.pregnancy ?? {}) },
    allergies: Array.isArray(clone.allergies) ? clone.allergies : [],
    current_medications: Array.isArray(clone.current_medications)
      ? clone.current_medications
      : [],
    contraindications: Array.isArray(clone.contraindications)
      ? clone.contraindications
      : [],
  };
};

// ── State ──────────────────────────────────────────────────
const anamneses = ref([]);
const currentAnamnesis = ref(EMPTY_ANAMNESIS());
const allergyInput = ref('');
const medicationInput = ref('');
const isSavingAnamnesis = ref(false);

// ── Helpers / Actions ─────────────────────────────────────
// Aplica o state de forma cirúrgica: muta propriedades in-place em vez de
// substituir o Ref inteiro. Isso preserva a reatividade dos v-models aninhados
// (ex: currentAnamnesis.medical_history.hypertension) após fetchAnamneses.
const applyAnamnesisState = source => {
  const target = currentAnamnesis.value;
  const normalized = source
    ? normalizeAnamnesisFromServer(source)
    : EMPTY_ANAMNESIS();

  // campos escalares no root
  [
    'id',
    'specialty',
    'chief_complaint',
    'surgical_history',
    'family_history',
    'additional_notes',
    'status',
    'version_number',
    'finalized_at',
    'pdf_url',
    'updated_at',
  ].forEach(key => {
    target[key] = normalized[key] ?? (key === 'id' ? null : '');
  });

  // hashes aninhados — mutar in-place
  Object.keys(target.medical_history).forEach(key => {
    target.medical_history[key] = normalized.medical_history[key] ?? false;
  });
  Object.keys(normalized.medical_history).forEach(key => {
    target.medical_history[key] = normalized.medical_history[key];
  });

  Object.keys(target.relevant_habits).forEach(key => {
    target.relevant_habits[key] =
      normalized.relevant_habits[key] ?? target.relevant_habits[key];
  });

  target.pregnancy = { ...normalized.pregnancy };

  // arrays — substituir referência (Vue reage bem a substituição de array)
  target.allergies = Array.isArray(normalized.allergies)
    ? [...normalized.allergies]
    : [];
  target.current_medications = Array.isArray(normalized.current_medications)
    ? [...normalized.current_medications]
    : [];
  target.contraindications = Array.isArray(normalized.contraindications)
    ? [...normalized.contraindications]
    : [];
};

const startNewAnamnesis = () => {
  applyAnamnesisState(null);
};

const flushAllergyInput = () => {
  const value = allergyInput.value?.trim();
  if (!value) return;
  currentAnamnesis.value.allergies = [
    ...(currentAnamnesis.value.allergies || []),
    { name: value },
  ];
  allergyInput.value = '';
};

const flushMedicationInput = () => {
  const value = medicationInput.value?.trim();
  if (!value) return;
  currentAnamnesis.value.current_medications = [
    ...(currentAnamnesis.value.current_medications || []),
    { name: value },
  ];
  medicationInput.value = '';
};

const removeAllergy = idx => {
  if (currentAnamnesis.value.status === 'finalized') return;
  currentAnamnesis.value.allergies = (
    currentAnamnesis.value.allergies || []
  ).filter((_, i) => i !== idx);
};

const removeMedication = idx => {
  if (currentAnamnesis.value.status === 'finalized') return;
  currentAnamnesis.value.current_medications = (
    currentAnamnesis.value.current_medications || []
  ).filter((_, i) => i !== idx);
};

const fetchAnamneses = async () => {
  try {
    const response = await AnamnesisAPI.get(route.params.patientId);
    anamneses.value = response.data?.payload || response.data || [];
    applyAnamnesisState(anamneses.value[0] || null);
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error fetching anamneses', error);
    useAlert('Não foi possível carregar a anamnese.');
  }
};

const UNPERMITTED_ANAMNESIS_KEYS = [
  'id',
  'status',
  'version_number',
  'account_id',
  'patient_id',
  'professional_id',
  'finalized_at',
  'created_at',
  'updated_at',
  'pdf_url',
];

const saveAnamnesis = async (finalize = false) => {
  if (isSavingAnamnesis.value) return;
  try {
    isSavingAnamnesis.value = true;

    // flush inputs soltos antes de montar o payload
    flushAllergyInput();
    flushMedicationInput();

    const payload = deepCloneAnamnesis(currentAnamnesis.value);
    UNPERMITTED_ANAMNESIS_KEYS.forEach(key => delete payload[key]);

    let response;
    if (currentAnamnesis.value.id) {
      response = await AnamnesisAPI.update(
        route.params.patientId,
        currentAnamnesis.value.id,
        payload
      );
    } else {
      response = await AnamnesisAPI.create(route.params.patientId, payload);
    }

    const persisted = response.data?.payload || response.data;
    const savedId = persisted?.id || currentAnamnesis.value.id;

    if (finalize && savedId) {
      // ao finalizar, delegamos o sync do state apenas ao fetchAnamneses final
      // (evita duplo-sync reativo entre save → finalize).
      await AnamnesisAPI.finalize(route.params.patientId, savedId);
      await fetchAnamneses();
      useAlert('Anamnese assinada e finalizada com sucesso!');
    } else {
      if (persisted) {
        applyAnamnesisState(persisted);
      }
      useAlert('Anamnese salva como rascunho com sucesso!');
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error saving anamnesis', error);
    useAlert(error?.response?.data?.error || 'Erro ao salvar anamnese.');
  } finally {
    isSavingAnamnesis.value = false;
  }
};

onMounted(() => {
  fetchAnamneses();
});
</script>

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
        <span
          v-if="currentAnamnesis.updated_at"
          class="text-xs text-slate-500"
        >
          Última alteração: {{ formatDate(currentAnamnesis.updated_at) }}
        </span>

        <a
          v-if="currentAnamnesis.pdf_url"
          :href="currentAnamnesis.pdf_url"
          target="_blank"
          rel="noopener noreferrer"
          class="geral-header-btn"
        >
          <i class="i-lucide-file-text" /> Visualizar PDF
        </a>

        <button
          v-if="currentAnamnesis.status === 'finalized'"
          class="geral-header-btn"
          @click="startNewAnamnesis"
        >
          <i class="i-lucide-plus" /> Nova Anamnese
        </button>

        <button
          v-else
          class="geral-header-btn"
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
              <span class="check-item-label"
                >Hepatite / Doenças hepáticas</span
              >
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
                @blur="flushAllergyInput"
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
                  <button
                    v-if="currentAnamnesis.status !== 'finalized'"
                    type="button"
                    class="anm-tag-remove"
                    :aria-label="`Remover ${alg.name}`"
                    @click="removeAllergy(idx)"
                  >
                    <i class="i-lucide-x w-3 h-3" />
                  </button>
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
                @blur="flushMedicationInput"
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
                  <button
                    v-if="currentAnamnesis.status !== 'finalized'"
                    type="button"
                    class="anm-tag-remove"
                    :aria-label="`Remover ${med.name}`"
                    @click="removeMedication(idx)"
                  >
                    <i class="i-lucide-x w-3 h-3" />
                  </button>
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
                v-model="
                  currentAnamnesis.medical_history.has_anesthesia_complications
                "
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
            <label class="form-label"
              >Detalhes das Intervenções Recentes</label
            >
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
              <span class="reg-section-title"
                >Hábitos e Estilo de Vida</span
              >
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
                <option value="Atleta / Alta intensidade"
                  >Atleta / Alta intensidade</option
                >
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

<style scoped>
/* ── Grid de checkboxes (2 colunas para histórico de saúde) ── */
.anm-check-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0;
}

/* ── Coluna de checkboxes (1 coluna para cirúrgico) ── */
.anm-check-col {
  display: flex;
  flex-direction: column;
  gap: 0;
}

/* ── Tags de alergias / medicamentos ── */
.anm-tags-row {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 8px;
}

.anm-tag {
  display: inline-flex;
  align-items: center;
  font-size: 12px;
  font-weight: 500;
  padding: 2px 10px;
  border-radius: 99px;
  border: 1px solid transparent;
}

.anm-tag--red {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.2);
}
.anm-tag-remove {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  margin-left: 6px;
  padding: 0;
  width: 14px;
  height: 14px;
  border: none;
  background: transparent;
  color: currentColor;
  opacity: 0.6;
  cursor: pointer;
  border-radius: 3px;
  transition: opacity 0.15s, background 0.15s;
}
.anm-tag-remove:hover {
  opacity: 1;
  background: rgba(255, 255, 255, 0.08);
}

.anm-tag--blue {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}

/* ── Label de alerta (alergias) ── */
.anm-label-danger {
  display: flex;
  align-items: center;
  gap: 5px;
  color: #f87171;
  font-size: 13px;
  font-weight: 500;
  margin-bottom: 6px;
}

/* ── Input de alergias com borda vermelha sutil ── */
.anm-input-danger {
  border-color: rgba(239, 68, 68, 0.3) !important;
}
.anm-input-danger:focus {
  border-color: #ef4444 !important;
}

/* ── Card de observações confidenciais ── */
.anm-notes-card {
  background: rgba(251, 191, 36, 0.04);
  border: 1px solid rgba(251, 191, 36, 0.15);
  border-radius: 10px;
  padding: 16px;
}

.anm-notes-input {
  border-color: rgba(251, 191, 36, 0.2) !important;
}

.anm-notes-input:focus {
  border-color: rgba(251, 191, 36, 0.5) !important;
}
</style>
