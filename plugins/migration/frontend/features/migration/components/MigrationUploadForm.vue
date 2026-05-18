<script setup>
import { ref, computed } from 'vue';
import { uploadCsv, previewCsv } from '../api/migrationApi.js';

const props = defineProps({
  accounts: { type: Array, required: true },
});
const emit = defineEmits(['runCreated']);

const accountId = ref(null);
const kind      = ref('patients');
const source    = ref('clinicorp');

// Single-file flow (agenda etc)
const file      = ref(null);

// Multi-file flow (patients): Patient.csv + PatientAnamnesis.csv + Anamnesis.csv
const patientsFile         = ref(null);
const patientAnamnesisFile = ref(null);
const anamnesisFile        = ref(null);

const previewing = ref(false);
const submitting = ref(false);
const preview    = ref(null); // { summary, rows, warnings, anamneses? }
const errorMsg   = ref('');
const successMsg = ref('');

const KINDS = [
  { value: 'patients',  label: 'Pacientes (+ anamnese opcional)' },
  { value: 'agenda',    label: 'Agenda (eventos / appointments)' },
  { value: 'financial', label: 'Financeiro (em breve)', disabled: true },
];

const SOURCES = [
  { value: 'clinicorp', label: 'Clinicorp (CSV)' },
  { value: 'generic',   label: 'Genérico (CSV padrão Klivy)', disabled: true },
];

const isPatients = computed(() => kind.value === 'patients');

const canPreview = computed(() => {
  if (!accountId.value || !kind.value || previewing.value || submitting.value) return false;
  if (!isPatients.value) return false; // preview only implemented for patients
  return !!patientsFile.value;
});

const canSubmit = computed(() => {
  if (!accountId.value || !kind.value || submitting.value) return false;
  if (isPatients.value) return !!patientsFile.value;
  return !!file.value;
});

function pickFile(e, slot) {
  const f = e.target.files?.[0];
  if (!f) return;
  if (slot === 'file') file.value = f;
  else if (slot === 'patients') patientsFile.value = f;
  else if (slot === 'patientAnamnesis') patientAnamnesisFile.value = f;
  else if (slot === 'anamnesis') anamnesisFile.value = f;
  // Any file change invalidates a previously-computed preview
  preview.value = null;
}

function buildArgs() {
  const args = { accountId: accountId.value, kind: kind.value, source: source.value };
  if (isPatients.value) {
    args.files = {
      patients: patientsFile.value,
      patientAnamnesis: patientAnamnesisFile.value,
      anamnesis: anamnesisFile.value,
    };
  } else {
    args.file = file.value;
  }
  return args;
}

async function runPreview() {
  errorMsg.value = '';
  successMsg.value = '';
  preview.value = null;
  if (!canPreview.value) return;
  previewing.value = true;
  try {
    preview.value = await previewCsv(buildArgs());
  } catch (err) {
    errorMsg.value = err.message || 'Falha ao gerar pré-visualização.';
  } finally {
    previewing.value = false;
  }
}

async function submit() {
  errorMsg.value = '';
  successMsg.value = '';
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
    const run = await uploadCsv(buildArgs());
    successMsg.value = `Migração #${run.id} enfileirada — ${run.csv_filename}.`;
    file.value = null;
    patientsFile.value = null;
    patientAnamnesisFile.value = null;
    anamnesisFile.value = null;
    preview.value = null;
    emit('runCreated', run);
  } catch (err) {
    errorMsg.value = err.message || 'Falha ao enviar planilha.';
  } finally {
    submitting.value = false;
  }
}

function fmtSize(f) {
  return f ? `${f.name} · ${(f.size / 1024).toFixed(1)} KB` : '';
}

const ACTION_LABEL = {
  create: 'Criar',
  update: 'Atualizar',
  skip:   'Pular',
  error:  'Erro',
};
</script>

