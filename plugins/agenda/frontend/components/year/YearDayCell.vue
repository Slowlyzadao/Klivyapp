<script setup>
/**
 * YearDayCell — célula de heatmap (1 dia) na Year View.
 *
 * Render puro/stateless. Props mínimas — re-render apenas quando bucket
 * ou stats mudam. O Tooltip é montado lazy (só renderiza ao hover via
 * Teleport para `<body>`), então 365 células não inflam o DOM.
 *
 * Tooltip:
 *   - 2 linhas: nome do dia da semana (pt-BR completo, ex: "Quinta-feira")
 *     + contagem com plural correto ("1 agendado" / "8 agendados").
 *   - Variant `year-view` aplica estilo premium (sem borda, sombra suave,
 *     suporte a `\n`).
 *
 * A11y:
 *   - `<button>` semântico (não <div>) — tab-navigable
 *   - aria-label com data completa pra screen readers
 */
import { computed, getCurrentInstance } from 'vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import { MONTH_KEYS } from '../../utils/agenda-constants.js';

const props = defineProps({
  day: { type: Number, required: true },
  dateKey: { type: String, required: true },
  bucket: { type: Number, required: true }, // 0..4
  stats: { type: Object, default: null }, // { count, confirmed, ... } ou null
  isToday: { type: Boolean, default: false },
  // Lista de bloqueios FUTUROS aplicáveis a este dia, vinda do useAgenda
  // (já filtrada pra remover blocos passados — ver YearMonthCard).
  // Cada item: { type: 'holiday' | 'exception' | 'closed', title: string }
  blockInfo: { type: Array, default: () => [] },
});

const emit = defineEmits(['click']);

const { proxy } = getCurrentInstance();
const t = proxy.$t.bind(proxy);

// Formatter pt-BR reutilizável — Intl é cached pelo runtime, mas instanciar
// fora do render evita realocações por célula. Module-scope porque é puro.
const WEEKDAY_FMT = new Intl.DateTimeFormat('pt-BR', { weekday: 'long' });

function capitalize(s) {
  if (!s) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

const monthIndex = computed(() => parseInt(props.dateKey.slice(5, 7), 10) - 1);
const monthLabel = computed(() => t(`AGENDA.MONTHS.${MONTH_KEYS[monthIndex.value]}`));
const yearNum = computed(() => parseInt(props.dateKey.slice(0, 4), 10));

const weekdayName = computed(() => {
  // dateKey 'YYYY-MM-DD' → Date local (sem TZ shift que vem do parser ISO)
  const d = new Date(yearNum.value, monthIndex.value, props.day);
  return capitalize(WEEKDAY_FMT.format(d));
});

const total = computed(() => props.stats?.count || 0);

// Quando 0 eventos, retorna `null` — o tooltip omite a linha de contagem
// pra ficar mais limpo (só dia da semana, ou dia + motivo do bloqueio).
const countLabel = computed(() => {
  const n = total.value;
  if (n === 0) return null;
  if (n === 1) return `1 ${t('AGENDA.YEAR.SCHEDULED_NOUN_SINGULAR')}`;
  return `${n} ${t('AGENDA.YEAR.SCHEDULED_NOUN_PLURAL')}`;
});

// Bloqueio: primeiro bloco da lista (geralmente só há 1 — feriado OU folga
// OU dia fechado). Quando há sobreposição, prioriza pelo tipo mais explícito
// (holiday > exception > closed).
const BLOCK_PRIORITY = { holiday: 0, exception: 1, closed: 2 };
const primaryBlock = computed(() => {
  const arr = props.blockInfo || [];
  if (!arr.length) return null;
  return [...arr].sort(
    (a, b) => (BLOCK_PRIORITY[a.type] ?? 9) - (BLOCK_PRIORITY[b.type] ?? 9)
  )[0];
});

const isBlocked = computed(() => !!primaryBlock.value);

const blockLabel = computed(() => {
  const b = primaryBlock.value;
  if (!b) return '';
  // Título já vem traduzido do useAgenda (ex: "Natal", "Folga: feriado emendado",
  // "Fechado"). Não adicionamos prefixo redundante.
  return b.title;
});

// Tooltip: até 3 linhas separadas por `\n`. CSS variant `year-view` preserva
// quebras via `white-space: pre-line`. Linhas vazias são omitidas pra evitar
// ruído ("Sem agendamentos" some quando não há eventos — fica só o dia).
const tooltipLabel = computed(() => {
  const lines = [weekdayName.value];
  if (blockLabel.value) lines.push(blockLabel.value);
  if (countLabel.value) lines.push(countLabel.value);
  return lines.join('\n');
});

const ariaLabel = computed(() => {
  const parts = [
    `${weekdayName.value}, ${props.day} ${t('AGENDA.OF')} ${monthLabel.value.toLowerCase()}`,
  ];
  if (blockLabel.value) parts.push(blockLabel.value);
  if (countLabel.value) parts.push(countLabel.value);
  return parts.join(' · ');
});

function onClick() {
  emit('click');
}
</script>

<template>
  <Tooltip
    :label="tooltipLabel"
    position="top"
    :delay="120"
    multiline
    variant="year-view"
  >
    <button
      type="button"
      class="ydc"
      :class="[
        `ydc--bucket-${bucket}`,
        {
          'ydc--today': isToday,
          'ydc--empty': total === 0,
          'ydc--blocked': isBlocked,
          [`ydc--block-${primaryBlock?.type}`]: isBlocked,
        },
      ]"
      :aria-label="ariaLabel"
      @click="onClick"
    >
      <span class="ydc__num">{{ day }}</span>
    </button>
  </Tooltip>
</template>
