<script setup>
import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  watch,
  nextTick,
} from 'vue';

// Modeled after the AgendaEventModal "Novo Evento" custom-select. Reusable
// across the dashboard — keeps the same visual identity (rounded trigger,
// animated chevron, popover panel with optional search and clear).
//
// The dropdown is teleported to <body> with position: fixed so it escapes
// any ancestor with `overflow: hidden` (e.g. the patient form's collapsible
// sections). Position is recalculated on open + on scroll/resize while open.

const props = defineProps({
  modelValue: {
    type: [String, Number, Boolean, Object],
    default: '',
  },
  // Accepts ['feminino', 'masculino'] OR [{ value, label, color, hint, disabled }]
  options: {
    type: Array,
    default: () => [],
  },
  placeholder: { type: String, default: 'Selecione' },
  searchable: { type: Boolean, default: false },
  searchPlaceholder: { type: String, default: 'Buscar...' },
  clearable: { type: Boolean, default: false },
  clearLabel: { type: String, default: 'Limpar seleção' },
  noOptionsText: { type: String, default: 'Sem resultados' },
  disabled: { type: Boolean, default: false },
  // When true, shows the search field only if there are 6+ options. Avoids
  // noise on short lists (sex, marital status) but keeps it for long ones.
  autoSearchable: { type: Boolean, default: false },
  // Dropdown max height in px (matches max-height in CSS by default).
  maxHeight: { type: Number, default: 240 },
});

const emit = defineEmits(['update:modelValue', 'change']);

const open = ref(false);
const search = ref('');
const triggerRef = ref(null);
const dropdownRef = ref(null);
const searchInputRef = ref(null);
const dropdownStyle = ref({});
const dropDirection = ref('down'); // 'down' | 'up'

const normalizedOptions = computed(() =>
  (props.options || [])
    .map(opt => {
      if (opt === null || opt === undefined) return null;
      if (typeof opt === 'object') return opt;
      return { value: opt, label: String(opt) };
    })
    .filter(Boolean)
);

const showSearch = computed(() => {
  if (props.searchable) return true;
  if (props.autoSearchable && normalizedOptions.value.length >= 6) return true;
  return false;
});

// Busca interna do dropdown: casa em `label`, `badge` e `hint`. Permite
// achar opções tanto por nome quanto por ID/identificador exibido como badge.
const filteredOptions = computed(() => {
  if (!search.value) return normalizedOptions.value;
  const q = search.value.toLowerCase().trim();
  return normalizedOptions.value.filter(o => {
    const haystack = [o.label, o.badge, o.hint, o.value]
      .filter(v => v !== null && v !== undefined && v !== '')
      .map(String)
      .join(' ')
      .toLowerCase();
    return haystack.includes(q);
  });
});

const selected = computed(
  () => normalizedOptions.value.find(o => o.value === props.modelValue) || null
);

const hasSelection = computed(
  () =>
    props.modelValue !== '' &&
    props.modelValue !== null &&
    props.modelValue !== undefined
);

const updatePosition = () => {
  if (!triggerRef.value) return;
  const rect = triggerRef.value.getBoundingClientRect();
  const viewportH = window.innerHeight;
  const spaceBelow = viewportH - rect.bottom;
  const spaceAbove = rect.top;
  const desiredHeight = props.maxHeight + 8; // dropdown + small gap

  // Prefer down, but flip up if there isn't enough room and there's more above.
  const goesUp = spaceBelow < desiredHeight && spaceAbove > spaceBelow;
  dropDirection.value = goesUp ? 'up' : 'down';

  const style = {
    position: 'fixed',
    left: `${rect.left}px`,
    width: `${rect.width}px`,
    // Acima dos modais do Chatwoot (.modal-mask z-[9990]) e qualquer outro
    // overlay. Inline overrides class CSS, então precisa estar aqui.
    zIndex: 100000,
  };

  if (goesUp) {
    style.bottom = `${viewportH - rect.top + 4}px`;
    style.maxHeight = `${Math.min(props.maxHeight, spaceAbove - 12)}px`;
  } else {
    style.top = `${rect.bottom + 4}px`;
    style.maxHeight = `${Math.min(props.maxHeight, spaceBelow - 12)}px`;
  }

  dropdownStyle.value = style;
};

const toggle = async () => {
  if (props.disabled) return;
  if (open.value) {
    close();
    return;
  }
  // Calcula posição ANTES de marcar open=true para que o primeiro paint do
  // dropdown já saia no lugar certo (sem o "flash" de canto na 1ª abertura).
  updatePosition();
  open.value = true;
  await nextTick();
  // Reposiciona pós-render caso layout tenha shiftado (ex: scroll travou).
  updatePosition();
  if (showSearch.value) searchInputRef.value?.focus();
};

