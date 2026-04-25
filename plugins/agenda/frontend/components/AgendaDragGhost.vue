<script>
import { formatEventTime } from '../utils/agenda-date.js';

export default {
  name: 'AgendaDragGhost',
  props: {
    event: { type: Object, required: true },
    ghostStyle: { type: Object, required: true },
    dragStartsAt: { type: String, default: null },
    dragEndsAt: { type: String, default: null },
  },
  methods: {
    formatEventTime,
  },
};
</script>

<template>
  <div class="timeline-evt drag-ghost" :style="ghostStyle">
    <div class="evt-sbs-body">
      <span class="evt-sbs-title drag-ghost-title">
        {{ event.title }}
      </span>
      <span
        v-if="event.custom_attributes?.treatment"
        class="evt-sbs-title drag-ghost-title opacity-80 font-normal"
        style="margin-top: -2px"
      >
        {{ event.custom_attributes.treatment }}
      </span>
      <span class="evt-sbs-time">
        <i class="i-lucide-clock time-icon" />
        {{ formatEventTime(dragStartsAt) }} -
        {{ formatEventTime(dragEndsAt) }}
      </span>
    </div>
  </div>
</template>
