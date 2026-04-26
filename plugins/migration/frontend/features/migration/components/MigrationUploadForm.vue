<script setup>
import { ref, computed } from 'vue';
import { uploadCsv } from '../api/migrationApi.js';

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

const submitting = ref(false);
const errorMsg  = ref('');
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
}

async function submit() {
  errorMsg.value = '';
  successMsg.value = '';
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
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
    const run = await uploadCsv(args);
    successMsg.value = `Migração #${run.id} enfileirada — ${run.csv_filename}.`;
    file.value = null;
    patientsFile.value = null;
    patientAnamnesisFile.value = null;
    anamnesisFile.value = null;
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

    <div class="mig-actions">
      <button class="mig-btn mig-btn--primary" :disabled="!canSubmit" @click="submit">
        {{ submitting ? 'Enviando…' : 'Iniciar migração' }}
      </button>
    </div>
  </div>
</template>