const close = () => {
  open.value = false;
  search.value = '';
};

const selectOption = option => {
  if (option.disabled) return;
  emit('update:modelValue', option.value);
  emit('change', option.value);
  close();
};

const clear = () => {
  emit('update:modelValue', '');
  emit('change', '');
  close();
};

const isInsideComponent = target =>
  (triggerRef.value && triggerRef.value.contains(target)) ||
  (dropdownRef.value && dropdownRef.value.contains(target));

const onClickOutside = e => {
  if (!isInsideComponent(e.target)) close();
};

const onKeyDown = e => {
  if (!open.value) return;
  if (e.key === 'Escape') {
    e.stopPropagation();
    close();
  }
};

const onScrollOrResize = () => {
  if (open.value) updatePosition();
};

watch(open, isOpen => {
  if (isOpen) {
    // Track scroll on capture so we catch scroll on any ancestor too
    window.addEventListener('scroll', onScrollOrResize, true);
    window.addEventListener('resize', onScrollOrResize);
  } else {
    window.removeEventListener('scroll', onScrollOrResize, true);
    window.removeEventListener('resize', onScrollOrResize);
  }
});

onMounted(() => {
  document.addEventListener('click', onClickOutside, true);
  document.addEventListener('keydown', onKeyDown);
});

onBeforeUnmount(() => {
  document.removeEventListener('click', onClickOutside, true);
  document.removeEventListener('keydown', onKeyDown);
  window.removeEventListener('scroll', onScrollOrResize, true);
  window.removeEventListener('resize', onScrollOrResize);
});
</script>

<!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
<template>
  <div class="ms-root" :class="{ open, disabled }">
    <button
      ref="triggerRef"
      type="button"
      class="ms-trigger"
      :disabled="disabled"
      :aria-haspopup="'listbox'"
      :aria-expanded="open"
      @click="toggle"
    >
      <span class="ms-trigger-content">
        <slot name="selected" :option="selected">
          <template v-if="selected">
            <span
              v-if="selected.color"
              class="ms-dot"
              :style="{ background: selected.color }"
            />
            <span class="ms-selected-label">{{ selected.label }}</span>
          </template>
          <span v-else class="ms-placeholder">{{ placeholder }}</span>
        </slot>
      </span>
      <i class="i-lucide-chevron-down ms-arrow" />
    </button>

    <Teleport to="body">
      <div
        v-if="open"
        ref="dropdownRef"
        class="ms-dropdown"
        :class="{ 'ms-dropdown-up': dropDirection === 'up' }"
        :style="dropdownStyle"
        role="listbox"
      >
        <input
          v-if="showSearch"
          ref="searchInputRef"
          v-model="search"
          class="ms-search"
          :placeholder="searchPlaceholder"
          @click.stop
        />
        <div class="ms-options-scroll">
          <div
            v-if="clearable && hasSelection"
            class="ms-option ms-option-clear"
            @click.stop="clear"
          >
            <i class="i-lucide-x ms-clear-icon" />
            {{ clearLabel }}
          </div>
          <div
            v-for="option in filteredOptions"
            :key="option.value"
            class="ms-option"
            :class="{
              selected: option.value === modelValue,
              disabled: option.disabled,
            }"
            role="option"
            :aria-selected="option.value === modelValue"
            @click.stop="selectOption(option)"
          >
            <slot name="option" :option="option">
              <span
                v-if="option.color"
                class="ms-dot"
                :style="{ background: option.color }"
              />
              <!-- ms-option-main: agrupa label + badge para que o badge fique
                   inline com o nome. O `flex: 1` daqui empurra o hint pra direita. -->
              <span class="ms-option-main">
                <span class="ms-option-label">{{ option.label }}</span>
                <span
                  v-if="option.badge !== null && option.badge !== undefined && option.badge !== ''"
                  class="ms-option-badge"
                >{{ option.badge }}</span>
              </span>
              <span v-if="option.hint" class="ms-option-hint">{{
                option.hint
              }}</span>
            </slot>
          </div>
          <div v-if="filteredOptions.length === 0" class="ms-empty">
            {{ noOptionsText }}
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.ms-root {
  position: relative;
  width: 100%;
}

.ms-trigger {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  width: 100%;
  padding: 0.375rem 0.75rem;
  min-height: 2.5rem;
  border: 1px solid rgb(var(--slate-4));
  border-radius: 0.5rem;
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-12));
  font-size: 0.875rem;
  cursor: pointer;
  transition: all 0.2s ease-in-out;
  text-align: left;
  outline: none;
  font-family: inherit;
}

