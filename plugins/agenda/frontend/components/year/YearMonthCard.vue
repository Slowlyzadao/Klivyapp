<script setup>
/**
 * YearMonthCard — Mini calendário de um mês para a Year View.
 *
 * Layout grid 7 colunas (Dom..Sáb) com células do dia. Padding nas
 * primeiras/últimas posições para alinhar a primeira semana ao DOW correto.
 *
 * Performance:
 *   - `cells` é computed memoizado por (year, monthIndex) — só recomputa
 *     quando o mês muda (raríssimo: só ao trocar de ano via prev/next)
 *   - YearDayCell é puro, recebe props mínimas
 *   - Color bucket é função recebida via prop — recomputa só quando o
 *     consumidor (composable) muda
 */
import { computed, getCurrentInstance } from 'vue';
import YearDayCell from './YearDayCell.vue';

const props = defineProps({
  year: { type: Number, required: true },
  monthIndex: { type: Number, required: true }, // 0-11
  monthKey: { type: String, required: true },
  total: { type: Number, default: 0 },
  today: { type: Object, required: true }, // { year, month, day }
  colorBucket: { type: Function, required: true },
  getDay: { type: Function, required: true },
  // Funções vindas do useAgenda — bloqueios visuais (feriados/folgas/fechado).
  isDayBlocked: { type: Function, default: () => false },
  getDayBlockInfo: { type: Function, default: () => [] },
});

const emit = defineEmits(['month-click', 'day-click']);

const { proxy } = getCurrentInstance();
const t = proxy.$t.bind(proxy);

const monthLabel = computed(() => t(`AGENDA.MONTHS.${props.monthKey}`));

const dayShortHeaders = computed(() => [
  t('AGENDA.DAYS.SUN').charAt(0),
  t('AGENDA.DAYS.MON').charAt(0),
  t('AGENDA.DAYS.TUE').charAt(0),
  t('AGENDA.DAYS.WED').charAt(0),
  t('AGENDA.DAYS.THU').charAt(0),
  t('AGENDA.DAYS.FRI').charAt(0),
  t('AGENDA.DAYS.SAT').charAt(0),
]);

function pad2(n) {
  return String(n).padStart(2, '0');
}

// Cells do mês: para cada dia, dateKey 'YYYY-MM-DD'. Spacers antes do dia 1
// E depois do último — sempre 42 células (6 linhas × 7 colunas) pra todos
// os meses, garantindo cards de altura idêntica no grid anual.
const CELLS_PER_MONTH = 42;

const cells = computed(() => {
  const result = [];
  const firstDow = new Date(props.year, props.monthIndex, 1).getDay();
  const daysInMonth = new Date(props.year, props.monthIndex + 1, 0).getDate();

  for (let i = 0; i < firstDow; i += 1) {
    result.push(null);
  }
  for (let d = 1; d <= daysInMonth; d += 1) {
    const dateKey = `${props.year}-${pad2(props.monthIndex + 1)}-${pad2(d)}`;
    result.push({
      day: d,
      dateKey,
      isToday:
        props.today.year === props.year &&
        props.today.month === props.monthIndex &&
        props.today.day === d,
    });
  }
  // Trailing padding até completar 42 — mantém a altura do card constante
  // independentemente de o mês ter 28/29/30/31 dias e do dia 1 cair em
  // qualquer dia da semana. Sem isso, fevereiro fica visivelmente mais
  // baixo que março/maio.
  while (result.length < CELLS_PER_MONTH) {
    result.push(null);
  }
  return result;
});

function onCellClick(cell) {
  if (!cell) return;
  emit('day-click', {
    year: props.year,
    month: props.monthIndex,
    day: cell.day,
  });
}

// Retorna apenas os blocos relevantes (feriado/exceção/fechado).
// `getDayBlockInfo` recebe `dayObj` no formato { year, month, day }.
// Filtramos blocos "passados" pra evitar marcar visualmente todo o
// histórico — Year View também serve pra ler retrospectiva, então
// um feriado que já passou não precisa de visual de "bloqueado".
function getBlocksForCell(cell) {
  if (!cell) return [];
  const dayObj = { year: props.year, month: props.monthIndex, day: cell.day };
  const all = props.getDayBlockInfo(dayObj) || [];
  return all.filter(b => !b.isPast);
}


function onTitleClick() {
  emit('month-click');
}
</script>

<template>
  <article class="ymc" role="listitem">
    <header class="ymc__header">
      <button
        type="button"
        class="ymc__title"
        :aria-label="t('AGENDA.YEAR.OPEN_MONTH') + ' ' + monthLabel"
        @click="onTitleClick"
      >
        {{ monthLabel }}
      </button>
      <span class="ymc__total" :aria-label="`${total} ` + t('AGENDA.YEAR.APPOINTMENTS')">
        {{ total }}
      </span>
    </header>

    <div class="ymc__dow-row" aria-hidden="true">
      <span
        v-for="(label, idx) in dayShortHeaders"
        :key="idx"
        class="ymc__dow"
      >
        {{ label }}
      </span>
    </div>

    <div class="ymc__grid">
      <template v-for="(cell, idx) in cells" :key="idx">
        <span v-if="!cell" class="ymc__spacer" aria-hidden="true" />
        <YearDayCell
          v-else
          :day="cell.day"
          :date-key="cell.dateKey"
          :bucket="colorBucket(cell.dateKey)"
          :stats="getDay(cell.dateKey)"
          :is-today="cell.isToday"
          :block-info="getBlocksForCell(cell)"
          @click="onCellClick(cell)"
        />
      </template>
    </div>
  </article>
</template>