<template>
  <div class="mig-card">
    <h2 style="font-size: 16px; font-weight: 700; margin: 0 0 16px;">Nova migração</h2>

    <div class="mig-grid">
      <div>
        <label class="mig-label">Conta de destino</label>
        <select v-model="accountId" class="mig-select">
          <option :value="null">Selecione a conta…</option>
          <option v-for="a in accounts" :key="a.id" :value="a.id">
            #{{ a.id }} — {{ a.name }}
          </option>
        </select>
        <div class="mig-help">A planilha será importada para a conta selecionada (account_id).</div>
      </div>

      <div>
        <label class="mig-label">Tipo de migração</label>
        <select v-model="kind" class="mig-select">
          <option v-for="k in KINDS" :key="k.value" :value="k.value" :disabled="k.disabled">
            {{ k.label }}
          </option>
        </select>
        <div class="mig-help">Em "Pacientes" você pode anexar também os 2 CSVs de anamnese.</div>
      </div>

      <div>
        <label class="mig-label">Origem</label>
        <select v-model="source" class="mig-select">
          <option v-for="s in SOURCES" :key="s.value" :value="s.value" :disabled="s.disabled">
            {{ s.label }}
          </option>
        </select>
        <div class="mig-help">Define o parser do CSV (mapeamento de colunas).</div>
      </div>

      <!-- Multi-file: Patients flow -->
      <template v-if="isPatients">
        <div>
          <label class="mig-label">Patient.csv (obrigatório)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">📄</div>
            <div class="mig-drop__text">{{ patientsFile ? fmtSize(patientsFile) : 'Selecione Patient.csv' }}</div>
            <input type="file" accept=".csv,text/csv" style="display: none;" @change="(e) => pickFile(e, 'patients')" />
          </label>
        </div>
        <div>
          <label class="mig-label">PatientAnamnesis.csv (opcional)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">🧾</div>
            <div class="mig-drop__text">{{ patientAnamnesisFile ? fmtSize(patientAnamnesisFile) : 'Selecione PatientAnamnesis.csv' }}</div>
            <input type="file" accept=".csv,text/csv" style="display: none;" @change="(e) => pickFile(e, 'patientAnamnesis')" />
          </label>
        </div>
        <div>
          <label class="mig-label">Anamnesis.csv (opcional)</label>
          <label class="mig-drop mig-drop--small">
            <div class="mig-drop__icon">📋</div>
            <div class="mig-drop__text">{{ anamnesisFile ? fmtSize(anamnesisFile) : 'Selecione Anamnesis.csv' }}</div>
            <input type="file" accept=".csv,text/csv" style="display: none;" @change="(e) => pickFile(e, 'anamnesis')" />
          </label>
        </div>
      </template>

      <!-- Single-file: legacy flow (agenda, etc) -->
      <div v-else>
        <label class="mig-label">Arquivo CSV</label>
        <label class="mig-drop">
          <div class="mig-drop__icon">📄</div>
          <div class="mig-drop__text">{{ file ? fmtSize(file) : 'Clique para selecionar o CSV' }}</div>
          <div class="mig-drop__hint">Suporta até 25MB · ~10.000 linhas</div>
          <input type="file" accept=".csv,text/csv" style="display: none;" @change="(e) => pickFile(e, 'file')" />
        </label>
      </div>
    </div>

    <div v-if="errorMsg" class="mig-error">{{ errorMsg }}</div>
    <div v-if="successMsg" class="mig-success">{{ successMsg }}</div>

    <div v-if="preview" class="mig-preview">
      <h3 style="font-size: 13px; font-weight: 700; margin: 16px 0 8px; color: #374151;">
        Pré-visualização — nada foi gravado ainda
      </h3>
      <div class="mig-preview__summary">
        <span class="mig-preview__chip">Total: {{ preview.summary.total }}</span>
        <span class="mig-preview__chip mig-preview__chip--create">Criar: {{ preview.summary.would_create }}</span>
        <span class="mig-preview__chip mig-preview__chip--update">Atualizar: {{ preview.summary.would_update }}</span>
        <span class="mig-preview__chip mig-preview__chip--skip">Pular: {{ preview.summary.would_skip }}</span>
        <span v-if="preview.summary.warnings" class="mig-preview__chip mig-preview__chip--warn">
          Avisos: {{ preview.summary.warnings }}
        </span>
        <span v-if="preview.summary.errors" class="mig-preview__chip mig-preview__chip--err">
          Linhas inválidas: {{ preview.summary.errors }}
        </span>
      </div>

      <div v-if="preview.anamneses" class="mig-help" style="margin-bottom: 8px;">
        Anamneses: {{ preview.anamneses.total }} no CSV ·
        {{ preview.anamneses.linked }} serão vinculadas ·
        {{ preview.anamneses.unlinked }} sem vínculo (ID truncado pelo Excel).
      </div>

      <div class="mig-preview__rows">
        <div v-for="(row, idx) in preview.rows" :key="idx" class="mig-preview__row">
          <span :class="['mig-preview__action', `mig-preview__action--${row.action}`]">
            {{ ACTION_LABEL[row.action] || row.action }}
          </span>
          <div>
            <div class="mig-preview__row-name">
              {{ row.name || '(sem nome)' }}
              <span v-if="row.cpf" style="color:#6b7280; font-weight:400;"> · CPF {{ row.cpf }}</span>
            </div>
            <div class="mig-preview__row-meta">
              Linha {{ row.line }}
              <span v-if="row.fields.email"> · {{ row.fields.email }}</span>
              <span v-if="row.fields.phone"> · {{ row.fields.phone }}</span>
              <span v-if="row.fields.city"> · {{ row.fields.city }}</span>
              <span v-if="row.fields.insurance_plan"> · plano: {{ row.fields.insurance_plan }}</span>
            </div>
            <div v-if="row.fields.notes_preview" class="mig-preview__row-meta">
              📝 {{ row.fields.notes_preview }}
            </div>
            <div v-if="row.reason" class="mig-preview__row-reason">{{ row.reason }}</div>
          </div>
        </div>
      </div>

      <div v-if="preview.warnings && preview.warnings.length" style="margin-top: 12px;">
        <h4 style="font-size: 12px; font-weight: 600; margin: 0 0 6px; color: #78350f;">
          Avisos ({{ preview.warnings.length }})
        </h4>
        <div class="mig-error-list">
          <div v-for="(w, idx) in preview.warnings" :key="idx" class="mig-error-list__item mig-error-list__item--warning">
            <strong>Linha {{ w.line }}:</strong> {{ w.message }}
          </div>
        </div>
      </div>
    </div>

    <div class="mig-actions">
      <button v-if="isPatients" class="mig-btn mig-btn--ghost" :disabled="!canPreview" @click="runPreview">
        {{ previewing ? 'Analisando…' : (preview ? 'Regerar pré-visualização' : 'Pré-visualizar') }}
      </button>
      <button class="mig-btn mig-btn--primary" :disabled="!canSubmit" @click="submit">
        {{ submitting ? 'Enviando…' : (preview ? 'Confirmar e iniciar' : 'Iniciar migração') }}
      </button>
    </div>
  </div>
</template>
