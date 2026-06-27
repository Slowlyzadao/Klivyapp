/**
 * useProgressiveList — renderização progressiva de listas longas via
 * IntersectionObserver.
 *
 * Recebe uma `Ref<Array>` da lista completa (já filtrada/ordenada) e
 * expõe `visibleItems` (slice dos primeiros N) + `sentinelRef` para
 * colocar no template logo após a lista. Quando o sentinel entra na
 * viewport, mais um batch é renderizado.
 *
 * Por que IntersectionObserver e não virtual scrolling:
 *   - Itens dessas abas (timeline/agenda) têm alturas variáveis (cards
 *     com metadata em múltiplas linhas, alguns sem). Virtual scrolling
 *     puro requer alturas fixas ou estimadas.
 *   - 100-500 nodes DOM montados após scrolls é aceitável (cards são
 *     leves, sem listeners custosos). Casos extremos (>2k itens) seriam
 *     raros; aí vale revisitar.
 *   - Sem dependência externa. Vanilla browser API.
 *
 * Uso típico:
 *   const list = computed(() => filteredAppointments.value);
 *   const { visibleItems, sentinelRef, hasMore } =
 *     useProgressiveList(list, { initialCount: 30, batchSize: 30 });
 *
 *   <AppointmentCard v-for="apt in visibleItems" :key="apt.id" :appointment="apt" />
 *   <div v-if="hasMore" ref="sentinelRef" class="sentinel" />
 */
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue';

export function useProgressiveList(sourceListRef, options = {}) {
  const initialCount = options.initialCount ?? 30;
  const batchSize    = options.batchSize    ?? 30;
  // `rootMargin` antecipa o carregamento: dispara N px antes do sentinel
  // entrar realmente na viewport — evita "flash" de tela em branco.
  const rootMargin   = options.rootMargin   ?? '200px';

  const visibleCount = ref(initialCount);
  const sentinelRef  = ref(null);

  const visibleItems = computed(() =>
    (sourceListRef.value || []).slice(0, visibleCount.value)
  );

  const totalCount = computed(() => (sourceListRef.value || []).length);
  const hasMore    = computed(() => visibleCount.value < totalCount.value);

  // Reseta o contador sempre que a fonte muda (filtro, ordenação, nova
  // página) — assim o scroll volta ao topo lógico em vez de manter um
  // visibleCount inflado de uma lista anterior.
  watch(
    () => totalCount.value,
    () => {
      visibleCount.value = initialCount;
    }
  );

  let observer = null;

  const setupObserver = () => {
    if (observer) {
      observer.disconnect();
      observer = null;
    }
    if (!sentinelRef.value || !hasMore.value) return;

    observer = new IntersectionObserver(
      entries => {
        entries.forEach(entry => {
          if (entry.isIntersecting && hasMore.value) {
            visibleCount.value = Math.min(
              visibleCount.value + batchSize,
              totalCount.value
            );
          }
        });
      },
      { rootMargin }
    );
    observer.observe(sentinelRef.value);
  };

  // Re-arma o observer quando o sentinel aparece/desaparece (toggle de
  // `hasMore`) ou quando o ref do DOM muda. Vue troca o node entre os
  // estados; sem re-arming o observer fica preso ao node antigo.
  watch([sentinelRef, hasMore], () => setupObserver(), { flush: 'post' });

  onMounted(setupObserver);
  onBeforeUnmount(() => {
    if (observer) observer.disconnect();
    observer = null;
  });

  return {
    visibleItems,
    visibleCount,
    totalCount,
    hasMore,
    sentinelRef,
  };
}
