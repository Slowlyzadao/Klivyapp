import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue';

// Conta o tempo decorrido desde `startedAt` (ISO ou Date) em segundos,
// atualizando uma vez por segundo. Usado pelos cards "Ao vivo" da
// listagem de teleconsultas em andamento.
//
// Limpa o intervalo no unmount e quando o caller passa `startedAt = null`.
export function useLiveDuration(startedAt) {
  const now = ref(Date.now());
  let intervalId = null;

  const start = computed(() => {
    const value =
      typeof startedAt === 'function'
        ? startedAt()
        : (startedAt?.value ?? startedAt);
    if (!value) return null;
    const t = new Date(value).getTime();
    return Number.isNaN(t) ? null : t;
  });

  const seconds = computed(() => {
    if (!start.value) return 0;
    return Math.max(0, Math.floor((now.value - start.value) / 1000));
  });

  const tick = () => {
    now.value = Date.now();
  };

  const startTicking = () => {
    if (intervalId) return;
    tick();
    intervalId = setInterval(tick, 1000);
  };

  const stopTicking = () => {
    if (!intervalId) return;
    clearInterval(intervalId);
    intervalId = null;
  };

  onMounted(() => {
    if (start.value) startTicking();
  });
  onBeforeUnmount(stopTicking);

  watch(start, value => {
    if (value) startTicking();
    else stopTicking();
  });

  return { seconds };
}
