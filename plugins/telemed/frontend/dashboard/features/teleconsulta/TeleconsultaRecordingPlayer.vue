<script setup>
// Player de gravação (audio-only MVP) com controles custom.
// Recebe URL assinada via API; expõe `seekTo(seconds)` para os segmentos
// clicáveis da transcrição.
//
// 2026-05-25 (audit) — Reescrito pra resolver 3 bugs:
//   1. `seekTo` forçava `play()` em todo clique → após pulos repetidos o
//      audio element entrava em estado quebrado e o usuário precisava
//      recarregar a página pra voltar a tocar. Agora preserva o estado
//      (se estava pausado, continua pausado; só toca se já estava tocando).
//   2. Signed URL R2 expira em 5min. Após esse tempo, qualquer seek pra
//      ponto não bufferizado falha com NotSupportedError silencioso. Agora
//      escutamos `error`/`stalled` e refetchamos a URL automaticamente.
//   3. Faltavam controles: só play/mute. Adicionados volume slider e
//      velocidade (0.5x..2x).
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';
import { teleconsultasApi } from '../../api/teleconsultas';
import { formatClockSeconds } from './utils/formatters.js';

const props = defineProps({
  eventId: { type: [String, Number], required: true },
  recording: { type: Object, required: true },
});

// 2026-05-25 — emit `time-update` pra que o pai (DetailPage) propague o
// `currentTime` pra TeleconsultaTranscript e habilite o destaque "karaokê"
// do segmento sendo falado. Frequência ~4 Hz (rate nativo do timeupdate).
const emit = defineEmits(['time-update']);

const audioUrl = ref(null);
const audioRef = ref(null);
const isLoading = ref(true);
const error = ref(null);

const isPlaying = ref(false);
const currentTime = ref(0);
const duration = ref(0);
const isMuted = ref(false);
const volume = ref(1);
const playbackRate = ref(1);
// 2026-05-26 — volume estilo YouTube: slider inline expande no hover.
// Removido `showVolume` (popover) — click no ícone agora muta direto.
const showSpeed = ref(false);
const isRefetching = ref(false);

const SPEED_OPTIONS = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2];

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
  if (el.paused) {
    el.play().catch(err => handlePlayError(err));
  } else {
    el.pause();
  }
};

// Seeker robusto: clampa entre [0, totalSeconds], preserva estado play/pause.
// Antes forçava `play()` toda vez → quebrava audio element após N pulos.
const seekTo = seconds => {
  const el = audioRef.value;
  if (!el) return;
  const target = Math.max(0, Math.min(Number(seconds) || 0, totalSeconds.value || Infinity));
  const wasPlaying = !el.paused;
  try {
    el.currentTime = target;
  } catch (e) {
    // InvalidStateError: pode acontecer se metadata ainda não carregou.
    // Retry uma vez após 100ms.
    setTimeout(() => {
      if (audioRef.value) audioRef.value.currentTime = target;
    }, 100);
  }
  if (wasPlaying) {
    el.play().catch(err => handlePlayError(err));
  }
};

const handleBarClick = ev => {
  if (!totalSeconds.value) return;
  const rect = ev.currentTarget.getBoundingClientRect();
  const ratio = Math.min(1, Math.max(0, (ev.clientX - rect.left) / rect.width));
  seekTo(ratio * totalSeconds.value);
};

const toggleMute = () => {
  const el = audioRef.value;
  if (!el) return;
  el.muted = !el.muted;
  isMuted.value = el.muted;
};

const setVolume = ev => {
  const el = audioRef.value;
  if (!el) return;
  const v = Number(ev.target.value);
  el.volume = v;
  volume.value = v;
  if (v > 0 && el.muted) {
    el.muted = false;
    isMuted.value = false;
  }
};

const cycleSpeed = () => {
  const idx = SPEED_OPTIONS.indexOf(playbackRate.value);
  const next = SPEED_OPTIONS[(idx + 1) % SPEED_OPTIONS.length];
  setSpeed(next);
};

const setSpeed = rate => {
  const el = audioRef.value;
  if (!el) return;
  el.playbackRate = rate;
  playbackRate.value = rate;
  showSpeed.value = false;
};

// Refetch da signed URL e recarrega o elemento mantendo posição.
// Disparado por:
//   - error event (rede / 403 expirado)
//   - usuário clica em play após erro
async function refetchAndReload(targetSeconds = null) {
  if (isRefetching.value) return;
  isRefetching.value = true;
  const desiredTime = targetSeconds ?? currentTime.value;
  const wasPlaying = isPlaying.value;
  try {
    const { data } = await teleconsultasApi.recordingUrl(props.eventId, 'composite_audio');
    audioUrl.value = data.data.url;
    error.value = null;
    // Aguarda DOM atualizar com o novo src antes de seek/play.
    await new Promise(resolve => setTimeout(resolve, 50));
    const el = audioRef.value;
    if (el) {
      el.load();
      const onCanPlay = () => {
        el.removeEventListener('canplay', onCanPlay);
        try {
          el.currentTime = desiredTime;
        } catch (e) { /* ignora */ }
        if (wasPlaying) el.play().catch(() => {});
      };
      el.addEventListener('canplay', onCanPlay, { once: true });
    }
  } catch (e) {
    error.value = e?.response?.data?.error || e.message || 'Falha ao recarregar gravação';
  } finally {
    isRefetching.value = false;
  }
}

