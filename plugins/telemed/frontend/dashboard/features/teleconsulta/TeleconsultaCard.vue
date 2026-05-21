<script setup>
// Card individual da listagem de teleconsultas (clínica).
// Variantes baseadas no `item.status`:
//   in_progress → "live"      : barra verde, chip "Ao vivo", contador de
//                               duração ao vivo, botão "Entrar" habilitado.
//   arrived     → "waiting"   : barra azul, chip "Aguardando", data e hora,
//                               "Entrar" desabilitado (paciente esperando).
//   completed   → "completed" : chip verde "Concluído", info inline,
//                               "Ver Detalhes" + "Ver Resumo".
//   no_show     → "no_show"   : chip vermelho "Sem comparec.", info inline,
//                               "Ver Detalhes" como única ação.
//   *           → "upcoming"  : sem barra, chip do status, motivo + data,
//                               "Preparar" + "Ver detalhes".
// Estilos: ../../../styles/teleconsulta-index.scss (carregado pela página).
import { computed } from 'vue';
import {
  STATUS_LABELS,
  initialsFromName,
  formatStartDateLabel,
  formatPastDateLabel,
  formatRelativeHint,
  formatClockSeconds,
} from './utils/formatters.js';
import { useLiveDuration } from '../../composables/useLiveDuration.js';

const props = defineProps({
  item: { type: Object, required: true },
});
const emit = defineEmits(['open', 'prepare', 'enter-room', 'summary']);

const variant = computed(() => {
  switch (props.item.status) {
    case 'in_progress': return 'live';
    case 'arrived':     return 'waiting';
    case 'completed':   return 'completed';
    case 'no_show':     return 'no_show';
    default:            return 'upcoming';
  }
});

const cardClass = computed(() => ({
  'tc-card': true,
  [`tc-card--${variant.value}`]: true,
}));

const initials = computed(() => initialsFromName(props.item.patient?.name));
const motivo = computed(() => props.item.title?.trim() || 'Consulta');
const professional = computed(() => props.item.professional?.name || '—');

const upcomingDateLabel = computed(() => formatStartDateLabel(props.item.starts_at));
const upcomingDateHint  = computed(() => formatRelativeHint(props.item.starts_at));
const pastDateLabel     = computed(() => formatPastDateLabel(props.item.starts_at));

const statusClass = computed(() => `tc-chip tc-chip--${props.item.status}`);
const statusLabel = computed(() => {
  if (variant.value === 'live')      return 'Ao vivo';
  if (variant.value === 'completed') return 'Concluído';
  return STATUS_LABELS[props.item.status] || props.item.status || '—';
});

// Duração ao vivo (somente para in_progress). Usa o `recording.started_at`
// quando disponível; cai no `starts_at` do evento como fallback (menos
// preciso, mas mantém a UI viva enquanto a gravação não nasce).
const liveStart = computed(() => {
  if (variant.value !== 'live') return null;
  return props.item.recording?.started_at || props.item.starts_at;
});
const { seconds: liveSeconds } = useLiveDuration(liveStart);
const liveLabel = computed(() => formatClockSeconds(liveSeconds.value));

const canEnter = computed(() => variant.value === 'live');
</script>

