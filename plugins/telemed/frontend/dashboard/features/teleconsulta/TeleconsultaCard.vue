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
  formatStartDateLabel,
  formatPastDateLabel,
  formatRelativeHint,
  formatClockSeconds,
} from './utils/formatters.js';
import { useLiveDuration } from '../../composables/useLiveDuration.js';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

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

// Audit 2026-05-25: motivo NÃO pode ser `item.title` — o modal auto-preenche
// title com nome do paciente p/ label do calendário, então usar como motivo
// duplicava o paciente na linha "Motivo". Fontes verdadeiras, em ordem:
//   1. service.name (treatment selecionado no agendamento)
//   2. reason       (descrição/observação do agendamento)
//   3. null         → UI mostra "—" em vez de inventar texto genérico
const motivo = computed(() => {
  const service = props.item.service?.name?.trim();
  if (service) return service;
  const reason = props.item.reason?.trim();
  if (reason) return reason;
  return null;
});
const professional = computed(() => props.item.professional?.name || '—');

const upcomingDateLabel = computed(() => formatStartDateLabel(props.item.starts_at));
const upcomingDateHint  = computed(() => formatRelativeHint(props.item.starts_at));
const pastDateLabel     = computed(() => formatPastDateLabel(props.item.starts_at));

const statusLabel = computed(() => {
  if (variant.value === 'live')      return 'Ao vivo';
  if (variant.value === 'completed') return 'Concluído';
  return STATUS_LABELS[props.item.status] || props.item.status || '—';
});
// Mapeia o status pro intent do Badge padrão (beclinic_core).
const badgeIntent = computed(() => {
  switch (variant.value) {
    case 'live':      return 'success';
    case 'waiting':   return 'warning';
    case 'completed': return 'success';
    case 'no_show':   return 'danger';
    default:          return 'info';
  }
});
const badgeIcon = computed(() =>
  variant.value === 'completed' ? 'i-lucide-check-circle-2' : null
);

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
        <Avatar
          :src="item.patient?.avatar_url"
          :name="item.patient?.name || '—'"
          :size="44"
          rounded-full
        />
        <div class="tc-card__patient-info">
          <h3 class="tc-card__name">{{ item.patient?.name || '—' }}</h3>
          <p class="tc-card__professional">{{ professional }}</p>
        </div>
      </div>
      <Badge :label="statusLabel" :intent="badgeIntent" :icon="badgeIcon" />
    </header>

    <div class="tc-card__body">
      <!-- Variante "live": foco no motivo + duração ao vivo -->
      <template v-if="variant === 'live'">
        <div v-if="motivo" class="tc-info-row">
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
            <span class="tc-info-row__value">{{ upcomingDateLabel }}</span>
          </div>
          <Badge
            v-if="upcomingDateHint"
            :label="upcomingDateHint"
            intent="neutral"
            class="tc-date-badge"
          />
        </div>
        <div v-if="motivo" class="tc-info-row">
          <i class="i-lucide-stethoscope w-4 h-4 tc-info-row__icon" />
          <div class="tc-info-row__content">
            <span class="tc-info-row__label">Motivo</span>
            <span class="tc-info-row__value">{{ motivo }}</span>
          </div>
        </div>
      </template>

      <!-- Variantes "completed"/"no_show": info em formato inline (compacto) -->
      <template v-else-if="variant === 'completed' || variant === 'no_show'">
        <div v-if="motivo" class="tc-info-row tc-info-row--inline">
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
        <div v-if="motivo" class="tc-info-row">
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
            <span class="tc-info-row__value">{{ upcomingDateLabel }}</span>
          </div>
          <Badge
            v-if="upcomingDateHint"
            :label="upcomingDateHint"
            intent="neutral"
            class="tc-date-badge"
          />
        </div>
      </template>
    </div>

    <footer class="tc-card__actions" @click.stop>
      <!-- Live/waiting → "Entrar" (primário; desabilitado quando aguardando) -->
      <template v-if="variant === 'live' || variant === 'waiting'">
        <BeclinicButton
          size="sm"
          variant="solid"
          color="blue"
          :icon="canEnter ? 'i-lucide-log-in' : 'i-lucide-video-off'"
          label="Entrar"
          class="flex-1"
          :disabled="!canEnter"
          :title="canEnter ? 'Entrar na sala' : 'Sala ainda não iniciada'"
          @click="emit('enter-room')"
        />
        <BeclinicButton
          size="sm"
          variant="outline"
          color="slate"
          label="Ver detalhes"
          class="flex-1"
          @click="emit('open')"
        />
      </template>

      <!-- Completed → "Ver Resumo" é o CTA primário -->
      <template v-else-if="variant === 'completed'">
        <BeclinicButton
          size="sm"
          variant="outline"
          color="slate"
          label="Ver Detalhes"
          class="flex-1"
          @click="emit('open')"
        />
        <BeclinicButton
          size="sm"
          variant="solid"
          color="blue"
          label="Ver Resumo"
          class="flex-1"
          @click="emit('summary')"
        />
      </template>

      <!-- No-show → uma ação (Ver Detalhes) -->
      <template v-else-if="variant === 'no_show'">
        <BeclinicButton
          size="sm"
          variant="outline"
          color="slate"
          label="Ver Detalhes"
          class="w-full"
          @click="emit('open')"
        />
      </template>

      <!-- Upcoming → "Preparar" (primário leve) + "Ver detalhes" (sutil) -->
      <template v-else>
        <BeclinicButton
          size="sm"
          variant="faded"
          color="blue"
          label="Preparar"
          class="flex-1"
          @click="emit('prepare')"
        />
        <BeclinicButton
          size="sm"
          variant="outline"
          color="slate"
          label="Ver detalhes"
          class="flex-1"
          @click="emit('open')"
        />
      </template>
    </footer>
  </article>
</template>
