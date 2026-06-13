<!--
  Checkbox — checkbox customizado padrão do design system Klivy.

  ⚠️  CONVENÇÃO DO PROJETO (mesma régua de FormSelect/Tooltip/Badge):
      SEMPRE use este componente em vez de `<input type="checkbox">` nativo.
      O input native tem visual desencontrado entre browsers, não respeita
      o tema light/dark e é difícil de estilizar de forma consistente. Aqui
      é um input `appearance-none` com checkmark SVG sobreposto, focus ring,
      hover, disabled state e cores do tema.

  Uso:
    <Checkbox v-model="value" label="Aceito os termos" />
    <Checkbox v-model="row.selected" aria-label="Selecionar linha" />
    <Checkbox v-model="active" :disabled="saving">
      <span>Texto rico no <strong>slot default</strong></span>
    </Checkbox>

  Props:
    modelValue : Boolean (v-model)
    label      : string opcional — render ao lado da caixa
    id         : string opcional — gerado via Vue useId() se omitido
    disabled   : Boolean
-->
<script setup>
import { computed, useId } from 'vue';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  label: { type: String, default: '' },
  id: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'change']);

const autoId = useId();
const inputId = computed(() => props.id || autoId);

const onChange = e => {
  emit('update:modelValue', e.target.checked);
  emit('change', e.target.checked);
};
</script>

<template>
  <label
    class="bcl-checkbox"
    :class="{ 'bcl-checkbox--disabled': disabled }"
    :for="inputId"
  >
    <span class="bcl-checkbox__box">
      <input
        :id="inputId"
        type="checkbox"
        :checked="modelValue"
        :disabled="disabled"
        class="bcl-checkbox__input"
        @change="onChange"
      />
      <span class="bcl-checkbox__check" aria-hidden="true">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          viewBox="0 0 20 20"
          fill="currentColor"
        >
          <path
            fill-rule="evenodd"
            d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
            clip-rule="evenodd"
          />
        </svg>
      </span>
    </span>
    <span v-if="label || $slots.default" class="bcl-checkbox__label">
      <slot>{{ label }}</slot>
    </span>
  </label>
</template>

<style scoped lang="scss">
.bcl-checkbox {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  cursor: pointer;
  user-select: none;
}

.bcl-checkbox--disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.bcl-checkbox__box {
  position: relative;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 18px;
  height: 18px;
  flex-shrink: 0;
}

/* Input nativo: appearance-none + box pintado por CSS. Mantemos ele com
   inset:0 pra cobrir todo o `.bcl-checkbox__box` — o checkmark sobrepõe
   absolutamente sem capturar clique (pointer-events:none). */
.bcl-checkbox__input {
  position: absolute;
  inset: 0;
  width: 100%;
  height: 100%;
  margin: 0;
  appearance: none;
  -webkit-appearance: none;
  background: transparent;
  border: 1px solid rgb(var(--slate-7));
  border-radius: 4px;
  cursor: inherit;
  transition:
    background-color 0.15s,
    border-color 0.15s,
    box-shadow 0.15s;
}

.bcl-checkbox__input:hover:not(:disabled) {
  border-color: rgb(var(--blue-8));
  box-shadow: 0 0 0 3px rgba(var(--blue-9), 0.08);
}

.bcl-checkbox__input:focus-visible {
  outline: none;
  border-color: rgb(var(--blue-8));
  box-shadow: 0 0 0 3px rgba(var(--blue-9), 0.18);
}

.bcl-checkbox__input:checked {
  background: rgb(var(--blue-9));
  border-color: rgb(var(--blue-9));
}

.bcl-checkbox__input:disabled {
  cursor: not-allowed;
}

.bcl-checkbox__check {
  position: absolute;
  top: 50%;
  left: 50%;
  width: 12px;
  height: 12px;
  transform: translate(-50%, -50%);
  pointer-events: none;
  color: #fff;
  opacity: 0;
  transition: opacity 0.12s ease-out;
}

.bcl-checkbox__check svg {
  width: 100%;
  height: 100%;
}

.bcl-checkbox__input:checked ~ .bcl-checkbox__check {
  opacity: 1;
}

.bcl-checkbox__label {
  font-size: 14px;
  line-height: 1.3;
  color: rgb(var(--slate-12));
}
</style>
