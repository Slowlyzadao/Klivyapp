<script>
import { formatEventTime } from '../utils/agenda-date.js';

export default {
  name: 'AgendaDragGhost',
  props: {
    event: { type: Object, required: true },
    ghostStyle: { type: Object, required: true },
    dragStartsAt: { type: String, default: null },
    dragEndsAt: { type: String, default: null },
    isBlocked: { type: Boolean, default: false },
    blockReason: { type: String, default: null },
  },
  computed: {
    ghostHeightPx() {
      return parseInt(this.ghostStyle?.height) || 0;
    },
    sizeTier() {
      const h = this.ghostHeightPx;
      if (h <= 32) return 'pill';
      if (h <= 50) return 'small';
      if (h <= 70) return 'medium';
      return 'full';
    },
    // PR #6 (follow-up²): live lookup no store → snapshot inline → JSONB legado.
    treatment() {
      const sid = this.event?.agenda_service_id;
      if (sid != null && this.$store) {
        const live = this.$store.getters['agendaServices/getServiceById'](sid);
        if (live?.name) return live.name;
      }
      return this.event?.agenda_service?.name || this.event.custom_attributes?.treatment;
    },
  },
  methods: { formatEventTime },
};
</script>

<template>
  <div
    class="timeline-evt drag-ghost"
    :class="[
      'evt-' + sizeTier,
      { 'drag-ghost--blocked': isBlocked },
    ]"
    :style="ghostStyle"
  >
    <!-- PILL (≤26px): nome + horário inline -->
    <div v-if="sizeTier === 'pill'" class="evt-pill-body">
      <span class="evt-pill-name drag-ghost-title">{{ event.title }}</span>
      <span class="evt-pill-sep">,</span>
      <span class="evt-pill-time">
        {{ formatEventTime(dragStartsAt) }} - {{ formatEventTime(dragEndsAt) }}
      </span>
    </div>

    <!-- SMALL (27–44px): nome + hora início -->
    <div v-else-if="sizeTier === 'small'" class="evt-small-body">
      <span class="evt-small-name drag-ghost-title">{{ event.title }}</span>
      <span class="evt-small-time">{{ formatEventTime(dragStartsAt) }}</span>
    </div>

    <!-- MEDIUM (45–68px): nome (1 linha) + range -->
    <div v-else-if="sizeTier === 'medium'" class="evt-sbs-body">
      <span class="evt-sbs-title drag-ghost-title">{{ event.title }}</span>
      <span v-if="isBlocked" class="drag-ghost-blocked-label">
        <i class="i-lucide-ban" />
        {{ blockReason || 'Indisponível' }}
      </span>
      <span class="evt-sbs-time">
        <i class="i-lucide-clock time-icon" />
        {{ formatEventTime(dragStartsAt) }} - {{ formatEventTime(dragEndsAt) }}
      </span>
    </div>

    <!-- FULL (>68px): título → hora → tratamento na base -->
    <div v-else class="evt-sbs-body">
      <span class="evt-sbs-title drag-ghost-title">{{ event.title }}</span>
      <span class="evt-sbs-time">
        <i class="i-lucide-clock time-icon" />
        {{ formatEventTime(dragStartsAt) }} - {{ formatEventTime(dragEndsAt) }}
      </span>
      <span v-if="isBlocked" class="drag-ghost-blocked-label">
        <i class="i-lucide-ban" />
        {{ blockReason || 'Indisponível' }}
      </span>
      <span
        v-if="!isBlocked && treatment"
        class="evt-sbs-treatment evt-sbs-treatment--bottom"
      >
        <span
          class="evt-treatment-dot"
          :style="{ background: event._treatmentColor || 'currentColor' }"
        />
        <span class="evt-treatment-label">{{ treatment }}</span>
      </span>
    </div>
  </div>
</template>

<style scoped>
.evt-ghost-treatment {
  opacity: 0.8;
  font-weight: 400;
  margin-top: -2px;
}
</style>
