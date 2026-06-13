<script setup>
/**
 * TimelineTab — Aba "Timeline" do prontuário do paciente.
 *
 * Orquestrador. Composição:
 *   • useTimeline — fetch read-only de eventos consolidados
 *   • timeline-tab/* (3 sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota.
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { useTimeline } from '@plugins/patients/frontend/features/patient-record/composables/useTimeline';
import { useProgressiveList } from '@plugins/patients/frontend/features/patient-record/composables/useProgressiveList';
import {
  BRT,
  matchesFilter,
} from '@plugins/patients/frontend/constants/timeline';
import TimelineHeader from '@plugins/patients/frontend/features/patient-record/components/timeline-tab/TimelineHeader.vue';
import TimelineFilters from '@plugins/patients/frontend/features/patient-record/components/timeline-tab/TimelineFilters.vue';
import TimelineEventCard from '@plugins/patients/frontend/features/patient-record/components/timeline-tab/TimelineEventCard.vue';

const { t } = useI18n();
const route = useRoute();
const patientId = computed(() => route.params.patientId);

const { events, isLoading, fetch: fetchTimeline } = useTimeline(patientId);

const filter = ref('all');
const sortOrder = ref('newest'); // 'newest' | 'oldest'

const filteredEvents = computed(() => {
  const list = events.value.filter(e => matchesFilter(e, filter.value));
  return [...list].sort((a, b) => {
    const da = new Date(a.occurred_at || 0);
    const db = new Date(b.occurred_at || 0);
    return sortOrder.value === 'oldest' ? da - db : db - da;
  });
});

// Auditoria UX 2026-05-15: carregamento progressivo. A lista de eventos
// pode ter centenas de entradas em pacientes antigos (cada consulta gera
// 3-5 eventos: criado, confirmado, atendido, anamnese, plano…). Renderiza
// primeiros 30 e carrega mais 30 por scroll via IntersectionObserver.
const {
  visibleItems: visibleEvents,
  hasMore: hasMoreEvents,
  sentinelRef: timelineSentinel,
} = useProgressiveList(filteredEvents, { initialCount: 30, batchSize: 30 });

// Agrupa por data formatada (pt-BR full). Re-agrupa só o slice visível —
// assim a estrutura de "divisores de data" sempre reflete o que está
// montado no DOM.
const groupedEvents = computed(() => {
  const groups = {};
  visibleEvents.value.forEach(event => {
    const date = event.occurred_at
      ? new Date(event.occurred_at).toLocaleDateString('pt-BR', {
          year: 'numeric',
          month: 'long',
          day: 'numeric',
          timeZone: BRT,
        })
      : t('PATIENT_TIMELINE.EMPTY.NO_DATE');
    if (!groups[date]) groups[date] = [];
    groups[date].push(event);
  });
  return Object.entries(groups).map(([date, list]) => ({ date, events: list }));
});

onMounted(fetchTimeline);
</script>

<template>
  <div class="tab-pane fade-in">
    <TimelineHeader
      :event-count="filteredEvents.length"
      :sort-order="sortOrder"
      @update:sort-order="sortOrder = $event"
    />

    <TimelineFilters
      :active="filter"
      @update:active="filter = $event"
    />

    <div
      v-if="isLoading"
      class="flex items-center justify-center py-20 gap-3 text-slate-400"
    >
      <i class="i-lucide-loader-2 animate-spin text-woot-400 text-xl" />
      <span>{{ t('PATIENT_TIMELINE.LOADING') }}</span>
    </div>

    <div
      v-else-if="!isLoading && filteredEvents.length === 0"
      class="tl-empty"
    >
      <div class="tl-empty-icon">
        <i class="i-lucide-clock-x w-6 h-6" />
      </div>
      <p class="tl-empty-title">{{ t('PATIENT_TIMELINE.EMPTY.TITLE') }}</p>
      <p class="tl-empty-hint">
        {{
          filter !== 'all'
            ? t('PATIENT_TIMELINE.EMPTY.HINT_FILTERED')
            : t('PATIENT_TIMELINE.EMPTY.HINT_ALL')
        }}
      </p>
      <BeclinicButton
        v-if="filter !== 'all'"
        size="sm"
        variant="ghost"
        color="slate"
        :label="t('PATIENT_TIMELINE.FILTERS.CLEAR')"
        class="mt-1"
        @click="filter = 'all'"
      />
    </div>

    <div v-else class="tl-timeline">
      <div
        v-for="group in groupedEvents"
        :key="group.date"
        class="tl-group"
      >
        <div class="tl-date-divider">
          <div class="tl-date-line" />
          <span class="tl-date-label">{{ group.date }}</span>
          <div class="tl-date-line" />
        </div>

        <div class="tl-events">
          <div class="tl-vline" />
          <TimelineEventCard
            v-for="event in group.events"
            :key="event.id"
            :event="event"
          />
        </div>
      </div>

      <!-- Sentinel do progressive list — IntersectionObserver dispara o
           próximo batch quando esse elemento entra na viewport. -->
      <div
        v-if="hasMoreEvents"
        ref="timelineSentinel"
        class="tl-load-more-sentinel"
      >
        <i class="i-lucide-loader-2 animate-spin text-slate-400 text-base" />
        <span>{{ t('PATIENT_TIMELINE.LOADING_MORE') || 'Carregando mais…' }}</span>
      </div>

      <div v-else class="tl-history-end">
        <div class="tl-history-line" />
        <div class="tl-history-dot" />
        <span class="tl-history-label">
          {{ t('PATIENT_TIMELINE.TIMELINE.HISTORY_END') }}
        </span>
        <div class="tl-history-line" />
      </div>
    </div>
  </div>
</template>
