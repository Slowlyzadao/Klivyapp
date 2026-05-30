<script setup>
// Menu de inserção de variável — usado tanto pelo painel lateral do editor
// quanto pelo suggestion popover disparado por "/" no texto.
//
// Recebe lista filtrada via props (filtragem é responsabilidade do pai —
// composable useVariableCatalog). Emite `select` ao clicar/Enter.

import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  items: { type: Array, default: () => [] },
  // Index do item destacado (controlado pelo pai pra integrar com suggestion).
  highlightedIndex: { type: Number, default: 0 },
  showSearch: { type: Boolean, default: false },
});

const emit = defineEmits(['select', 'update:highlightedIndex']);

const { t } = useI18n();
const searchTerm = ref('');
const listRef = ref(null);

const visibleItems = computed(() => {
  const q = searchTerm.value.trim().toLowerCase();
  if (!q) return props.items;
  return props.items.filter(v =>
    v.label.toLowerCase().includes(q) ||
    v.key.toLowerCase().includes(q)
  );
});

const grouped = computed(() => {
  const out = {};
  visibleItems.value.forEach(v => {
    out[v.category] ??= [];
    out[v.category].push(v);
  });
  return out;
});

const flatIndexFor = (variable) =>
  visibleItems.value.findIndex(v => v.key === variable.key);

const onSelect = (variable) => emit('select', variable);

const onHover = (variable) => {
  emit('update:highlightedIndex', flatIndexFor(variable));
};

// Scrollar item destacado pra view quando suggestion navega pelo teclado.
watch(
  () => props.highlightedIndex,
  async () => {
    await nextTick();
    const el = listRef.value?.querySelector(
      `[data-variable-index="${props.highlightedIndex}"]`
    );
    el?.scrollIntoView({ block: 'nearest' });
  }
);

// Exposto pro pai (TipTap suggestion handler) chamar Enter remotamente.
defineExpose({
  onKeyDown: ({ event }) => {
    const items = visibleItems.value;
    if (items.length === 0) return false;

    if (event.key === 'ArrowDown') {
      const next = (props.highlightedIndex + 1) % items.length;
      emit('update:highlightedIndex', next);
      return true;
    }
    if (event.key === 'ArrowUp') {
      const prev = (props.highlightedIndex - 1 + items.length) % items.length;
      emit('update:highlightedIndex', prev);
      return true;
    }
    if (event.key === 'Enter') {
      const item = items[props.highlightedIndex] || items[0];
      if (item) onSelect(item);
      return true;
    }
    return false;
  },
});
</script>

<template>
  <div ref="listRef" class="variable-picker">
    <div v-if="showSearch" class="variable-picker__search">
      <span class="i-lucide-search variable-picker__search-icon" />
      <input
        v-model="searchTerm"
        type="text"
        :placeholder="t('DOCUMENT_TEMPLATES.EDITOR.SEARCH_VARIABLE')"
        class="variable-picker__search-input"
      />
    </div>

    <div v-if="visibleItems.length === 0" class="variable-picker__empty">
      {{ t('DOCUMENT_TEMPLATES.EDITOR.NO_VARIABLES') }}
    </div>

    <div
      v-for="(items, category) in grouped"
      :key="category"
      class="variable-picker__group"
    >
      <h3 class="variable-picker__group-title">{{ category }}</h3>
      <ul class="variable-picker__list">
        <li
          v-for="variable in items"
          :key="variable.key"
          :data-variable-index="flatIndexFor(variable)"
        >
          <button
            type="button"
            class="variable-picker__item"
            :class="{
              'variable-picker__item--active':
                flatIndexFor(variable) === highlightedIndex,
            }"
            @click="onSelect(variable)"
            @mousemove="onHover(variable)"
          >
            <span class="variable-picker__item-label">{{ variable.label }}</span>
            <span v-if="variable.example" class="variable-picker__item-example">
              {{ variable.example }}
            </span>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/picker-menu';
</style>
