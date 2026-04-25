<template>
  <div class="modern-select-wrapper" ref="wrapperRef">
    <!-- Trigger Button -->
    <button
      type="button"
      :class="['modern-select-trigger', { 'is-open': isOpen, 'is-disabled': disabled }, $attrs.class]"
      :style="$attrs.style"
      @click="toggleMenu"
      :disabled="disabled"
    >
      <span class="modern-select-label">{{ selectedLabel }}</span>
      <i class="i-lucide-chevron-down modern-select-icon" :class="{ 'rotate-180': isOpen }" />
    </button>

    <!-- Dropdown List Teleported to Body -->
    <teleport to="body">
      <div
        v-if="isOpen"
        class="modern-select-dropdown"
        :style="dropdownStyle"
      >
        <div class="modern-select-options">
          <div
            v-for="opt in options"
            :key="opt.value"
            class="modern-select-item"
            :class="{ 'is-selected': opt.value === modelValue }"
            @click="selectOption(opt)"
          >
            <span class="truncate">{{ opt.label }}</span>
            <i v-if="opt.value === modelValue" class="i-lucide-check ml-auto size-[14px]" />
          </div>
        </div>
      </div>
    </teleport>
  </div>
</template>

<script setup>
import { ref, computed, nextTick, onMounted, onUnmounted } from 'vue';

defineOptions({
  inheritAttrs: false
});

const props = defineProps({
  modelValue: { type: [String, Number, Boolean, Object], default: null },
  options: { type: Array, required: true }, // [{ label: 'Name', value: 1 }, ...]
  placeholder: { type: String, default: 'Selecione...' },
  disabled: { type: Boolean, default: false }
});

const emit = defineEmits(['update:modelValue', 'change']);

const isOpen = ref(false);
const wrapperRef = ref(null);
const dropdownStyle = ref({});

const selectedLabel = computed(() => {
  const selected = props.options.find(o => o.value === props.modelValue);
  return selected ? selected.label : props.placeholder;
});

const calculatePosition = () => {
  if (!wrapperRef.value) return;
  const rect = wrapperRef.value.getBoundingClientRect();
  
  // Calculate if there's enough space below, otherwise pop up
  const spaceBelow = window.innerHeight - rect.bottom;
  const spaceAbove = rect.top;
  const menuHeight = 250; // estimated max height of dropdown
  
  if (spaceBelow < menuHeight && spaceAbove > spaceBelow) {
    // Pop UP
    dropdownStyle.value = {
      bottom: `${window.innerHeight - rect.top + 4}px`,
      left: `${rect.left}px`,
      width: `${rect.width}px`
    };
  } else {
    // Pop DOWN
    dropdownStyle.value = {
      top: `${rect.bottom + 4}px`,
      left: `${rect.left}px`,
      width: `${rect.width}px`
    };
  }
};

const handleOutsideClick = (e) => {
  if (!isOpen.value) return;
  
  // If clicked inside the wrapper, ignore (toggleMenu handles it)
  if (wrapperRef.value && wrapperRef.value.contains(e.target)) return;
  
  // If clicked inside the dropdown teleported element
  const dropdownEls = document.querySelectorAll('.modern-select-dropdown');
  let clickedInsideDropdown = false;
  dropdownEls.forEach(el => {
    if (el.contains(e.target)) clickedInsideDropdown = true;
  });
  
  if (!clickedInsideDropdown) {
    closeMenu();
  }
};

const toggleMenu = () => {
  isOpen.value = !isOpen.value;
  if (isOpen.value) {
    nextTick(() => {
      calculatePosition();
      // Add event listeners on next tick so the current click doesn't trigger outside click immediately
      window.addEventListener('click', handleOutsideClick);
      window.addEventListener('scroll', calculatePosition, true);
      window.addEventListener('resize', calculatePosition);
    });
  } else {
    removeListeners();
  }
};

const closeMenu = () => {
  if (isOpen.value) {
    isOpen.value = false;
    removeListeners();
  }
};

const removeListeners = () => {
  window.removeEventListener('click', handleOutsideClick);
  window.removeEventListener('scroll', calculatePosition, true);
  window.removeEventListener('resize', calculatePosition);
};

const selectOption = (opt) => {
  emit('update:modelValue', opt.value);
  emit('change', opt.value);
  closeMenu();
};

onMounted(() => {
  // Just in case component unmounts while open
});

onUnmounted(() => {
  removeListeners();
});
</script>

<style scoped>
.modern-select-wrapper {
  position: relative;
  /* Allow passing inline width bindings transparently if container sets it */
  width: 100%;
}

/* Trigger Button */
.modern-select-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 8px 12px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-family: inherit;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
  outline: none;
}
.modern-select-trigger:hover:not(.is-disabled) {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-6));
}
.modern-select-trigger.is-open {
  border-color: rgb(var(--blue-9));
  box-shadow: 0 0 0 1px rgb(var(--blue-9));
}
.modern-select-trigger.is-disabled {
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-9));
  cursor: not-allowed;
  box-shadow: none;
  opacity: 0.6;
}

.modern-select-label {
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.modern-select-icon {
  font-size: 16px;
  color: rgb(var(--slate-8));
  transition: transform 0.2s;
  flex-shrink: 0;
  margin-left: 8px;
}

/* Dropdown Menu */
.modern-select-dropdown {
  position: fixed;
  z-index: 10005; /* Above modals */
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  box-shadow: 0 10px 25px -5px rgba(0, 0, 0, 0.2), 0 8px 10px -6px rgba(0, 0, 0, 0.1);
  overflow: hidden;
}

.modern-select-options {
  max-height: 250px;
  overflow-y: auto;
  display: flex;
  flex-direction: column;
  padding: 4px;
}

.modern-select-item {
  display: flex;
  align-items: center;
  padding: 8px 12px;
  border-radius: 6px;
  @apply text-sm;
  color: rgb(var(--slate-11));
  cursor: pointer;
  transition: all 0.15s ease;
}
.modern-select-item:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}

.modern-select-item.is-selected {
  background: rgba(59, 130, 246, 0.12);
  color: rgb(var(--blue-10));
  font-weight: 600;
}
</style>
