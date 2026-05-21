<script setup>
/**
 * Campo de busca padrão do Financeiro V2.
 *
 * Encapsula a estrutura wrapper + ícone + input usada em todas as páginas
 * do módulo (Receivables, Payables, CashFlow, Reclassify, AuditLogs) e em
 * pickers de modais. Substitui o HTML duplicado por copy-paste em cada
 * página por um ponto de manutenção único.
 *
 * Geometria e cascata (override do reset do Chatwoot core em `_base.scss`)
 * vivem em `styles/financial/_layout.scss` — não duplicar regras aqui.
 *
 * Class fallthrough vai pro wrapper externo (preserva classes de layout
 * por página, ex.: `pyv2__input--grow`, `rcv-v2__input--grow`). Demais
 * attrs e listeners (id, name, @keydown.enter, autofocus) vão pro input.
 */
import { computed, useAttrs } from 'vue';

defineOptions({ inheritAttrs: false });

defineProps({
  modelValue: { type: String, default: '' },
  placeholder: { type: String, default: '' },
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
  <div class="finv2-input-wrap finv2-input-wrap--with-icon" :class="wrapperClass">
    <i class="i-lucide-search finv2-input__icon" aria-hidden="true" />
    <input
      :value="modelValue"
      type="search"
      class="finv2-input"
      :placeholder="placeholder"
      :aria-label="ariaLabel || placeholder"
      v-bind="inputAttrs"
      @input="onInput"
    />
  </div>
</template>
