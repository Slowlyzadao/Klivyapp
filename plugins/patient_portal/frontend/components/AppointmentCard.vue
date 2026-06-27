<template>
  <router-link :to="{ name: 'appointment-detail', params: { id: appointment.id } }" class="pp-appt-card">
    <div class="pp-appt-card__date">
      <div class="pp-appt-card__day">{{ day }}</div>
      <div class="pp-appt-card__month">{{ month }}</div>
    </div>
    <div class="pp-appt-card__body">
      <div class="pp-appt-card__title">{{ appointment.title }}</div>
      <div class="pp-appt-card__meta">
        <span class="pp-appt-card__time">
          <IconClock :size="13" /> {{ time }}
        </span>
        <span v-if="appointment.professional" class="pp-appt-card__pro">
          · {{ appointment.professional.name }}
        </span>
      </div>
      <div v-if="appointment.service" class="pp-appt-card__service">{{ appointment.service.name }}</div>
    </div>
    <div class="pp-appt-card__trailing">
      <AppointmentStatusBadge :status="appointment.status" :cancelled="appointment.cancelled" size="sm" />
      <IconChevronRight :size="18" class="pp-appt-card__chevron" />
    </div>
  </router-link>
</template>

<script setup>
import { computed } from 'vue';
import IconClock from './icons/IconClock.vue';
import IconChevronRight from './icons/IconChevronRight.vue';
import AppointmentStatusBadge from './AppointmentStatusBadge.vue';
import { formatTime } from '../utils/format';

const props = defineProps({
  appointment: { type: Object, required: true }
});

const MONTHS = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];

const day = computed(() => {
  const d = new Date(props.appointment.starts_at);
  return String(d.getDate()).padStart(2, '0');
});
const month = computed(() => MONTHS[new Date(props.appointment.starts_at).getMonth()]);
const time  = computed(() => formatTime(props.appointment.starts_at));
</script>

<style scoped>
.pp-appt-card {
  display: flex; align-items: center; gap: 12px;
  background: #fff; border: 1px solid var(--pp-color-border); border-radius: 14px;
  padding: 12px; text-decoration: none; color: inherit;
  transition: transform 80ms ease, box-shadow 120ms ease, border-color 120ms ease;
}
.pp-appt-card:hover  { box-shadow: 0 4px 12px rgba(15, 23, 42, .06); border-color: var(--pp-color-primary); }
.pp-appt-card:active { transform: scale(0.99); }

.pp-appt-card__date {
  flex-shrink: 0; width: 48px;
  display: flex; flex-direction: column; align-items: center; justify-content: center;
  background: color-mix(in srgb, var(--pp-color-primary) 10%, transparent);
  color: var(--pp-color-primary);
  border-radius: 10px; padding: 8px 6px;
}
.pp-appt-card__day   { font-size: 18px; font-weight: 800; line-height: 1; }
.pp-appt-card__month { font-size: 10px; font-weight: 700; letter-spacing: 1px; margin-top: 3px; }

.pp-appt-card__body  { flex: 1; min-width: 0; }
.pp-appt-card__title { font-weight: 600; font-size: 15px; color: var(--pp-color-text); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pp-appt-card__meta  { display: flex; align-items: center; gap: 4px; font-size: 12px; color: var(--pp-color-text-muted); margin-top: 4px; }
.pp-appt-card__time  { display: inline-flex; align-items: center; gap: 4px; }
.pp-appt-card__pro   { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.pp-appt-card__service { font-size: 11px; color: var(--pp-color-text-muted); margin-top: 2px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }

.pp-appt-card__trailing { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
.pp-appt-card__chevron  { color: var(--pp-color-text-muted); }
</style>
