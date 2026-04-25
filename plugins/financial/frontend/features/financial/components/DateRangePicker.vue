<script setup>
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';

const props = defineProps({
  modelValue: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:modelValue']);

const open = ref(false);
const pickerRef = ref(null);

const WEEKDAYS = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
const MONTH_NAMES = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

const viewYear = ref(new Date().getFullYear());
const viewMonth = ref(new Date().getMonth());

// Phase: 0 = empty, 1 = first date picked (waiting second), 2 = range complete
const phase = ref(0);
const rangeStart = ref('');
const rangeEnd = ref('');
const hoverDate = ref('');

const today = new Date();
const todayStr = [
  today.getFullYear(),
  String(today.getMonth() + 1).padStart(2, '0'),
  String(today.getDate()).padStart(2, '0'),
].join('-');

function syncFromModel() {
  if (props.modelValue && props.modelValue.length > 0) {
    rangeStart.value = props.modelValue[0] || '';
    rangeEnd.value = props.modelValue[1] || props.modelValue[0] || '';
    phase.value = 2;
    if (rangeStart.value) {
      const [y, m] = rangeStart.value.split('-');
      viewYear.value = parseInt(y, 10);
      viewMonth.value = parseInt(m, 10) - 1;
    }
  } else {
    rangeStart.value = '';
    rangeEnd.value = '';
    phase.value = 0;
    viewYear.value = new Date().getFullYear();
    viewMonth.value = new Date().getMonth();
  }
}

watch(() => props.modelValue, syncFromModel, { immediate: true });

function shortMonth(m) {
  return MONTH_NAMES[parseInt(m, 10) - 1].slice(0, 3).toLowerCase();
}

const displayLabel = computed(() => {
  if (!props.modelValue || props.modelValue.length === 0)
    return 'Selecionar período';
  const [y1, m1, d1] = props.modelValue[0].split('-');
  if (!props.modelValue[1] || props.modelValue[0] === props.modelValue[1]) {
    return `${d1} ${shortMonth(m1)}. ${y1}`;
  }
  const [y2, m2, d2] = props.modelValue[1].split('-');
  const sameYear = y1 === y2;
  const isCurrentYear = y1 === String(new Date().getFullYear());
  if (sameYear && isCurrentYear) {
    return `${d1} ${shortMonth(m1)} - ${d2} ${shortMonth(m2)}`;
  }
  if (sameYear) {
    return `${d1} ${shortMonth(m1)} - ${d2} ${shortMonth(m2)} ${y1}`;
  }
  return `${d1} ${shortMonth(m1)} ${y1} - ${d2} ${shortMonth(m2)} ${y2}`;
});

const viewMonthLabel = computed(
  () => `${MONTH_NAMES[viewMonth.value]} ${viewYear.value}`
);

const calendarDays = computed(() => {
  const y = viewYear.value;
  const m = viewMonth.value;
  const firstDay = new Date(y, m, 1).getDay();
  const daysInMonth = new Date(y, m + 1, 0).getDate();
  const daysInPrev = new Date(y, m, 0).getDate();
  const cells = [];
  for (let i = firstDay - 1; i >= 0; i -= 1) {
    cells.push({ day: daysInPrev - i, current: false });
  }
  for (let d = 1; d <= daysInMonth; d += 1) {
    cells.push({ day: d, current: true });
  }
  const remaining = 42 - cells.length;
  for (let d = 1; d <= remaining; d += 1) {
    cells.push({ day: d, current: false });
  }
  return cells;
});

function cellDateStr(cell) {
  if (!cell.current) return '';
  const mm = String(viewMonth.value + 1).padStart(2, '0');
  const dd = String(cell.day).padStart(2, '0');
  return `${viewYear.value}-${mm}-${dd}`;
}

// Returns { min, max } for the current selection (or preview during phase 1)
function getRange() {
  const start = rangeStart.value;
  if (!start) return null;
  const end =
    phase.value === 1 && hoverDate.value ? hoverDate.value : rangeEnd.value;
  if (!end) return { min: start, max: start };
  const t1 = new Date(start).getTime();
  const t2 = new Date(end).getTime();
  return t1 <= t2 ? { min: start, max: end } : { min: end, max: start };
}

function isInRange(cell) {
  if (!cell.current) return false;
  const range = getRange();
  if (!range) return false;
  const d = new Date(cellDateStr(cell)).getTime();
  return (
    d >= new Date(range.min).getTime() && d <= new Date(range.max).getTime()
  );
}

function isEdge(cell) {
  if (!cell.current) return false;
  const range = getRange();
  if (!range) return false;
  const d = cellDateStr(cell);
  return d === range.min || d === range.max;
}

function isToday(cell) {
  return cell.current && cellDateStr(cell) === todayStr;
}

function onHover(cell) {
  if (phase.value === 1 && cell.current) {
    hoverDate.value = cellDateStr(cell);
  }
}

function selectDay(cell) {
  if (!cell.current) return;
  const d = cellDateStr(cell);
  if (phase.value === 0 || phase.value === 2) {
    rangeStart.value = d;
    rangeEnd.value = '';
    hoverDate.value = '';
    phase.value = 1;
  } else {
    rangeEnd.value = d;
    const t1 = new Date(rangeStart.value).getTime();
    const t2 = new Date(rangeEnd.value).getTime();
    const sorted =
      t1 <= t2
        ? [rangeStart.value, rangeEnd.value]
        : [rangeEnd.value, rangeStart.value];
    emit('update:modelValue', sorted);
    phase.value = 2;
    open.value = false;
  }
}

function prevMonth() {
  if (viewMonth.value === 0) {
    viewMonth.value = 11;
    viewYear.value -= 1;
  } else {
    viewMonth.value -= 1;
  }
}

function nextMonth() {
  if (viewMonth.value === 11) {
    viewMonth.value = 0;
    viewYear.value += 1;
  } else {
    viewMonth.value += 1;
  }
}

function toggle() {
  if (!open.value) syncFromModel();
  open.value = !open.value;
}

function setToday() {
  emit('update:modelValue', [todayStr, todayStr]);
  open.value = false;
}

function clearSelection() {
  emit('update:modelValue', []);
  open.value = false;
}

function onClickOutside(e) {
  if (pickerRef.value && !pickerRef.value.contains(e.target)) {
    open.value = false;
  }
}

onMounted(() => document.addEventListener('mousedown', onClickOutside));
onUnmounted(() => document.removeEventListener('mousedown', onClickOutside));
</script>

<template>
  <div ref="pickerRef" class="drp-wrap">
    <!-- Trigger button -->
    <button class="dre-mp__trigger" @click="toggle">
      <span class="i-lucide-calendar w-4 h-4 dre-mp__icon" />
      <span class="dre-mp__label">{{ displayLabel }}</span>
      <span
        v-if="modelValue.length > 0"
        class="i-lucide-x w-3 h-3 ml-1 text-slate-400 hover:text-slate-600 cursor-pointer"
        @click.stop="clearSelection"
      />
      <span
        v-else
        class="i-lucide-chevron-down w-3.5 h-3.5 dre-mp__chevron"
        :class="{ 'dre-mp__chevron--open': open }"
      />
    </button>

    <!-- Dropdown -->
    <Transition name="dre-mp-drop">
      <div v-if="open" class="drp-dropdown">
        <!-- Nav -->
        <div class="drp-nav">
          <button class="dre-mp__year-btn" @click="prevMonth">
            <span class="i-lucide-chevron-left w-4 h-4" />
          </button>
          <span class="dre-dp__nav-label">{{ viewMonthLabel }}</span>
          <button class="dre-mp__year-btn" @click="nextMonth">
            <span class="i-lucide-chevron-right w-4 h-4" />
          </button>
        </div>

        <!-- Weekdays header -->
        <div class="drp-weekdays">
          <span v-for="(wd, i) in WEEKDAYS" :key="i" class="drp-wd">{{
            wd
          }}</span>
        </div>

        <!-- Days grid -->
        <div class="drp-grid">
          <button
            v-for="(cell, i) in calendarDays"
            :key="i"
            class="drp-day"
            :class="{
              'drp-day--other': !cell.current,
              'drp-day--edge': isEdge(cell),
              'drp-day--in-range': isInRange(cell) && !isEdge(cell),
              'drp-day--today': isToday(cell) && !isInRange(cell),
            }"
            :disabled="!cell.current"
            @click="selectDay(cell)"
            @mouseenter="onHover(cell)"
          >
            {{ cell.day }}
          </button>
        </div>

        <!-- Footer -->
        <div class="drp-footer">
          <button class="drp-footer-today" @click="setToday">Hoje</button>
          <button class="drp-footer-clear" @click="clearSelection">
            Limpar
          </button>
        </div>
      </div>
    </Transition>
  </div>
</template>

<style scoped>
.drp-wrap {
  position: relative;
  display: inline-flex;
}

.drp-dropdown {
  position: absolute;
  top: calc(100% + 6px);
  left: 0;
  z-index: 50;
  width: 320px;
  padding: 14px 16px 0;
  background: #fff;
  border: 1px solid #e2e8f0;
  border-radius: 12px;
  box-shadow:
    0 8px 24px rgba(0, 0, 0, 0.12),
    0 2px 8px rgba(0, 0, 0, 0.06);
}

.drp-nav {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 10px;
}

.drp-weekdays {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  margin-bottom: 4px;
}

.drp-wd {
  text-align: center;
  font-size: 11px;
  font-weight: 600;
  color: #94a3b8;
  text-transform: uppercase;
  padding: 4px 0;
}

.drp-grid {
  display: grid;
  grid-template-columns: repeat(7, 1fr);
  gap: 2px;
}

.drp-day {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  aspect-ratio: 1;
  border: none;
  border-radius: 6px;
  background: transparent;
  color: #334155;
  font-size: 13px;
  cursor: pointer;
  transition: all 0.12s;
}

.drp-day:hover:not(:disabled):not(.drp-day--edge):not(.drp-day--in-range) {
  background: #f1f5f9;
}

.drp-day--other {
  color: #cbd5e1;
  pointer-events: none;
}

.drp-day--today {
  font-weight: 700;
  color: #3b82f6;
}

/* Edge = start or end: solid blue */
.drp-day--edge {
  background: #2563eb !important;
  color: #fff !important;
  font-weight: 600;
  border-radius: 6px;
}

/* In-range (between start and end): very light blue */
.drp-day--in-range {
  background: #dbeafe;
  color: #3b82f6;
  font-weight: 500;
  border-radius: 0;
}

/* Make edges have full border radius even when inside a range */
.drp-day--edge {
  border-radius: 6px !important;
}

.drp-footer {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-top: 12px;
  padding: 10px 0 12px;
  border-top: 1px solid #f1f5f9;
}

.drp-footer-today {
  border: none;
  background: transparent;
  color: #475569;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  padding: 4px 8px;
  border-radius: 6px;
  transition: color 0.15s;
}

.drp-footer-today:hover {
  color: #0f172a;
}

.drp-footer-clear {
  border: none;
  background: #2563eb;
  color: #fff;
  font-size: 13px;
  font-weight: 600;
  cursor: pointer;
  padding: 6px 14px;
  border-radius: 6px;
  transition: background 0.15s;
}

.drp-footer-clear:hover {
  background: #1d4ed8;
}
</style>
