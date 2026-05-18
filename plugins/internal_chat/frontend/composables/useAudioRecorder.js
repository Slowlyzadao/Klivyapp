import { onBeforeUnmount, ref } from 'vue';

// Detecta o melhor mimeType disponível no navegador. Safari só aceita
// audio/mp4, Chrome/Firefox preferem webm/opus.
const pickMimeType = () => {
  const candidates = [
    'audio/webm;codecs=opus',
    'audio/webm',
    'audio/mp4',
    'audio/ogg;codecs=opus',
  ];
  if (typeof MediaRecorder === 'undefined') return null;
  return candidates.find(t => MediaRecorder.isTypeSupported(t)) || '';
};

export function useAudioRecorder() {
  const state = ref('idle'); // idle | recording | preview
  const elapsed = ref(0); // segundos
  const error = ref('');
  const blob = ref(null);
  const blobUrl = ref('');

  let stream = null;
  let recorder = null;
  let chunks = [];
  let timerId = null;
  let startedAt = 0;

  const cleanup = () => {
    if (timerId) clearInterval(timerId);
    timerId = null;
    if (stream) {
      stream.getTracks().forEach(t => t.stop());
      stream = null;
    }
    recorder = null;
    chunks = [];
  };

  const reset = () => {
    if (blobUrl.value) URL.revokeObjectURL(blobUrl.value);
    blob.value = null;
    blobUrl.value = '';
    elapsed.value = 0;
    error.value = '';
    state.value = 'idle';
  };

  const start = async () => {
    error.value = '';
    if (typeof navigator?.mediaDevices?.getUserMedia !== 'function') {
      error.value = 'Gravação de áudio não suportada neste navegador';
      return false;
    }
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    } catch (e) {
      error.value =
        e.name === 'NotAllowedError'
          ? 'Permissão de microfone negada'
          : 'Não foi possível acessar o microfone';
      return false;
    }

    const mimeType = pickMimeType();
    try {
      recorder = mimeType
        ? new MediaRecorder(stream, { mimeType })
        : new MediaRecorder(stream);
    } catch (e) {
      cleanup();
      error.value = 'MediaRecorder indisponível';
      return false;
    }

    chunks = [];
    recorder.ondataavailable = e => {
      if (e.data && e.data.size > 0) chunks.push(e.data);
    };
    recorder.onstop = () => {
      const type = recorder?.mimeType || 'audio/webm';
      const finalBlob = new Blob(chunks, { type });
      blob.value = finalBlob;
      blobUrl.value = URL.createObjectURL(finalBlob);
      state.value = 'preview';
      cleanup();
    };

    recorder.start();
    startedAt = Date.now();
    elapsed.value = 0;
    timerId = setInterval(() => {
      elapsed.value = Math.floor((Date.now() - startedAt) / 1000);
      // Limite de 5 minutos para evitar arquivos enormes
      if (elapsed.value >= 300) stop();
    }, 200);
    state.value = 'recording';
    return true;
  };

  const stop = () => {
    if (state.value !== 'recording') return;
    try {
      recorder?.stop();
    } catch (e) {
      cleanup();
      reset();
    }
  };

  const cancel = () => {
    if (state.value === 'recording') {
      try {
        recorder?.stop();
      } catch (e) {
        // ignore
      }
    }
    cleanup();
    reset();
  };

  const buildFile = () => {
    if (!blob.value) return null;
    const ext = (blob.value.type.includes('mp4') && 'm4a') ||
                (blob.value.type.includes('ogg') && 'ogg') ||
                'webm';
    return new File([blob.value], `audio-${Date.now()}.${ext}`, {
      type: blob.value.type,
    });
  };

  onBeforeUnmount(cancel);

  return {
    state,
    elapsed,
    error,
    blob,
    blobUrl,
    start,
    stop,
    cancel,
    reset,
    buildFile,
  };
}
