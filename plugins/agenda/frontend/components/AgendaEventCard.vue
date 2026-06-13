<script>
import { getEventSizeTier } from '../utils/agenda-date.js';
import { formatEventTime } from '../utils/agenda-date.js';
import { STATUS_CONFIGS } from '../utils/agenda-constants.js';

export default {
  name: 'AgendaEventCard',
  props: {
    event: { type: Object, required: true },
    cardStyle: { type: Object, default: () => ({}) },
    agentColor: { type: String, default: '#3b82f6' },
    treatmentColor: { type: String, default: null },
    isResizingThis: { type: Boolean, default: false },
    isDraggingThis: { type: Boolean, default: false },
    isLate: { type: Boolean, default: false },
    resizingEndAt: { type: String, default: null },
    layoutMode: { type: String, default: 'side-by-side' },
  },
  emits: ['click', 'quick-delete', 'mousedown-drag', 'mousedown-resize'],
  computed: {
    cardHeightPx() {
      return parseInt(this.cardStyle?.height) || 0;
    },
    sizeTier() {
      const h = this.cardHeightPx;
      if (h <= 32) return 'pill';
      if (h <= 50) return 'small';
      if (h <= 70) return 'medium';
      return 'full';
    },
    statusConfig() {
      return STATUS_CONFIGS[this.event.status] || STATUS_CONFIGS.scheduled;
    },
    tooltipText() {
      return [
        this.event.title,
        this.treatment,
        this.statusConfig.label,
        this.isLate ? 'Atrasado' : null,
      ]
        .filter(Boolean)
        .join(' · ');
    },
    hasStarIcon() {
      return this.treatment === 'Avaliação' || this.event.icon;
    },
    isBlock() {
      return this.event.event_type === 'agenda_block';
    },
    isAppointment() {
      return this.event.event_type === 'appointment';
    },
    isNonConsultation() {
      return this.isBlock || this.isAppointment;
    },
    typeIconClass() {
      if (this.isBlock) return 'i-lucide-lock';
      if (this.isAppointment) return 'i-lucide-calendar-clock';
      return null;
    },
    typeIconTooltip() {
      if (this.isBlock) return 'Horário bloqueado';
      if (this.isAppointment) return 'Compromisso';
      return null;
    },
    // PR #6 (follow-up²): live lookup no store de serviços PRIMEIRO — captura
    // rename imediato sem precisar refetchar eventos (snapshot inline congela
    // no momento do fetch). Fallback: snapshot inline → JSONB legado.
    treatment() {
      const sid = this.event?.agenda_service_id;
      if (sid != null && this.$store) {
        const live = this.$store.getters['agendaServices/getServiceById'](sid);
        if (live?.name) return live.name;
      }
      return this.event?.agenda_service?.name || this.event.custom_attributes?.treatment || '';
    },
    displayEndTime() {
      if (this.isResizingThis && this.resizingEndAt) {
        return formatEventTime(this.resizingEndAt);
      }
      return formatEventTime(this.event.ends_at);
    },
  },
  methods: {
    formatEventTime,
  },
};
</script>