.ms-trigger:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-1));
  box-shadow: none;
}
.ms-trigger:focus,
.ms-root.open .ms-trigger {
  border-color: rgb(var(--blue-8));
  box-shadow: 0 0 0 3px rgba(var(--blue-9), 0.12);
  background: rgb(var(--slate-1));
}

.ms-root.disabled .ms-trigger {
  cursor: not-allowed;
  opacity: 0.6;
}

.ms-arrow {
  width: 14px;
  height: 14px;
  color: rgb(var(--slate-8));
  flex-shrink: 0;
  transition: transform 0.2s;
}

.ms-root.open .ms-arrow {
  transform: rotate(180deg);
}

.ms-trigger-content {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ms-selected-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ms-placeholder {
  color: rgb(var(--slate-8));
}

.ms-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
  /* Keeps colored dots visible on light/dark surfaces */
  box-shadow: 0 0 0 1.5px #fff, 0 0 0 2px rgba(0, 0, 0, 0.08);
}
</style>

<style>
/* Unscoped — the dropdown is teleported to <body>, so scoped CSS won't
   reach it. Class names are namespaced (ms-*) to avoid collisions. */
.ms-dropdown {
  /* Acima dos modais do Chatwoot (~9999) */
  z-index: 100000;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--border-strong));
  border-radius: 0.5rem;
  box-shadow: 0 12px 32px rgba(0, 0, 0, 0.18);
  padding: 4px;
  display: flex;
  flex-direction: column;
  overflow: hidden;
  animation: ms-pop 120ms ease-out;
}

.ms-dropdown-up {
  animation: ms-pop-up 120ms ease-out;
}

@keyframes ms-pop {
  from {
    opacity: 0;
    transform: translateY(-4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@keyframes ms-pop-up {
  from {
    opacity: 0;
    transform: translateY(4px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.ms-search {
  width: 100%;
  padding: 8px 10px;
  border: none;
  border-bottom: 1px solid rgb(var(--border-strong));
  background: rgb(var(--slate-1));
  color: rgb(var(--slate-12));
  font-size: 0.875rem;
  outline: none;
  margin-bottom: 4px;
  border-radius: 0;
  flex-shrink: 0;
}

.ms-search::placeholder {
  color: rgb(var(--slate-8));
}

.ms-options-scroll {
  overflow-y: auto;
  flex: 1 1 auto;
  min-height: 0;
}

.ms-option {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px 10px;
  font-size: 0.875rem;
  color: rgb(var(--slate-11));
  cursor: pointer;
  border-radius: 6px;
  transition: background 0.1s, color 0.1s;
  user-select: none;
}

.ms-option:hover {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
}

.ms-option.selected {
  color: rgb(var(--blue-9));
  font-weight: 600;
  background: rgba(var(--blue-9), 0.08);
}

.ms-option.disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

.ms-option-clear {
  color: rgb(var(--slate-9)) !important;
  font-style: italic;
}

.ms-clear-icon {
  width: 14px;
  height: 14px;
}

/* Wrapper que mantém label + badge juntos (inline). Toma o `flex: 1`
   da row para que o hint fique empurrado pra direita. */
.ms-option-main {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  flex: 1;
  min-width: 0;
  overflow: hidden;
}
.ms-option-label {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* Badge discreto AO LADO do label — identificador numérico (ID do serviço).
   Monospace + tabular-nums + fundo sutil cinza. */
.ms-option-badge {
  display: inline-flex;
  align-items: center;
  padding: 1px 6px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 4px;
  font-size: 10px;
  font-family: ui-monospace, SFMono-Regular, 'JetBrains Mono', Consolas, monospace;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-9));
  flex-shrink: 0;
  line-height: 1.2;
}

/* Hint visual como badge azul sutil — usado para duração + preço, ou
   qualquer info numérica/contextual à direita da opção. */
.ms-option-hint {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  background: rgba(37, 99, 235, 0.08);
  color: rgb(var(--blue-11));
  border: 1px solid rgba(37, 99, 235, 0.18);
  border-radius: 5px;
  font-size: 10px;
  font-weight: 500;
  font-variant-numeric: tabular-nums;
  flex-shrink: 0;
  line-height: 1.3;
  white-space: nowrap;
}

:root.dark .ms-option-hint {
  background: rgba(59, 130, 246, 0.15);
  color: #93c5fd;
  border-color: rgba(59, 130, 246, 0.32);
}

.ms-empty {
  padding: 12px;
  text-align: center;
  color: rgb(var(--slate-8));
  font-style: italic;
  font-size: 0.875rem;
}

.ms-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
  box-shadow: 0 0 0 1.5px #fff, 0 0 0 2px rgba(0, 0, 0, 0.08);
}
</style>
