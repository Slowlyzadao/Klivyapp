<script setup>
import {
  ref,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  nextTick,
} from 'vue';

const props = defineProps({
  modelValue: {
    type: [String, Number],
    default: '',
  },
  options: {
    type: Array,
    required: true,
    // Formato esperado: [{ label: 'Foo', value: 'foo' }]
  },
  label: {
    type: String,
    default: '',
  },
  placeholder: {
    type: String,
    default: 'Selecione uma opção',
  },
  required: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue', 'change']);

// Refs
const triggerRef = ref(null);
const dropdownRef = ref(null);

const isOpen = ref(false);
const positionStyle = ref({});
const focusedIndex = ref(-1);

// Composables / Computed
const selectedLabel = computed(() => {
  const selected = props.options.find(opt => opt.value === props.modelValue);
  return selected ? selected.label : props.placeholder;
});

// Lógica de fechamento via click outside
const closeIfOutside = e => {
  if (!isOpen.value) return;
  if (triggerRef.value && triggerRef.value.contains(e.target)) return;
  if (dropdownRef.value && dropdownRef.value.contains(e.target)) return;
  close();
};

const handleScroll = () => {
  if (isOpen.value) close();
};

const handleResize = () => {
  if (isOpen.value) close();
};

// Lifecycle
onMounted(() => {
  document.addEventListener('mousedown', closeIfOutside);
  // Usa capture 'true' para pegar scrolls de modais internos e do document body
  document.addEventListener('scroll', handleScroll, true);
  window.addEventListener('resize', handleResize);
});

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', closeIfOutside);
  document.removeEventListener('scroll', handleScroll, true);
  window.removeEventListener('resize', handleResize);
});

// Ações
const toggle = async () => {
  if (isOpen.value) {
    close();
  } else {
    await open();
  }
};

const open = async () => {
  isOpen.value = true;
  focusedIndex.value = props.options.findIndex(
    o => o.value === props.modelValue
  );
  if (focusedIndex.value === -1) focusedIndex.value = 0;

  await calculatePosition();
};

const close = () => {
  isOpen.value = false;
  focusedIndex.value = -1;
};

const selectOption = option => {
  emit('update:modelValue', option.value);
  emit('change', option.value);
  close();
  triggerRef.value?.focus();
};

const calculatePosition = async () => {
  await nextTick();
  if (!triggerRef.value) return;

  const rect = triggerRef.value.getBoundingClientRect();
  const windowHeight = window.innerHeight;

  // Usa a metade da tela como âncora absoluta para decidir a inversão,
  // ignorando o offsetHeight falho da transição.
  const showUpwards = rect.bottom > windowHeight / 2;

  if (showUpwards) {
    positionStyle.value = {
      position: 'fixed',
      left: `${rect.left}px`,
      width: `${rect.width}px`,
      bottom: `${windowHeight - rect.top + 4}px`,
      zIndex: 999999, // Superior a qualquer modal
    };
  } else {
    positionStyle.value = {
      position: 'fixed',
      left: `${rect.left}px`,
      width: `${rect.width}px`,
      top: `${rect.bottom + 4}px`,
      zIndex: 999999,
    };
  }
};

// Teclado
const handleKeydown = e => {
  if (!isOpen.value) {
    if (['Enter', 'Space', 'ArrowDown', 'ArrowUp'].includes(e.code)) {
      e.preventDefault();
      open();
    }
    return;
  }

  // Com dropdown aberto
  switch (e.code) {
    case 'Escape':
      e.preventDefault();
      close();
      triggerRef.value?.focus();
      break;
    case 'ArrowDown':
      e.preventDefault();
      focusedIndex.value =
        (focusedIndex.value + 1) % props.options.length;
      break;
    case 'ArrowUp':
      e.preventDefault();
      focusedIndex.value =
        (focusedIndex.value - 1 + props.options.length) % props.options.length;
      break;
    case 'Enter':
    case 'Space':
      e.preventDefault();
      if (
        focusedIndex.value >= 0 &&
        focusedIndex.value < props.options.length
      ) {
        selectOption(props.options[focusedIndex.value]);
      }
      break;
    case 'Tab':
      close();
      break;
    default:
      break;
  }
};
</script>