function handlePlayError(err) {
  // NotAllowedError: navegador bloqueou autoplay — usuário precisa interagir.
  // Aceitamos; toggle visual já reflete estado real.
  if (err?.name === 'NotAllowedError') return;
  // AbortError ou NotSupportedError: provavelmente signed URL expirou.
  refetchAndReload();
}

defineExpose({ seekTo });

// Handlers nomeados — guardamos as referências pra que `removeEventListener`
// no unmount/troca de ref consiga desregistrar (closures inline anônimas
// no addEventListener original eram inalcançáveis → leak acumulativo a cada
// revisita do detalhe).
const onAudioPlay     = () => (isPlaying.value = true);
const onAudioPause    = () => (isPlaying.value = false);
const onAudioEnded    = () => (isPlaying.value = false);
const onAudioTime     = () => {
  if (!audioRef.value) return;
  currentTime.value = audioRef.value.currentTime;
  emit('time-update', currentTime.value);
};
const onAudioMetadata = () => {
  if (audioRef.value) {
    duration.value = audioRef.value.duration || 0;
    audioRef.value.playbackRate = playbackRate.value;
    audioRef.value.volume = volume.value;
  }
};
const onAudioError = () => {
  // Signed URL R2 expira em 5min. Quando o browser tenta range request num
  // ponto não bufferizado e leva 403, dispara `error` no elemento. Refetch
  // automático preserva UX (player continua "vivo" sem reload).
  refetchAndReload();
};
const onAudioVolumeChange = () => {
  if (audioRef.value) {
    volume.value = audioRef.value.volume;
    isMuted.value = audioRef.value.muted;
  }
};
const AUDIO_EVENTS = [
  ['play', onAudioPlay],
  ['pause', onAudioPause],
  ['ended', onAudioEnded],
  ['timeupdate', onAudioTime],
  ['loadedmetadata', onAudioMetadata],
  ['error', onAudioError],
  ['volumechange', onAudioVolumeChange],
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

// Fecha popover de velocidade ao clicar fora. Volume não tem mais
// popover (slider inline expande no hover, sem estado controlado).
const onDocumentClick = ev => {
  if (!ev.target.closest('.tcd-audio__speed-wrap')) showSpeed.value = false;
};

onBeforeUnmount(() => {
  if (audioRef.value) unbindAudioListeners(audioRef.value);
  document.removeEventListener('click', onDocumentClick);
});

onMounted(async () => {
  document.addEventListener('click', onDocumentClick);
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
      <button type="button" class="tcd-audio__retry" @click="refetchAndReload(0)">
        Tentar de novo
      </button>
    </div>
    <div v-else-if="audioUrl" class="tcd-audio">
      <button
        type="button"
        class="tcd-audio__play"
        :aria-label="isPlaying ? 'Pausar' : 'Reproduzir'"
        :disabled="isRefetching"
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

      <!-- Velocidade — botão ciclico ou popover com opções -->
      <div class="tcd-audio__speed-wrap">
        <button
          type="button"
          class="tcd-audio__speed"
          :aria-label="`Velocidade ${playbackRate}x`"
          :aria-expanded="showSpeed"
          @click.stop="showSpeed = !showSpeed"
        >
          {{ playbackRate }}x
        </button>
        <div v-if="showSpeed" class="tcd-audio__speed-menu" role="menu">
          <button
            v-for="rate in SPEED_OPTIONS"
            :key="rate"
            type="button"
            role="menuitem"
            :class="['tcd-audio__speed-item', { 'is-active': rate === playbackRate }]"
            @click="setSpeed(rate)"
          >
            {{ rate }}x
          </button>
        </div>
      </div>

      <!-- Volume estilo YouTube: ícone + slider horizontal inline.
           - Hover no wrap → slider expande à direita (0 → 70px).
           - Click no ícone → muta/desmuta direto (sem popover).
           - Click+drag no slider → ajusta volume; se acima de 0 com
             áudio mutado, desmuta automaticamente. -->
      <div class="tcd-audio__volume-wrap">
        <button
          type="button"
          class="tcd-audio__volume"
          :aria-label="isMuted ? 'Ativar som' : 'Mutar'"
          @click="toggleMute"
        >
          <i
            :class="[
              isMuted || volume === 0 ? 'i-lucide-volume-x' :
              volume < 0.5 ? 'i-lucide-volume-1' : 'i-lucide-volume-2',
              'w-5 h-5'
            ]"
          />
        </button>
        <input
          type="range"
          min="0"
          max="1"
          step="0.05"
          :value="isMuted ? 0 : volume"
          class="tcd-audio__volume-slider"
          aria-label="Volume"
          @input="setVolume"
        />
      </div>

      <!-- preload=auto pra bufferizar pulos longos sem range-request mid-seek
           (causa do bug "áudio trava após pular várias vezes"). Custo:
           download upfront do arquivo inteiro (~28MB/hora — aceitável). -->
      <audio ref="audioRef" preload="auto" :src="audioUrl" class="sr-only" />
    </div>
    <div v-else class="tcd-audio">
      <span class="tcd-audio__state tcd-audio__state--error">
        Gravação não disponível.
      </span>
    </div>
  </section>
</template>
