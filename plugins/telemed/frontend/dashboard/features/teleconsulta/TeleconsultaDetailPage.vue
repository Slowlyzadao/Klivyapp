<script setup>
// Página de detalhe da teleconsulta finalizada (clínica).
// Layout em 2 colunas: gravação + transcrição + resumo (esquerda) e
// painel da evolução clínica IA (direita). Estilos em
// `@plugins/telemed/frontend/styles/teleconsulta-detail.scss`.
import '@plugins/telemed/frontend/styles/teleconsulta-detail.scss';

import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useRoute, useRouter, onBeforeRouteLeave } from 'vue-router';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import { teleconsultasApi } from '../../api/teleconsultas';
import TeleconsultaDetailHeader from './TeleconsultaDetailHeader.vue';
import TeleconsultaRecordingPlayer from './TeleconsultaRecordingPlayer.vue';
import TeleconsultaTranscript from './TeleconsultaTranscript.vue';
import TeleconsultaSummary from './TeleconsultaSummary.vue';
import TeleconsultaEvolutionEditor from './TeleconsultaEvolutionEditor.vue';
import TeleconsultaProcedureRegister from './TeleconsultaProcedureRegister.vue';

const route = useRoute();
const router = useRouter();
const detail = ref(null);
const isLoading = ref(true);
const error = ref(null);
const playerRef = ref(null);
const editorRef = ref(null);
// 2026-05-26 — Agora a edição vive no ProcedureRegister (bloco full-width
// abaixo do grid). O guard onBeforeRouteLeave consulta este ref.
const procedureRef = ref(null);

// 2026-05-25 — ponte player → transcrição. Atualizado pelo `@time-update`
// do TeleconsultaRecordingPlayer (~4 Hz, rate nativo do `timeupdate` do
// elemento <audio>). TeleconsultaTranscript usa pra destacar o segmento
// atual em modo "karaokê".
const playerCurrentTime = ref(0);

// AUDIT 2026-05-25 — sequencer anti-stale.
// ActionCable dispara `fetchDetail` em cada transição relevante
// (transcribed → ready). Requests podem retornar fora de ordem
// (ex.: ready respondido antes do transcribed em conexão lenta) e o
// segundo write sobrescreveria evolução já carregada com payload stale.
// `fetchSeq` incrementa a cada chamada; só aplica resultado se a geração
// continua sendo a mais recente quando a Promise resolve.
let fetchSeq = 0;

const eventId = computed(() => route.params.eventId);

const isRecordingReady = computed(() => {
  const status = detail.value?.recording?.status;
  return status === 'ready' || status === 'transcribed';
});

const recordingPending = computed(() => {
  const recording = detail.value?.recording;
  return recording && !isRecordingReady.value;
});

// 2026-05-22 — Antes a tela mostrava o enum cru ("Gravação em processamento
// (failed)…"), expondo o status em inglês no meio de uma frase PT-BR.
// Mapeia pros rótulos do usuário; default cai no próprio status (defesa
// se um dia o backend introduzir novo status sem atualizar o front).
const RECORDING_STATUS_LABELS = {
  pending: 'aguardando início',
  recording: 'gravando',
  uploaded: 'enviada, na fila de transcrição',
  transcribing: 'transcrevendo',
  transcribed: 'transcrição concluída',
  failed: 'falhou',
  ready: 'pronta',
};
const recordingStatusLabel = computed(() => {
  const status = detail.value?.recording?.status;
  return RECORDING_STATUS_LABELS[status] || status || '';
});

