<script setup>
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import WaveSurfer from 'wavesurfer.js';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  src: { type: String, required: true },
  isOwn: { type: Boolean, default: false },
  sender: { type: Object, default: () => ({}) },
});

const containerRef = ref(null);
let ws = null;

const isPlaying = ref(false);
const isReady = ref(false);
const currentTime = ref(0);
const duration = ref(0);

const formatTime = secs => {
  const s = Math.max(0, Math.floor(secs || 0));
  const m = Math.floor(s / 60);
  return `${m}:${String(s % 60).padStart(2, '0')}`;
};

// Cores do waveform: tons que casam com a bolha verde clara (own) ou cinza (other).
const colors = computed(() =>
  props.isOwn
    ? { wave: '#1d8a52', progress: '#0f5132', cursor: 'rgba(0,0,0,0)' }
    : { wave: '#94a3b8', progress: '#475569', cursor: 'rgba(0,0,0,0)' }
);

const initWaveSurfer = () => {
  if (!containerRef.value) return;
  ws = WaveSurfer.create({
    container: containerRef.value,
    waveColor: colors.value.wave,
    progressColor: colors.value.progress,
    cursorColor: colors.value.cursor,
    height: 32,
    barWidth: 2,
    barGap: 2,
    barRadius: 2,
    normalize: true,
    interact: true,
    url: props.src,
    backend: 'WebAudio',
  });

  ws.on('ready', () => {
    isReady.value = true;
    duration.value = ws.getDuration();
  });
  ws.on('play', () => { isPlaying.value = true; });
  ws.on('pause', () => { isPlaying.value = false; });
  ws.on('finish', () => {
    isPlaying.value = false;
    currentTime.value = 0;
    ws.seekTo(0);
  });
  ws.on('audioprocess', () => {
    currentTime.value = ws.getCurrentTime();
  });
  ws.on('seeking', () => {
    currentTime.value = ws.getCurrentTime();
  });
};

onMounted(initWaveSurfer);

watch(
  () => props.src,
  url => {
    if (!ws) return;
    ws.load(url);
  }
);

onBeforeUnmount(() => {
  if (ws) {
    try { ws.destroy(); } catch { /* noop */ }
    ws = null;
  }
});

const toggle = () => {
  if (!ws) return;
  ws.playPause();
};

const displayTime = computed(() => {
  if (!isReady.value) return '...';
  if (isPlaying.value || currentTime.value > 0) {
    return formatTime(currentTime.value);
  }
  return formatTime(duration.value);
});
</script>

<template>
  <div
    class="flex flex-col px-2 py-2 rounded-2xl min-w-[260px] max-w-[320px]"
    :class="isOwn ? 'ic-audio-own' : 'ic-audio-other'"
  >
    <!-- Linha principal: avatar + play + waveform, todos vertically centered.
         Tempo vai numa segunda linha indentada pra alinhar com o waveform. -->
    <div class="flex items-center gap-3">
      <Avatar
        :name="sender.name || 'Áudio'"
        :src="sender.avatar_url || ''"
        :size="40"
        rounded-full
      />

      <button
        type="button"
        class="inline-flex items-center justify-center w-9 h-9 rounded-full shrink-0 transition disabled:opacity-50"
        :class="isOwn ? 'ic-audio-btn-own' : 'ic-audio-btn-other'"
        :disabled="!isReady"
        :title="isPlaying ? 'Pausar' : 'Tocar'"
        @click="toggle"
      >
        <span
          :class="isPlaying ? 'i-lucide-pause' : 'i-lucide-play'"
          class="text-base"
        />
      </button>

      <div ref="containerRef" class="flex-1 min-w-0" />
    </div>

    <p
      class="text-[10px] mt-1 tabular-nums pl-[100px]"
      :class="isOwn ? 'ic-own-muted' : 'text-n-slate-10'"
    >
      {{ displayTime }}
    </p>
  </div>
</template>

<style>
/* Áudio no chat — visual WhatsApp: avatar + play + waveform + tempo */
.ic-audio-own {
  background-color: rgba(15, 23, 42, 0.05);
}
.ic-audio-other {
  background-color: rgb(var(--n-alpha-1));
}
.ic-audio-btn-own {
  background-color: #1d8a52;
  color: #fff;
}
.ic-audio-btn-own:hover { filter: brightness(1.1); }
.ic-audio-btn-other {
  background-color: rgb(var(--n-slate-9) / 0.18);
  color: rgb(var(--n-slate-12));
}
.ic-audio-btn-other:hover {
  background-color: rgb(var(--n-slate-9) / 0.28);
}
.dark .ic-audio-own {
  background-color: rgba(255, 255, 255, 0.06);
}
.dark .ic-audio-btn-own {
  background-color: #6ee7b7;
  color: #052e1d;
}
</style>
