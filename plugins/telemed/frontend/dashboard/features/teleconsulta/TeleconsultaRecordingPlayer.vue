<script setup>
// Player de gravação (audio-only MVP) com controles custom.
// Recebe URL assinada via API; expõe `seekTo(seconds)` para os segmentos
// clicáveis da transcrição. Sem CSS interno: estilos vivem no SCSS.
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { teleconsultasApi } from '../../api/teleconsultas';
import { formatClockSeconds } from './utils/formatters.js';

const props = defineProps({
  eventId: { type: [String, Number], required: true },
  recording: { type: Object, required: true },
});

const audioUrl = ref(null);
const audioRef = ref(null);
const isLoading = ref(true);
const error = ref(null);

const isPlaying = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const isMuted = ref(false);

const totalSeconds = computed(() => {
  // `duration` do elemento <audio> só fica disponível após metadata; até lá
  // caímos no `duration_seconds` que veio do backend (mais confiável que 0).
  if (duration.value > 0) return duration.value;
  return Number(props.recording?.duration_seconds) || 0;
});

const progressPct = computed(() => {
  if (!totalSeconds.value) return 0;
  return Math.min(100, (currentTime.value / totalSeconds.value) * 100);
});

const currentLabel = computed(() => formatClockSeconds(currentTime.value));
const totalLabel = computed(() => formatClockSeconds(totalSeconds.value));

const togglePlay = () => {
  const el = audioRef.value;
  if (!el) return;
  if (el.paused) el.play().catch(() => {});
  else el.pause();
};

const seekTo = seconds => {
  const el = audioRef.value;
  if (!el) return;
  el.currentTime = Number(seconds) || 0;
  el.play?.().catch(() => {});
};

const handleBarClick = ev => {
  const el = audioRef.value;
  if (!el || !totalSeconds.value) return;
  const rect = ev.currentTarget.getBoundingClientRect();
  const ratio = Math.min(1, Math.max(0, (ev.clientX - rect.left) / rect.width));
  el.currentTime = ratio * totalSeconds.value;
};

const toggleMute = () => {
  const el = audioRef.value;
  if (!el) return;
  el.muted = !el.muted;
  isMuted.value = el.muted;
};

defineExpose({ seekTo });

// Handlers nomeados — guardamos as referências pra que `removeEventListener`
// no unmount/troca de ref consiga desregistrar (closures inline anônimas
// no addEventListener original eram inalcançáveis → leak acumulativo a cada
// revisita do detalhe).
const onAudioPlay     = () => (isPlaying.value = true);
const onAudioPause    = () => (isPlaying.value = false);
const onAudioEnded    = () => (isPlaying.value = false);
const onAudioTime     = () => {
  if (audioRef.value) currentTime.value = audioRef.value.currentTime;
};
const onAudioMetadata = () => {
  if (audioRef.value) duration.value = audioRef.value.duration || 0;
};
const AUDIO_EVENTS = [
  ['play', onAudioPlay],
  ['pause', onAudioPause],
  ['ended', onAudioEnded],
  ['timeupdate', onAudioTime],
  ['loadedmetadata', onAudioMetadata],
];

function bindAudioListeners(el) {
  AUDIO_EVENTS.forEach(([ev, fn]) => el.addEventListener(ev, fn));
}
function unbindAudioListeners(el) {
  AUDIO_EVENTS.forEach(([ev, fn]) => el.removeEventListener(ev, fn));
}

watch(audioRef, (el, oldEl) => {
  if (oldEl) unbindAudioListeners(oldEl);
  if (el) bindAudioListeners(el);
});

onBeforeUnmount(() => {
  if (audioRef.value) unbindAudioListeners(audioRef.value);
});

onMounted(async () => {
  try {
    const { data } = await teleconsultasApi.recordingUrl(props.eventId, 'composite_audio');
    audioUrl.value = data.data.url;
  } catch (e) {
    error.value = e?.response?.data?.error || e.message || 'Não foi possível carregar a gravação';
  } finally {
    isLoading.value = false;
  }
});
</script>

<template>
  <section class="tcd-card">
    <h3 class="tcd-card__title">
      <i class="i-lucide-audio-lines w-5 h-5 tcd-card__title-icon" />
      <span>Gravação da Consulta</span>
    </h3>

    <div v-if="isLoading" class="tcd-audio">
      <span class="tcd-audio__state">Carregando gravação…</span>
    </div>
    <div v-else-if="error" class="tcd-audio">
      <span class="tcd-audio__state tcd-audio__state--error">{{ error }}</span>
    </div>
    <div v-else-if="audioUrl" class="tcd-audio">
      <button
        type="button"
        class="tcd-audio__play"
        :aria-label="isPlaying ? 'Pausar' : 'Reproduzir'"
        @click="togglePlay"
      >
        <i :class="[isPlaying ? 'i-lucide-pause' : 'i-lucide-play', 'w-5 h-5']" />
      </button>

      <span class="tcd-audio__time">{{ currentLabel }}</span>

      <div
        class="tcd-audio__bar"
        role="slider"
        :aria-valuemin="0"
        :aria-valuemax="Math.round(totalSeconds)"
        :aria-valuenow="Math.round(currentTime)"
        @click="handleBarClick"
      >
        <div class="tcd-audio__bar-fill" :style="{ width: `${progressPct}%` }" />
      </div>

      <span class="tcd-audio__time tcd-audio__time--end">{{ totalLabel }}</span>

      <button
        type="button"
        class="tcd-audio__volume"
        :aria-label="isMuted ? 'Ativar som' : 'Silenciar'"
        @click="toggleMute"
      >
        <i :class="[isMuted ? 'i-lucide-volume-x' : 'i-lucide-volume-2', 'w-5 h-5']" />
      </button>

      <audio ref="audioRef" preload="metadata" :src="audioUrl" class="sr-only" />
    </div>
    <div v-else class="tcd-audio">
      <span class="tcd-audio__state tcd-audio__state--error">
        Gravação não disponível.
      </span>
    </div>
  </section>
</template>
