<script setup>
// Menu de inserção de variável — usado tanto pelo painel lateral do editor
// quanto pelo suggestion popover disparado por "/" no texto.
//
// SIDEBAR (showSearch=true): as seções por categoria viram ACORDEÃO (toggle
// inline) e, quando há paciente selecionado, cada item mostra o VALOR REAL
// resolvido (item sem valor some). POPOVER "/" (showSearch=false): lista plana
// com h3 estático + navegação por teclado — comportamento intacto.

import { ref, computed, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import SearchInput from '@plugins/beclinic_core/frontend/components/SearchInput.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  // Index do item destacado (controlado pelo pai pra integrar com suggestion).
  highlightedIndex: { type: Number, default: 0 },
  showSearch: { type: Boolean, default: false },
  // Mapa { chave: valor } resolvido do paciente (preview ao vivo). Vazio / sem
  // paciente → mostra o `example` estático como dica.
  previewValues: { type: Object, default: () => ({}) },
  selectedPatientId: { type: [String, Number], default: '' },
});

const emit = defineEmits(['select', 'update:highlightedIndex']);

const { t } = useI18n();
const searchTerm = ref('');
const listRef = ref(null);

// O resolver (backend) devolve '_______' (DEFAULT_FALLBACK) quando o campo do
// paciente está vazio — nunca null/''. Para a regra "vazio = não exibe",
// tratamos '_______' como SEM valor.
const EMPTY_RESOLVED = '_______';

const hasPatient = computed(() => Boolean(props.selectedPatientId));

const resolvedValueFor = variable => {
  const v = props.previewValues?.[variable.key];
  if (v === null || v === undefined) return '';
  const s = String(v).trim();
  if (s.length === 0 || s === EMPTY_RESOLVED) return '';
  return s;
};

// Campos de preenchimento (input.*) não vêm do cadastro — são digitados na
// geração. Sempre aparecem (mostram o exemplo como dica), mesmo com paciente.
const isInputVar = variable => String(variable.key || '').startsWith('input.');

// Com paciente: só itens com valor real (insere o que tem dado), exceto os
// input.* que sempre aparecem. Sem paciente: mostra tudo.
const shouldShowItem = variable =>
  !hasPatient.value || isInputVar(variable) || resolvedValueFor(variable).length > 0;

const visibleItems = computed(() => {
  const q = searchTerm.value.trim().toLowerCase();
  const base = q
    ? props.items.filter(
        v =>
          v.label.toLowerCase().includes(q) || v.key.toLowerCase().includes(q)
      )
    : props.items;
  return base.filter(shouldShowItem);
});

const grouped = computed(() => {
  const out = {};
  visibleItems.value.forEach(v => {
    (out[v.category] ??= []).push(v);
  });
  return out;
});

// Índice sobre a lista efetivamente visível (pós-filtro) — mantém setas/Enter
// coerentes com o DOM. No popover "/" não há filtro de paciente, então fica
// idêntico ao comportamento anterior.
const flatIndexFor = variable =>
  visibleItems.value.findIndex(v => v.key === variable.key);

const onSelect = variable => emit('select', variable);

const onHover = variable => {
  emit('update:highlightedIndex', flatIndexFor(variable));
};

// ── Acordeão (só na sidebar) ──────────────────────────────────────────────
const openCategories = ref(new Set());
const isCategoryOpen = category => openCategories.value.has(category);
const toggleCategory = category => {
  const next = new Set(openCategories.value); // novo Set p/ disparar reatividade
  if (next.has(category)) next.delete(category);
  else next.add(category);
  openCategories.value = next;
};

// Default: todas abertas. Busca força todas abertas; limpar não re-fecha o que
// o usuário deixou. Inerte no popover "/" (showSearch=false).
watch(
  [() => Object.keys(grouped.value).join('|'), searchTerm, () => props.showSearch],
  ([keysStr, term, withSearch]) => {
    if (!withSearch) return;
    const keys = keysStr ? keysStr.split('|') : [];
    if (term.trim() || openCategories.value.size === 0) {
      openCategories.value = new Set(keys);
    }
  },
  { immediate: true }
);

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
      // Clampa o índice à lista visível: insere sempre o item REALMENTE
      // destacado (o que casa `--active`), nunca um item silenciosamente errado.
      const i = Math.min(Math.max(props.highlightedIndex, 0), items.length - 1);
      const item = items[i];
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
      <SearchInput
        v-model="searchTerm"
        :placeholder="t('DOCUMENT_TEMPLATES.EDITOR.SEARCH_VARIABLE')"
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
      <!-- Sidebar: header de acordeão clicável. Popover "/": h3 estático. -->
      <button
        v-if="showSearch"
        type="button"
        class="variable-picker__accordion-header"
        :aria-expanded="isCategoryOpen(category)"
        @click="toggleCategory(category)"
      >
        <span
          class="i-lucide-chevron-right variable-picker__accordion-chevron"
          :class="{ 'is-open': isCategoryOpen(category) }"
        />
        <span class="variable-picker__accordion-label">{{ category }}</span>
        <span class="variable-picker__accordion-count">{{ items.length }}</span>
      </button>
      <h3 v-else class="variable-picker__group-title">{{ category }}</h3>

      <ul
        v-show="!showSearch || isCategoryOpen(category)"
        class="variable-picker__list"
      >
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
            <!-- Com paciente: valor real (itens sem valor já foram filtrados).
                 Campos de preenchimento e sem-paciente: example como dica. -->
            <span
              v-if="hasPatient && !isInputVar(variable)"
              class="variable-picker__item-value"
              :title="resolvedValueFor(variable)"
            >{{ resolvedValueFor(variable) }}</span>
            <span
              v-else-if="variable.example"
              class="variable-picker__item-example"
            >{{ variable.example }}</span>
          </button>
        </li>
      </ul>
    </div>
  </div>
</template>

<style lang="scss" scoped>
@use '../../styles/editor/picker-menu';
</style>