const fetchDetail = async () => {
  const mySeq = ++fetchSeq;
  isLoading.value = true;
  error.value = null;
  try {
    const { data } = await teleconsultasApi.show(eventId.value);
    if (mySeq !== fetchSeq) return; // outra chamada já tomou a frente
    detail.value = data.data;
  } catch (e) {
    if (mySeq !== fetchSeq) return;
    error.value = e?.response?.data?.error || e.message;
  } finally {
    if (mySeq === fetchSeq) isLoading.value = false;
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

// ─── Realtime: status do recording via ActionCable ───────────────────────
// Backend (`TelemedRecording#broadcast_status_change!`) emite no canal
// `account_<id>` em cada transição (pending → recording → uploaded →
// transcribing → transcribed → evolving → ready, ou failed). Sem este
// subscribe a UI ficava stale eternamente em "Gravação em processamento…"
// até o usuário dar F5. Audit Fase 1 — Tranche 5.
const onTelemedRecordingUpdated = payload => {
  // Só interessa o recording desta página. Mensagem de outras consultas é
  // ignorada — o connector global recebe tudo do account.
  if (!detail.value) return;
  if (String(payload.agenda_event_id) !== String(eventId.value)) return;

  // Hidrata recording inline (status, has_transcript, etc.). Para
  // transições terminais (`transcribed`, `ready`, `failed`) refetch
  // completo pra trazer segments/SOAP/evolution carregados pelo backend.
  const status = payload.status;
  if (detail.value.recording) {
    detail.value.recording.status = status;
    detail.value.recording.has_transcript = payload.has_transcript;
    detail.value.recording.has_audio = payload.has_audio;
  }

  if (status === 'transcribed' || status === 'ready' || status === 'failed') {
    fetchDetail();
  }
};

onMounted(() => {
  fetchDetail();
  emitter.on(BUS_EVENTS.TELEMED_RECORDING_UPDATED, onTelemedRecordingUpdated);
});

onBeforeUnmount(() => {
  emitter.off(BUS_EVENTS.TELEMED_RECORDING_UPDATED, onTelemedRecordingUpdated);
});

// Audit Fase 2 — pega navegação SPA pra dentro do dashboard (Voltar pra
// lista, ir pra outra teleconsulta, etc.). `beforeunload` no editor cobre
// fechar aba/refresh; este cobre rotas internas (browser nativo não
// dispara beforeunload em SPA navigation).
onBeforeRouteLeave(() => {
  const editorDirty    = editorRef.value?.hasUnsavedChanges?.value;
  const procedureDirty = procedureRef.value?.hasUnsavedChanges?.value;
  if (editorDirty || procedureDirty) {
    return window.confirm(
      'Você tem alterações não salvas na evolução. Sair mesmo assim?'
    );
  }
  return true;
});
</script>

<template>
  <div class="tcd-page">
    <button type="button" class="tcd-back" @click="goBack">
      <i class="i-lucide-arrow-left w-4 h-4" />
      <span>Voltar para a lista</span>
    </button>

    <!-- Skeleton (audit Fase 3): cabeçalho + 2 cards stub + painel
         lateral. Mantém o layout estável durante o fetch — quando
         `detail.value` chega, troca sem layout shift. -->
    <div v-if="isLoading" class="tcd-skeleton" aria-busy="true">
      <div class="tcd-skeleton__header">
        <div class="tcd-skeleton__line tcd-skeleton__line--title" />
        <div class="tcd-skeleton__line tcd-skeleton__line--subtitle" />
      </div>
      <div class="tcd-skeleton__grid">
        <div class="tcd-skeleton__col">
          <div class="tcd-skeleton__card" />
          <div class="tcd-skeleton__card" />
        </div>
        <div class="tcd-skeleton__col">
          <div class="tcd-skeleton__card tcd-skeleton__card--tall" />
        </div>
      </div>
    </div>
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
            @time-update="playerCurrentTime = $event"
          />
          <section v-else-if="recordingPending" class="tcd-card">
            <h3 class="tcd-card__title">
              <i class="i-lucide-audio-lines w-5 h-5 tcd-card__title-icon" />
              <span>Gravação da Consulta</span>
            </h3>
            <p class="tcd-summary__empty">
              Gravação em processamento ({{ recordingStatusLabel }})…
            </p>
          </section>

          <TeleconsultaTranscript
            :segments="detail.recording?.transcript_segments || []"
            :text="detail.recording?.transcript_text"
            :doctor-name="detail.professional?.name || 'Dr.'"
            :patient-name="detail.patient?.name || 'Paciente'"
            :current-time="playerCurrentTime"
            @segment-click="onSegmentClick"
          />

          <!-- 2026-05-22 — `summary` agora vem do Resumo Executivo dedicado
               do Claude (Markdown). Removido `fallback` pro raw_markdown:
               este duplicava o SOAP dos cards e era cortado por MAX_LEN. -->
          <TeleconsultaSummary
            :summary="detail.evolution?.summary || ''"
          />
        </div>

        <div class="tcd-col">
          <TeleconsultaEvolutionEditor
            v-if="detail.evolution"
            ref="editorRef"
            :evolution="detail.evolution"
          />
          <section v-else class="tcd-attention-panel" aria-label="Pontos de atenção">
            <header class="tcd-attention-panel__head">
              <h3 class="tcd-attention-panel__title">
                <i class="i-lucide-alert-triangle w-5 h-5 tcd-attention-panel__title-icon" />
                <span>Pontos de Atenção</span>
              </h3>
            </header>
            <p class="tcd-attention-panel__empty">
              Aguardando processamento da gravação para identificar pontos de atenção.
            </p>
          </section>
        </div>
      </div>

      <!-- Audit 2026-05-26 — bloco full-width abaixo do grid com o
           formulário de Registro de Procedimento (substitui os cards
           SOAP que ficavam na lateral direita). -->
      <TeleconsultaProcedureRegister
        v-if="detail.evolution"
        ref="procedureRef"
        :detail="detail"
        :evolution="detail.evolution"
        @saved="onEvolutionSaved"
        @approved="onEvolutionApproved"
        @rejected="onEvolutionRejected"
      />
    </template>
  </div>
</template>
