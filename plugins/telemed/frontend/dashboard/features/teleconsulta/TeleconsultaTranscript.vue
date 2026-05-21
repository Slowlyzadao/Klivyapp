<script setup>
// Transcrição da teleconsulta no formato de chat (DR/PACIENTE).
// Audit Fase 3 — virtualizada via `DynamicScroller` (vue-virtual-scroller).
// Antes mostrava só PAGE_SIZE iniciais e tinha botão "Carregar mais";
// consulta de 1h+ tem 200-800 segmentos → loop crescente de DOM nodes
// degradava scroll em low-end. Agora rendera só o viewport (~10 nodes)
// independente da contagem total.
//
// `DynamicScroller` (vs `RecycleScroller`) acomoda alturas variáveis
// (mensagens curtas/longas) sem precisar declarar `item-size` fixo.
import { computed } from 'vue';
import { DynamicScroller, DynamicScrollerItem } from 'vue-virtual-scroller';
import 'vue-virtual-scroller/dist/vue-virtual-scroller.css';
import { initialsFromName, formatClockSeconds } from './utils/formatters.js';

const props = defineProps({
  segments: { type: Array, default: () => [] },
  text: { type: String, default: '' },
  doctorName: { type: String, default: 'Dr.' },
  patientName: { type: String, default: 'Paciente' },
});
const emit = defineEmits(['segment-click']);

const hasSegments = computed(() =>
  Array.isArray(props.segments) && props.segments.length > 0
);

// DynamicScroller exige cada item com chave estável (`id`). Construímos
// uma vez aqui em vez de recalcular no template — `start` é único na
// prática (timestamps Whisper são monotonics por track).
const indexedSegments = computed(() =>
  (props.segments || []).map((seg, i) => ({
    ...seg,
    _id: `${seg.start ?? i}-${seg.speaker || ''}-${i}`,
  }))
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
</script>

<template>
  <section class="tcd-card">
    <h3 class="tcd-card__title">
      <i class="i-lucide-file-text w-5 h-5 tcd-card__title-icon" />
      <span>Transcrição</span>
    </h3>

    <DynamicScroller
      v-if="hasSegments"
      :items="indexedSegments"
      :min-item-size="80"
      key-field="_id"
      class="tcd-transcript tcd-transcript--virtual"
    >
      <template #default="{ item: seg, index, active }">
        <DynamicScrollerItem
          :item="seg"
          :active="active"
          :data-index="index"
          :size-dependencies="[seg.text]"
        >
          <div class="tcd-transcript__msg">
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
        </DynamicScrollerItem>
      </template>
    </DynamicScroller>

    <p v-else-if="text" class="tcd-transcript__text">{{ text }}</p>
    <p v-else class="tcd-transcript__empty">
      Transcrição ainda não disponível.
    </p>
  </section>
</template>

<style scoped>
/* DynamicScroller precisa de altura fixa pro viewport — sem isso o
   container colapsa e nada renderiza. 60vh dá scroll suficiente sem
   tomar a tela inteira do detalhe. Audit Fase 3. */
.tcd-transcript--virtual {
  height: 60vh;
  min-height: 320px;
  max-height: 720px;
  overflow-y: auto;
}
</style>
