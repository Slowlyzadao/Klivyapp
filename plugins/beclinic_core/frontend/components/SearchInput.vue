<script setup>
/**
 * SearchInput — campo de busca padrão dos plugins Klivy.
 *
 * Encapsula wrapper + ícone à direita + input com o visual já usado em
 * `plugins/patients/frontend/routes/patients/Index.vue` (`.pt-search-*`) e
 * espelhado em `plugins/financial/frontend/components/FinSearchInput.vue`
 * (`.finv2-input-wrap`). Substitui o HTML/SCSS duplicado por cada plugin.
 *
 * Visual:
 *   - background slate-2 (slate-1 no focus)
 *   - border-radius 8px
 *   - padding 8px 38px 8px 13px (espaço para ícone à direita)
 *   - font-size 13px (compacto, padrão das tabelas v2)
 *   - ícone i-lucide-search à direita, 15×15, slate-11
 *   - focus: border blue-8, sem box-shadow
 *
 * Uso:
 *   <SearchInput
 *     v-model="searchQuery"
 *     placeholder="Buscar..."
 *   />
 *
 * Props/Emit:
 *   modelValue   : string (v-model)
 *   placeholder  : string
 *   ariaLabel    : string (cai pro placeholder se omitido)
 *
 * Class fallthrough vai pro wrapper externo (permite ajuste de largura por
 * página). Demais attrs (id, name, autofocus, @keydown.enter) vão pro input.
 */
import { computed, useAttrs } from 'vue';

defineOptions({ inheritAttrs: false });

defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: 'Buscar...' },
  ariaLabel: { type: String, default: '' },
});

const emit = defineEmits(['update:modelValue']);

const attrs = useAttrs();
const wrapperClass = computed(() => attrs.class);
const inputAttrs = computed(() => {
  const { class: _c, style: _s, ...rest } = attrs;
  return rest;
});

function onInput(event) {
  emit('update:modelValue', event.target.value);
}
</script>

<template>
  <div class="bcl-search" :class="wrapperClass">
    <i class="i-lucide-search bcl-search__icon" aria-hidden="true" />
    <input
      :value="modelValue"
      type="search"
      class="bcl-search__input"
      :placeholder="placeholder"
      :aria-label="ariaLabel || placeholder"
      v-bind="inputAttrs"
      @input="onInput"
    />
  </div>
</template>

<style scoped lang="scss">
.bcl-search {
  position: relative;
  display: flex;
  align-items: center;
  flex: 1;
  min-width: 220px;
  max-width: 380px;
}

.bcl-search__icon {
  position: absolute;
  right: 12px;
  width: 15px;
  height: 15px;
  color: rgb(var(--slate-11));
  pointer-events: none;
}

.bcl-search__input {
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 8px 38px 8px 13px;
  color: rgb(var(--slate-12));
  font-size: 13px;
  outline: none;
  transition: border-color 0.15s ease, background 0.15s ease;
  box-shadow: none;
  font-family: inherit;

  &::placeholder {
    color: rgb(var(--slate-11));
  }

  &:focus {
    border-color: rgb(var(--blue-8));
    background: rgb(var(--slate-1));
    box-shadow: none;
  }

  /* Remove o "X" nativo do type=search no Chrome/Safari — visual fica mais
     limpo (o ícone de lupa já comunica o estado, e clear via teclado funciona). */
  &::-webkit-search-cancel-button {
    -webkit-appearance: none;
    appearance: none;
  }
}

@media (max-width: 640px) {
  .bcl-search {
    min-width: 0;
    max-width: none;
    width: 100%;
  }
}
</style>
