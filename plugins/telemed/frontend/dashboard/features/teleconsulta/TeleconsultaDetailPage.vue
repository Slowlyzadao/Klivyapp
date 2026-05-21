<script setup>
// Página de detalhe da teleconsulta finalizada (clínica).
// Layout em 2 colunas: gravação + transcrição + resumo (esquerda) e
// painel da evolução clínica IA (direita). Estilos em
// `@plugins/telemed/frontend/styles/teleconsulta-detail.scss`.
import '@plugins/telemed/frontend/styles/teleconsulta-detail.scss';

import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { teleconsultasApi } from '../../api/teleconsultas';
import TeleconsultaDetailHeader from './TeleconsultaDetailHeader.vue';
import TeleconsultaRecordingPlayer from './TeleconsultaRecordingPlayer.vue';
import TeleconsultaTranscript from './TeleconsultaTranscript.vue';
import TeleconsultaSummary from './TeleconsultaSummary.vue';
import TeleconsultaEvolutionEditor from './TeleconsultaEvolutionEditor.vue';

const route = useRoute();
const router = useRouter();
const detail = ref(null);
const isLoading = ref(true);
const error = ref(null);
const playerRef = ref(null);

const eventId = computed(() => route.params.eventId);

const isRecordingReady = computed(() => {
  const status = detail.value?.recording?.status;
  return status === 'ready' || status === 'transcribed';
});

const recordingPending = computed(() => {
  const recording = detail.value?.recording;
  return recording && !isRecordingReady.value;
});

const fetchDetail = async () => {
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await teleconsultasApi.show(eventId.value);
    detail.value = data.data;
  } catch (e) {
    error.value = e?.response?.data?.error || e.message;
  } finally {
    isLoading.value = false;
  }
};

const goBack = () => {
  router.push({ name: 'teleconsultas_index' });
};

const openPatientRecord = () => {
  const patientId = detail.value?.patient?.patient_id;
  if (!patientId) return;
  router.push({ name: 'patients_dashboard_record', params: { patientId } });
};

const onSegmentClick = segment => {
  playerRef.value?.seekTo?.(segment.start);
};

const onEvolutionSaved = updated => {
  if (detail.value) detail.value.evolution = updated;
};

const onEvolutionApproved = ({ evolution, clinical_note: clinicalNote }) => {
  if (detail.value) detail.value.evolution = evolution;
  window.alert(
    `Evolução aplicada ao prontuário (ClinicalNote #${clinicalNote.id}).`
  );
};

const onEvolutionRejected = updated => {
  if (detail.value) detail.value.evolution = updated;
};

onMounted(fetchDetail);
</script>

<template>
  <div class="tcd-page">
    <button type="button" class="tcd-back" @click="goBack">
      <i class="i-lucide-arrow-left w-4 h-4" />
      <span>Voltar para a lista</span>
    </button>

    <div v-if="isLoading" class="tcd-state">Carregando teleconsulta…</div>
    <div v-else-if="error" class="tcd-state tcd-state--error">Erro: {{ error }}</div>

    <template v-else-if="detail">
      <TeleconsultaDetailHeader
        :detail="detail"
        @open-record="openPatientRecord"
      />

      <div class="tcd-grid">
        <div class="tcd-col">
          <TeleconsultaRecordingPlayer
            v-if="isRecordingReady"
            ref="playerRef"
            :event-id="detail.id"
            :recording="detail.recording"
          />
          <section v-else-if="recordingPending" class="tcd-card">
            <h3 class="tcd-card__title">
              <i class="i-lucide-audio-lines w-5 h-5 tcd-card__title-icon" />
              <span>Gravação da Consulta</span>
            </h3>
            <p class="tcd-summary__empty">
              Gravação em processamento ({{ detail.recording.status }})…
            </p>
          </section>

          <TeleconsultaTranscript
            :segments="detail.recording?.transcript_segments || []"
            :text="detail.recording?.transcript_text"
            :doctor-name="detail.professional?.name || 'Dr.'"
            :patient-name="detail.patient?.name || 'Paciente'"
            @segment-click="onSegmentClick"
          />

          <TeleconsultaSummary
            :summary="detail.summary || ''"
            :fallback="detail.evolution?.raw_markdown || ''"
          />
        </div>

        <div class="tcd-col">
          <TeleconsultaEvolutionEditor
            v-if="detail.evolution"
            :evolution="detail.evolution"
            @saved="onEvolutionSaved"
            @approved="onEvolutionApproved"
            @rejected="onEvolutionRejected"
          />
          <section v-else class="tcd-evolution" aria-label="Evolução do paciente">
            <header class="tcd-evolution__head">
              <h3 class="tcd-evolution__title">
                <i class="i-lucide-sparkles w-5 h-5 tcd-evolution__title-icon" />
                <span>Evolução do Paciente</span>
              </h3>
            </header>
            <p class="tcd-summary__empty">
              Evolução ainda não gerada — aguardando processamento da gravação.
            </p>
          </section>
        </div>
      </div>
    </template>
  </div>
</template>
