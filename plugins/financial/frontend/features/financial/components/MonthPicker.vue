<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const open = ref(false);
const pickerRef = ref(null);

const months = [
  'Jan',
  'Fev',
  'Mar',
  'Abr',
  'Mai',
  'Jun',
  'Jul',
  'Ago',
  'Set',
  'Out',
  'Nov',
  'Dez',
];

const selectedYear = ref(new Date().getFullYear());
const selectedMonth = ref(new Date().getMonth());

function syncFromModel() {
  if (props.modelValue) {
    const [y, m] = props.modelValue.split('-');
    selectedYear.value = parseInt(y, 10);
    selectedMonth.value = parseInt(m, 10) - 1;
  }
}

syncFromModel();

const displayLabel = computed(() => {
  const m = months[selectedMonth.value];
  return `${m}. ${selectedYear.value}`;
});

function prevYear() {
  selectedYear.value -= 1;
}

function nextYear() {
  selectedYear.value += 1;
}

function selectMonth(idx) {
  selectedMonth.value = idx;
  const mm = String(idx + 1).padStart(2, '0');
  emit('update:modelValue', `${selectedYear.value}-${mm}`);
  open.value = false;
}

function toggle() {
  syncFromModel();
  open.value = !open.value;
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
  <div ref="pickerRef" class="dre-mp">
    <button class="dre-mp__trigger" @click="toggle">
      <span class="i-lucide-calendar w-4 h-4 dre-mp__icon" />
      <span class="dre-mp__label">{{ displayLabel }}</span>
      <span
        class="i-lucide-chevron-down w-3.5 h-3.5 dre-mp__chevron"
        :class="{ 'dre-mp__chevron--open': open }"
      />
    </button>

    <Transition name="dre-mp-drop">
      <div v-if="open" class="dre-mp__dropdown">
        <div class="dre-mp__year-nav">
          <button class="dre-mp__year-btn" @click="prevYear">
            <span class="i-lucide-chevron-left w-4 h-4" />
          </button>
          <span class="dre-mp__year-label">{{ selectedYear }}</span>
          <button class="dre-mp__year-btn" @click="nextYear">
            <span class="i-lucide-chevron-right w-4 h-4" />
          </button>
        </div>
        <div class="dre-mp__grid">
          <button
            v-for="(m, idx) in months"
            :key="idx"
            class="dre-mp__month"
            :class="{ 'dre-mp__month--active': idx === selectedMonth }"
            @click="selectMonth(idx)"
          >
            {{ m }}
          </button>
        </div>
      </div>
    </Transition>
  </div>
</template>