<template>
  <div class="npm-field npm-field--relative w-full">
    <label v-if="label" class="npm-label" @click="triggerRef?.focus()">
      {{ label }} <span v-if="required" class="npm-required">*</span>
    </label>

    <button
      ref="triggerRef"
      type="button"
      class="base-select-trigger"
      :class="{ 'base-select-trigger--active': isOpen }"
      aria-haspopup="listbox"
      :aria-expanded="isOpen"
      @click="toggle"
      @keydown="handleKeydown"
    >
      <span class="truncate block text-left" :class="{ 'opacity-50 text-slate-500': !modelValue }">
        {{ selectedLabel }}
      </span>
      <i class="chevron-icon" />
    </button>

    <Teleport to="body">
      <Transition
        enter-active-class="transition duration-150 ease-out"
        enter-from-class="opacity-0 scale-95 -translate-y-2"
        enter-to-class="opacity-100 scale-100 translate-y-0"
        leave-active-class="transition duration-100 ease-in"
        leave-from-class="opacity-100 scale-100 translate-y-0"
        leave-to-class="opacity-0 scale-95"
      >
        <div
          v-if="isOpen"
          ref="dropdownRef"
          :style="positionStyle"
          class="base-select-dropdown"
          role="listbox"
          tabindex="-1"
          @keydown.prevent
        >
          <ul class="base-select-list">
            <li
              v-for="(opt, index) in options"
              :key="opt.value"
              role="option"
              :aria-selected="modelValue === opt.value"
              class="base-select-item"
              :class="{
                'base-select-item--active': index === focusedIndex,
                'base-select-item--selected': modelValue === opt.value,
              }"
              @mouseenter="focusedIndex = index"
              @mousedown.prevent="selectOption(opt)"
            >
              <span
                class="flex-1 truncate"
                :class="modelValue === opt.value ? 'font-semibold' : 'font-medium'"
              >
                {{ opt.label }}
              </span>
              <i v-show="modelValue === opt.value" class="i-lucide-check w-4 h-4 shrink-0 check-icon" />
            </li>
          </ul>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.npm-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.npm-label {
  font-size: 12px;
  font-weight: 600;
  color: rgb(var(--slate-11));
}

.npm-required {
  color: #f87171;
}

.base-select-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  box-sizing: border-box;
  padding: 0.375rem 0.75rem;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 0.75rem;
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-12));
  font-size: 0.875rem;
  min-height: 2.5rem;
  font-family: inherit;
  outline: none;
  cursor: pointer;
  transition: all 0.2s ease-in-out;
}

.base-select-trigger:focus-visible,
.base-select-trigger--active {
  border-color: rgba(var(--blue-9), 0.5);
  box-shadow: 0 0 0 1px rgba(var(--blue-9), 0.5);
  background: rgb(var(--slate-1));
}

.chevron-icon {
  display: block;
  width: 1.25rem;
  height: 1.25rem;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' fill='none' viewBox='0 0 24 24' stroke-width='1.5' stroke='%2394a3b8'%3E%3Cpath stroke-linecap='round' stroke-linejoin='round' d='M8.25 15 12 18.75 15.75 15m-7.5-6L12 5.25 15.75 9' /%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: center;
  background-size: contain;
  flex-shrink: 0;
}

.base-select-dropdown {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  box-shadow: 0 8px 24px rgba(0, 0, 0, 0.3);
  overflow: hidden;
  max-height: 220px;
  display: flex;
  flex-direction: column;
}

.base-select-list {
  list-style: none;
  margin: 0;
  padding: 4px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.base-select-item {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 8px 12px;
  border-radius: 6px;
  cursor: pointer;
  font-size: 0.875rem;
  color: rgb(var(--slate-12));
  transition: background 0.15s;
}

.base-select-item--active {
  background: rgb(var(--slate-3));
}

.base-select-item--selected {
  color: rgba(var(--blue-600), 1);
  background: rgba(var(--blue-600), 0.1);
}
@media (prefers-color-scheme: dark) {
  .base-select-item--selected {
    color: rgba(var(--blue-400), 1);
    background: rgba(var(--blue-500), 0.15);
  }
}

.base-select-item:hover:not(.base-select-item--selected) {
  background: rgb(var(--slate-3));
}

.check-icon {
  color: inherit;
}
</style>