<template>
  <div
    class="timeline-evt"
    :class="[
      'evt-' + layoutMode,
      'priority-' + (event.custom_attributes?.priority || 'medium'),
      {
        'is-resizing': isResizingThis,
        'is-dragging': isDraggingThis,
        'evt-pill': sizeTier === 'pill',
        'evt-small': sizeTier === 'small',
        'evt-medium': sizeTier === 'medium',
        'evt-late': isLate,
        'evt-no-show': event.status === 'no_show',
        // Auditoria 2026-05-15: cancelados ganham strikethrough + opacidade
        // pra clínica distinguir visualmente do agendamento ativo. Padrão de
        // calendário (Google/Outlook). Cor de base permanece pra preservar
        // identidade do tratamento, mas título fica riscado e card opaco.
        'evt-cancelled': event.status === 'cancelled',
        'evt-type-block': isBlock,
        'evt-type-appointment': isAppointment,
      },
    ]"
    :style="cardStyle"
    :data-tooltip="tooltipText"
    @mousedown.stop="$emit('mousedown-drag', $event)"
    @click.stop="$emit('click', $event)"
  >
    <!-- ══ PILL (≤26px) — linha única badge ══ -->
    <template v-if="sizeTier === 'pill'">
      <div class="evt-pill-body">
        <span v-if="isNonConsultation" class="evt-type-icon-wrap">
          <svg
            v-if="isBlock"
            class="evt-type-icon"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
            <path d="M7 11V7a5 5 0 0 1 10 0v4" />
          </svg>
          <svg
            v-else
            class="evt-type-icon"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <path d="M21 7.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h3.5" />
            <path d="M16 2v4" />
            <path d="M8 2v4" />
            <path d="M3 10h5" />
            <path d="M17.5 17.5 16 16.3V14" />
            <circle cx="16" cy="16" r="6" />
          </svg>
          <span class="evt-type-tooltip" role="tooltip">{{ typeIconTooltip }}</span>
        </span>
        <span
          v-else
          class="evt-status-dot-sm"
          :style="{ background: statusConfig.color }"
        />
        <span class="evt-pill-name">{{ event.title }}</span>
        <span class="evt-pill-sep">,</span>
        <span class="evt-pill-time">
          {{ formatEventTime(event.starts_at) }} - {{ displayEndTime }}
        </span>
      </div>
      <div class="evt-pill-actions">
        <button
          class="evt-info-btn-hover !p-0"
          @click.stop="$emit('quick-delete')"
        >
          <span class="i-lucide-trash-2 w-3 h-3" />
        </button>
      </div>
    </template>

    <!-- ══ SMALL (27–44px) — nome + hora início ══ -->
    <div v-else-if="sizeTier === 'small'" class="evt-small-body">
      <span v-if="isNonConsultation" class="evt-type-icon-wrap">
        <svg
          v-if="isBlock"
          class="evt-type-icon"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
          <path d="M7 11V7a5 5 0 0 1 10 0v4" />
        </svg>
        <svg
          v-else
          class="evt-type-icon"
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2.5"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <path d="M21 7.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h3.5" />
          <path d="M16 2v4" />
          <path d="M8 2v4" />
          <path d="M3 10h5" />
          <path d="M17.5 17.5 16 16.3V14" />
          <circle cx="16" cy="16" r="6" />
        </svg>
        <span class="evt-type-tooltip" role="tooltip">{{ typeIconTooltip }}</span>
      </span>
      <span
        v-else
        class="evt-status-dot-sm"
        :style="{ background: statusConfig.color }"
      />
      <span class="evt-small-name">{{ event.title }}</span>
      <span class="evt-small-time">{{ formatEventTime(event.starts_at) }}</span>
      <button
        class="evt-info-btn-inline"
        @click.stop="$emit('quick-delete')"
      >
        <span class="i-lucide-trash-2 w-3 h-3" />
      </button>
    </div>

    <!-- ══ MEDIUM (45–68px) — nome (2 linhas) + range ══ -->
    <template v-else-if="sizeTier === 'medium'">
      <div class="evt-normal-actions">
        <button
          class="evt-info-btn-hover !p-0"
          @click.stop="$emit('quick-delete')"
        >
          <span class="i-lucide-trash-2 w-3 h-3" />
        </button>
        <svg
          v-if="hasStarIcon"
          class="evt-star-abs"
          width="11"
          height="11"
          viewBox="0 -10 511.98685 511"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="m510.652344 185.902344c-3.351563-10.367188-12.546875-17.730469-23.425782-18.710938l-147.773437-13.417968-58.433594-136.769532c-4.308593-10.023437-14.121093-16.511718-25.023437-16.511718s-20.714844 6.488281-25.023438 16.535156l-58.433594 136.746094-147.796874 13.417968c-10.859376 1.003906-20.03125 8.34375-23.402344 18.710938-3.371094 10.367187-.257813 21.738281 7.957031 28.90625l111.699219 97.960937-32.9375 145.089844c-2.410156 10.667969 1.730468 21.695313 10.582031 28.09375 4.757813 3.4375 10.324219 5.1875 15.9375 5.1875 4.839844 0 9.640625-1.304687 13.949219-3.882813l127.46875-76.183593 127.421875 76.183593c9.324219 5.609376 21.078125 5.097657 29.910156-1.304687 8.855469-6.417969 12.992187-17.449219 10.582031-28.09375l-32.9375-145.089844 111.699219-97.941406c8.214844-7.1875 11.351563-18.539063 7.980469-28.925781z"
            fill="#ffc107"
          />
        </svg>
      </div>
      <div class="evt-sbs-body">
        <span class="evt-title-wrap">
          <span v-if="isNonConsultation" class="evt-type-icon-wrap">
            <svg
              v-if="isBlock"
              class="evt-type-icon"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
            <svg
              v-else
              class="evt-type-icon"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M21 7.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h3.5" />
              <path d="M16 2v4" />
              <path d="M8 2v4" />
              <path d="M3 10h5" />
              <path d="M17.5 17.5 16 16.3V14" />
              <circle cx="16" cy="16" r="6" />
            </svg>
            <span class="evt-type-tooltip" role="tooltip">{{ typeIconTooltip }}</span>
          </span>
          <span
            v-else
            class="evt-status-dot-sm"
            :style="{ background: statusConfig.color }"
          />
          <span class="evt-sbs-title evt-sbs-title--clamp">
            {{ event.title }}
          </span>
        </span>
        <div class="evt-sbs-time-row">
          <span class="evt-sbs-time">
            {{ formatEventTime(event.starts_at) }} - {{ displayEndTime }}
          </span>
          <span v-if="isLate" class="evt-late-icon">!</span>
        </div>
      </div>
    </template>

    <!-- ══ NORMAL (>40 min) ══ -->
    <template v-else>
      <div class="evt-normal-actions">
        <button
          class="evt-info-btn-hover !p-0"
          @click.stop="$emit('quick-delete')"
        >
          <span class="i-lucide-trash-2 w-3 h-3" />
        </button>
        <svg
          v-if="hasStarIcon"
          class="evt-star-abs"
          width="11"
          height="11"
          viewBox="0 -10 511.98685 511"
          xmlns="http://www.w3.org/2000/svg"
        >
          <path
            d="m510.652344 185.902344c-3.351563-10.367188-12.546875-17.730469-23.425782-18.710938l-147.773437-13.417968-58.433594-136.769532c-4.308593-10.023437-14.121093-16.511718-25.023437-16.511718s-20.714844 6.488281-25.023438 16.535156l-58.433594 136.746094-147.796874 13.417968c-10.859376 1.003906-20.03125 8.34375-23.402344 18.710938-3.371094 10.367187-.257813 21.738281 7.957031 28.90625l111.699219 97.960937-32.9375 145.089844c-2.410156 10.667969 1.730468 21.695313 10.582031 28.09375 4.757813 3.4375 10.324219 5.1875 15.9375 5.1875 4.839844 0 9.640625-1.304687 13.949219-3.882813l127.46875-76.183593 127.421875 76.183593c9.324219 5.609376 21.078125 5.097657 29.910156-1.304687 8.855469-6.417969 12.992187-17.449219 10.582031-28.09375l-32.9375-145.089844 111.699219-97.941406c8.214844-7.1875 11.351563-18.539063 7.980469-28.925781z"
            fill="#ffc107"
          />
        </svg>
      </div>

      <div class="evt-sbs-body">
        <span class="evt-title-wrap">
          <span v-if="isNonConsultation" class="evt-type-icon-wrap">
            <svg
              v-if="isBlock"
              class="evt-type-icon"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <rect width="18" height="11" x="3" y="11" rx="2" ry="2" />
              <path d="M7 11V7a5 5 0 0 1 10 0v4" />
            </svg>
            <svg
              v-else
              class="evt-type-icon"
              xmlns="http://www.w3.org/2000/svg"
              viewBox="0 0 24 24"
              fill="none"
              stroke="currentColor"
              stroke-width="2.5"
              stroke-linecap="round"
              stroke-linejoin="round"
            >
              <path d="M21 7.5V6a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h3.5" />
              <path d="M16 2v4" />
              <path d="M8 2v4" />
              <path d="M3 10h5" />
              <path d="M17.5 17.5 16 16.3V14" />
              <circle cx="16" cy="16" r="6" />
            </svg>
            <span class="evt-type-tooltip" role="tooltip">{{ typeIconTooltip }}</span>
          </span>
          <span
            v-else
            class="evt-status-dot-sm"
            :style="{ background: statusConfig.color }"
          />
          <span class="evt-sbs-title">
            {{ event.title }}
          </span>
        </span>
        <div class="evt-sbs-time-row">
          <span class="evt-sbs-time">
            {{ formatEventTime(event.starts_at) }} - {{ displayEndTime }}
          </span>
          <span v-if="isLate" class="evt-late-icon">!</span>
        </div>
        <span
          v-if="treatment"
          class="evt-sbs-treatment evt-sbs-treatment--bottom"
        >
          <span
            class="evt-treatment-dot"
            :style="{ background: treatmentColor || agentColor }"
          />
          <span class="evt-treatment-label">{{ treatment }}</span>
        </span>
      </div>
    </template>

    <div
      class="evt-resize-handle"
      @mousedown.stop="$emit('mousedown-resize', $event)"
    />
  </div>
</template>
