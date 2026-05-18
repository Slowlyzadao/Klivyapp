<script setup>
import { computed } from 'vue';
import { useAudioRecorder } from '@plugins/internal_chat/frontend/composables/useAudioRecorder';

const emit = defineEmits(['ready', 'error']);

const {
  state,
  elapsed,
  error,
  blobUrl,
  start,
  stop,
  cancel,
  buildFile,
  reset,
} = useAudioRecorder();

const formatTime = computed(() => {
  const total = elapsed.value;
  const m = Math.floor(total / 60).toString().padStart(2, '0');
  const s = (total % 60).toString().padStart(2, '0');
  return `${m}:${s}`;
});

const startRecording = async () => {
  const ok = await start();
  if (!ok && error.value) emit('error', error.value);
};

const sendRecording = () => {
  const file = buildFile();
  if (file) emit('ready', file);
  reset();
};
</script>

<template>
  <!-- Idle: só o botão de microfone -->
  <button
    v-if="state === 'idle'"
    type="button"
    class="inline-flex items-center justify-center w-10 h-10 rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12 transition shrink-0"
    title="Gravar áudio"
    @click="startRecording"
  >
    <span class="i-lucide-mic text-lg" />
  </button>

  <!-- Gravando -->
  <div
    v-else-if="state === 'recording'"
    class="flex items-center gap-2 px-3 py-2 rounded-md bg-n-ruby-3 border border-n-ruby-7"
  >
    <span class="relative flex w-2.5 h-2.5">
      <span class="absolute inline-flex w-full h-full rounded-full opacity-75 animate-ping bg-n-ruby-9" />
      <span class="relative inline-flex w-2.5 h-2.5 rounded-full bg-n-ruby-10" />
    </span>
    <span class="text-sm font-medium tabular-nums text-n-ruby-11">
      Gravando {{ formatTime }}
    </span>
    <button
      type="button"
      class="ml-2 inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-alpha-2"
      title="Cancelar"
      @click="cancel"
    >
      <span class="i-lucide-x text-base" />
    </button>
    <button
      type="button"
      class="inline-flex items-center justify-center w-8 h-8 rounded-md bg-n-ruby-9 text-white hover:bg-n-ruby-10"
      title="Parar"
      @click="stop"
    >
      <span class="i-lucide-square text-sm" />
    </button>
  </div>

  <!-- Preview antes de enviar -->
  <div
    v-else-if="state === 'preview'"
    class="flex items-center gap-2 px-3 py-2 rounded-md bg-n-alpha-1 border border-n-weak"
  >
    <span class="i-lucide-mic text-base text-n-slate-11" />
    <audio :src="blobUrl" controls class="h-8" />
    <button
      type="button"
      class="inline-flex items-center justify-center w-8 h-8 rounded-md text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-ruby-11"
      title="Descartar"
      @click="cancel"
    >
      <span class="i-lucide-trash-2 text-base" />
    </button>
    <button
      type="button"
      class="inline-flex items-center justify-center w-8 h-8 rounded-md bg-n-brand text-white hover:brightness-110"
      title="Enviar áudio"
      @click="sendRecording"
    >
      <span class="i-lucide-send text-sm" />
    </button>
  </div>
</template>
