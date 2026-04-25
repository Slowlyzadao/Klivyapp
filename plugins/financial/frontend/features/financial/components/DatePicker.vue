<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
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

function syncFromModel() {
  if (props.modelValue) {
    const [y, m] = props.modelValue.split('-');
    viewYear.value = parseInt(y, 10);
    viewMonth.value = parseInt(m, 10) - 1;
  }
}

syncFromModel();

const displayLabel = computed(() => {
  if (!props.modelValue) return 'Selecionar data';
  const [y, m, d] = props.modelValue.split('-');
  const monthShort = MONTH_NAMES[parseInt(m, 10) - 1].slice(0, 3).toLowerCase();
  return `${d} ${monthShort}. ${y}`;
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

const today = new Date();
const todayStr = `${today.getFullYear()}-${String(today.getMonth() + 1).padStart(2, '0')}-${String(today.getDate()).padStart(2, '0')}`;

function cellDateStr(cell) {
  if (!cell.current) return '';
  const mm = String(viewMonth.value + 1).padStart(2, '0');
  const dd = String(cell.day).padStart(2, '0');
  return `${viewYear.value}-${mm}-${dd}`;
}

function isSelected(cell) {
  return cell.current && cellDateStr(cell) === props.modelValue;
}

function isToday(cell) {
  return cell.current && cellDateStr(cell) === todayStr;
}

function selectDay(cell) {
  if (!cell.current) return;
  emit('update:modelValue', cellDateStr(cell));
  open.value = false;
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
  syncFromModel();
  open.value = !open.value;
}

function setToday() {
  emit('update:modelValue', todayStr);
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
  <div ref="pickerRef" class="dre-dp">
    <button class="dre-mp__trigger" @click="toggle">
      <span class="i-lucide-calendar w-4 h-4 dre-mp__icon" />
      <span class="dre-mp__label">{{ displayLabel }}</span>
      <span
        class="i-lucide-chevron-down w-3.5 h-3.5 dre-mp__chevron"
        :class="{ 'dre-mp__chevron--open': open }"
      />
    </button>

    <Transition name="dre-mp-drop">
      <div v-if="open" class="dre-dp__dropdown">
        <div class="dre-dp__nav">
          <button class="dre-mp__year-btn" @click="prevMonth">
            <span class="i-lucide-chevron-left w-4 h-4" />
          </button>
          <span class="dre-dp__nav-label">{{ viewMonthLabel }}</span>
          <button class="dre-mp__year-btn" @click="nextMonth">
            <span class="i-lucide-chevron-right w-4 h-4" />
          </button>
        </div>
        <div class="dre-dp__weekdays">
          <span v-for="(wd, i) in WEEKDAYS" :key="i" class="dre-dp__wd">
            {{ wd }}
          </span>
        </div>
        <div class="dre-dp__grid">
          <button
            v-for="(cell, i) in calendarDays"
            :key="i"
            class="dre-dp__day"
            :class="{
              'dre-dp__day--other': !cell.current,
              'dre-dp__day--selected': isSelected(cell),
              'dre-dp__day--today': isToday(cell) && !isSelected(cell),
            }"
            :disabled="!cell.current"
            @click="selectDay(cell)"
          >
            {{ cell.day }}
          </button>
        </div>
        <div class="dre-dp__footer">
          <button class="dre-dp__footer-btn" @click="setToday">Hoje</button>
        </div>
      </div>
    </Transition>
  </div>
</template>
