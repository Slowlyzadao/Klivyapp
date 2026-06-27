<script setup>
import { formatTimeBRT } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import {
  BRT,
  timelineEventConfig,
} from '@plugins/patients/frontend/constants/timeline';

defineProps({
  event: { type: Object, required: true },
});

const formatTime = formatTimeBRT;

const formatMetaValue = val => {
  if (typeof val === 'string' && /^\d{4}-\d{2}-\d{2}T/.test(val)) {
    return new Date(val)
      .toLocaleString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
        hour: '2-digit',
        minute: '2-digit',
        timeZone: BRT,
      })
      .replace(',', ' às');
  }
  return val;
};

const isVisibleMetaKey = (key, val) =>
  val && key !== 'account_id' && key !== 'patient_id';
</script>

<template>
  <div class="tl-event-row">
    <div
      class="tl-event-icon"
      :class="`tl-icon--${timelineEventConfig(event.event_type).color}`"
    >
      <i
        :class="timelineEventConfig(event.event_type).icon"
        class="w-4 h-4"
      />
    </div>

    <div class="tl-event-card">
      <div class="tl-event-header">
        <span
          class="tl-event-badge"
          :class="`tl-badge--${timelineEventConfig(event.event_type).color}`"
        >
          {{ timelineEventConfig(event.event_type).label }}
        </span>
        <span class="tl-event-time">{{ formatTime(event.occurred_at) }}</span>
      </div>

      <p class="tl-event-title">{{ event.label }}</p>

      <div
        v-if="event.metadata && Object.keys(event.metadata).length > 0"
        class="tl-event-meta"
      >
        <template v-for="(val, key) in event.metadata" :key="key">
          <div v-if="isVisibleMetaKey(key, val)" class="tl-meta-item">
            <span class="tl-meta-key">{{ key.replace(/_/g, ' ') }}</span>
            <span class="tl-meta-val">{{ formatMetaValue(val) }}</span>
          </div>
        </template>
      </div>

      <div v-if="event.actor_name" class="tl-event-actor">
        <i class="i-lucide-user-round w-3 h-3" />
        <span>{{ event.actor_name }}</span>
      </div>
    </div>
  </div>
</template>