<template>
  <article :class="cardClass" @click="emit('open')">
    <header class="tc-card__head">
      <div class="tc-card__patient">
        <div class="tc-card__avatar" :aria-hidden="true">{{ initials }}</div>
        <div class="tc-card__patient-info">
          <h3 class="tc-card__name">{{ item.patient?.name || '—' }}</h3>
          <p class="tc-card__professional">{{ professional }}</p>
        </div>
      </div>
      <span :class="statusClass">
        <span v-if="variant === 'live'" class="tc-chip__live-dot" aria-hidden="true" />
        <i v-if="variant === 'completed'" class="i-lucide-check-circle w-3.5 h-3.5" />
        {{ statusLabel }}
      </span>
    </header>

    <div class="tc-card__body">
      <!-- Variante "live": foco no motivo + duração ao vivo -->
      <template v-if="variant === 'live'">
        <div class="tc-info-row">
          <i class="i-lucide-stethoscope w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Motivo</span>
            <span class="tc-info-row__value">{{ motivo }}</span>
          </div>
        </div>
        <div class="tc-info-row">
          <i class="i-lucide-clock w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Duração atual</span>
            <span class="tc-info-row__value tc-info-row__value--live">{{ liveLabel }}</span>
          </div>
        </div>
      </template>

      <!-- Variante "waiting": data/hora primeiro, motivo logo abaixo -->
      <template v-else-if="variant === 'waiting'">
        <div class="tc-info-row">
          <i class="i-lucide-calendar w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Data e hora</span>
            <span class="tc-info-row__value">
              {{ upcomingDateLabel }}
              <span v-if="upcomingDateHint" class="tc-info-row__hint">({{ upcomingDateHint }})</span>
            </span>
          </div>
        </div>
        <div class="tc-info-row">
          <i class="i-lucide-stethoscope w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Motivo</span>
            <span class="tc-info-row__value">{{ motivo }}</span>
          </div>
        </div>
      </template>

      <!-- Variantes "completed"/"no_show": info em formato inline (compacto) -->
      <template v-else-if="variant === 'completed' || variant === 'no_show'">
        <div class="tc-info-row tc-info-row--inline">
          <i class="i-lucide-stethoscope w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Motivo</span>
            <span class="tc-info-row__value">{{ motivo }}</span>
          </div>
        </div>
        <div class="tc-info-row tc-info-row--inline">
          <i class="i-lucide-calendar w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Data</span>
            <span class="tc-info-row__value">{{ pastDateLabel }}</span>
          </div>
        </div>
      </template>

      <!-- Variante "upcoming" (padrão) -->
      <template v-else>
        <div class="tc-info-row">
          <i class="i-lucide-stethoscope w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Motivo</span>
            <span class="tc-info-row__value">{{ motivo }}</span>
          </div>
        </div>
        <div class="tc-info-row">
          <i class="i-lucide-calendar w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Data</span>
            <span class="tc-info-row__value">
              {{ upcomingDateLabel }}
              <span v-if="upcomingDateHint" class="tc-info-row__hint">({{ upcomingDateHint }})</span>
            </span>
          </div>
        </div>
      </template>
    </div>

    <footer class="tc-card__actions" @click.stop>
      <!-- Live/waiting → "Entrar" (primário; desabilitado quando aguardando) -->
      <template v-if="variant === 'live' || variant === 'waiting'">
        <button
          type="button"
          class="tc-btn tc-btn--primary"
          :disabled="!canEnter"
          :aria-label="canEnter ? 'Entrar na sala' : 'Sala ainda não iniciada'"
          @click="emit('enter-room')"
        >
          <i :class="[canEnter ? 'i-lucide-log-in' : 'i-lucide-video-off', 'w-4 h-4']" />
          Entrar
        </button>
        <button
          type="button"
          class="tc-btn tc-btn--ghost"
          @click="emit('open')"
        >
          Ver detalhes
        </button>
      </template>

      <!-- Completed → "Ver Detalhes" + "Ver Resumo" (CTA primário) -->
      <template v-else-if="variant === 'completed'">
        <button
          type="button"
          class="tc-btn tc-btn--ghost"
          @click="emit('open')"
        >
          Ver Detalhes
        </button>
        <button
          type="button"
          class="tc-btn tc-btn--primary"
          @click="emit('summary')"
        >
          Ver Resumo
        </button>
      </template>

      <!-- No-show → uma ação (Ver Detalhes) — sem CTA primário -->
      <template v-else-if="variant === 'no_show'">
        <button
          type="button"
          class="tc-btn tc-btn--ghost"
          @click="emit('open')"
        >
          Ver Detalhes
        </button>
      </template>

      <!-- Upcoming → "Preparar" + "Ver detalhes" -->
      <template v-else>
        <button
          type="button"
          class="tc-btn tc-btn--ghost"
          @click="emit('prepare')"
        >
          Preparar
        </button>
        <button
          type="button"
          class="tc-btn tc-btn--ghost"
          @click="emit('open')"
        >
          Ver detalhes
        </button>
      </template>
    </footer>
  </article>
</template>
