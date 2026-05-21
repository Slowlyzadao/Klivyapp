<script setup>
// Transcrição da teleconsulta no formato de chat (DR/PACIENTE).
// Mostra os primeiros N segmentos e expõe "Carregar mais" — clicar
// num segmento emite `segment-click` para o player buscar o timestamp.
import { ref, computed } from 'vue';
import { initialsFromName, formatClockSeconds } from './utils/formatters.js';

const PAGE_SIZE = 6;

const props = defineProps({
  segments: { type: Array, default: () => [] },
  text: { type: String, default: '' },
  doctorName: { type: String, default: 'Dr.' },
  patientName: { type: String, default: 'Paciente' },
});
const emit = defineEmits(['segment-click']);

const visibleCount = ref(PAGE_SIZE);

const hasSegments = computed(() =>
  Array.isArray(props.segments) && props.segments.length > 0
);

const visibleSegments = computed(() =>
  hasSegments.value ? props.segments.slice(0, visibleCount.value) : []
);

const hasMore = computed(() =>
  hasSegments.value && props.segments.length > visibleCount.value
);

// Heurística de fala: o backend marca speaker como "doutor"/"paciente"
// (em PT-BR), mas aceitamos variações ("doctor", "DR", "patient").
const isDoctor = speaker => {
  const s = String(speaker || '').toLowerCase();
  return s.startsWith('d') || s === 'dr' || s === 'doctor';
};

const speakerLabel = seg =>
  isDoctor(seg.speaker) ? props.doctorName : props.patientName;

const speakerInitials = seg =>
  initialsFromName(isDoctor(seg.speaker) ? props.doctorName : props.patientName);

const speakerClass = seg =>
  isDoctor(seg.speaker)
    ? 'tcd-transcript__avatar--doctor'
    : 'tcd-transcript__avatar--patient';

const loadMore = () => {
  visibleCount.value = Math.min(visibleCount.value + PAGE_SIZE, props.segments.length);
};
</script>

<template>
  <section class="tcd-card">
    <h3 class="tcd-card__title">
      <i class="i-lucide-file-text w-5 h-5 tcd-card__title-icon" />
      <span>Transcrição</span>
    </h3>

    <div v-if="hasSegments" class="tcd-transcript">
      <div
        v-for="seg in visibleSegments"
        :key="`${seg.start}-${seg.speaker || ''}`"
        class="tcd-transcript__msg"
      >
        <div :class="['tcd-transcript__avatar', speakerClass(seg)]">
          {{ speakerInitials(seg) }}
        </div>
        <div class="tcd-transcript__body">
          <div class="tcd-transcript__head">
            <span>{{ speakerLabel(seg) }}</span>
            <span class="tcd-transcript__timestamp">{{ formatClockSeconds(seg.start) }}</span>
          </div>
          <p
            class="tcd-transcript__text"
            role="button"
            tabindex="0"
            @click="emit('segment-click', seg)"
            @keydown.enter="emit('segment-click', seg)"
          >
            {{ seg.text }}
          </p>
        </div>
      </div>

      <button
        v-if="hasMore"
        type="button"
        class="tcd-transcript__more"
        @click="loadMore"
      >
        Carregar mais da transcrição
      </button>
    </div>

    <p v-else-if="text" class="tcd-transcript__text">{{ text }}</p>
    <p v-else class="tcd-transcript__empty">
      Transcrição ainda não disponível.
    </p>
  </section>
</template>
