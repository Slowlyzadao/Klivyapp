<!--
  Tooltip — componente reutilizável Beclinic.

  ⚠️  CONVENÇÃO DO PROJETO (ver AGENTS.md → "Reusable UI components"):
      SEMPRE use este componente em vez de `title="..."` HTML nativo.
      Native `title=` é feio, lento, dispensável em screen readers e quebra
      em containers com `overflow: hidden`. Este componente resolve tudo isso
      via Teleport pra `<body>` + posicionamento dinâmico.

  Estilo "pill escuro" alinhado ao tooltip da Agenda (`.evt-type-tooltip` em
  `plugins/agenda/frontend/styles/agenda-events.css`). Renderizado via
  `<Teleport to="body">` para escapar de qualquer `overflow: hidden` em
  containers ancestrais. Posicionado via `getBoundingClientRect` no hover/focus.

  Uso:
    <Tooltip label="Marcar como errata" position="top">
      <button>Errata</button>
    </Tooltip>

  Props:
    - label (string, obrigatório)
    - position ('top' | 'bottom' | 'left' | 'right', default 'top')
    - delay (number, ms — default 100; tempo antes de mostrar)
-->

<script setup>
import { ref, onBeforeUnmount } from 'vue';

const props = defineProps({
  label: { type: String, required: true },
  position: {
    type: String,
    default: 'top',
    validator: v => ['top', 'bottom', 'left', 'right'].includes(v),
  },
  delay: { type: Number, default: 100 },
  // Multiline permite que o tooltip quebre linha — útil pra textos longos
  // de help/regra. Default `false` mantém compatibilidade com tooltips
  // curtos (ex: "Marcar como errata") que ficam melhor em 1 linha.
  multiline: { type: Boolean, default: false },
  // Variante opcional. Quando definida, adiciona a classe modificadora
  // `.bcl-tooltip--<variant>` ao bubble — permite consumidores específicos
  // (ex: Year View da agenda) sobrescreverem estilo sem tocar no default
  // global. Sem valor = comportamento padrão (zero impacto em chamadas
  // existentes). Convenção: kebab-case curto (`year-view`, `error`, etc.).
  variant: { type: String, default: '' },
});

const wrapperRef = ref(null);
const bubbleStyle = ref({});
const isVisible = ref(false);
let showTimer = null;

const computeBubblePosition = (rect, pos) => {
  // Margem entre wrapper e bubble + reserva pra seta
  const gap = 10;
  const baseStyle = { position: 'fixed', zIndex: 99999 };

  if (pos === 'top') {
    return {
      ...baseStyle,
      left: `${rect.left + rect.width / 2}px`,
      top: `${rect.top - gap}px`,
      transform: 'translate(-50%, -100%)',
    };
  }
  if (pos === 'bottom') {
    return {
      ...baseStyle,
      left: `${rect.left + rect.width / 2}px`,
      top: `${rect.bottom + gap}px`,
      transform: 'translateX(-50%)',
    };
  }
  if (pos === 'left') {
    return {
      ...baseStyle,
      left: `${rect.left - gap}px`,
      top: `${rect.top + rect.height / 2}px`,
      transform: 'translate(-100%, -50%)',
    };
  }
  // right
  return {
    ...baseStyle,
    left: `${rect.right + gap}px`,
    top: `${rect.top + rect.height / 2}px`,
    transform: 'translateY(-50%)',
  };
};

const show = () => {
  if (showTimer) return;
  showTimer = window.setTimeout(() => {
    if (!wrapperRef.value) return;
    const rect = wrapperRef.value.getBoundingClientRect();
    bubbleStyle.value = computeBubblePosition(rect, props.position);
    isVisible.value = true;
    showTimer = null;
  }, props.delay);
};

const hide = () => {
  if (showTimer) {
    clearTimeout(showTimer);
    showTimer = null;
  }
  isVisible.value = false;
};

onBeforeUnmount(hide);
</script>

<template>
  <span
    ref="wrapperRef"
    class="bcl-tooltip-host"
    @mouseenter="show"
    @mouseleave="hide"
    @focusin="show"
    @focusout="hide"
  >
    <slot />
    <Teleport to="body">
      <span
        v-if="isVisible && label"
        class="bcl-tooltip"
        :class="[
          `bcl-tooltip--${position}`,
          { 'bcl-tooltip--multiline': multiline },
          variant ? `bcl-tooltip--${variant}` : null,
        ]"
        :style="bubbleStyle"
        role="tooltip"
      >
        {{ label }}
      </span>
    </Teleport>
  </span>
</template>

<style scoped lang="scss">
.bcl-tooltip-host {
  display: inline-flex;
}
</style>

<style lang="scss">
/* Estilos globais (não-scoped) porque o bubble vive no <body> via Teleport
   e perderia o `data-v-*` do scoped. */
.bcl-tooltip {
  padding: 5px 9px;
  background: rgb(31, 41, 55);
  color: #fff;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 500;
  line-height: 1.4;
  letter-spacing: 0.01em;
  white-space: nowrap;
  pointer-events: none;
  box-shadow:
    0 6px 16px rgba(0, 0, 0, 0.18),
    0 1px 3px rgba(0, 0, 0, 0.12);
  animation: bcl-tooltip-in 0.12s ease-out;

  &::after {
    content: '';
    position: absolute;
    border: 5px solid transparent;
  }
}

/* Variante multiline pra textos de help longos — permite quebra com largura
   máxima legível. Tipografia ganha um pouco mais de respiro também. */
.bcl-tooltip--multiline {
  white-space: normal;
  max-width: 280px;
  padding: 8px 11px;
  font-size: 11.5px;
  line-height: 1.5;
  text-align: left;
}

.bcl-tooltip--top::after {
  top: 100%;
  left: 50%;
  transform: translateX(-50%);
  border-top-color: rgb(31, 41, 55);
}
.bcl-tooltip--bottom::after {
  bottom: 100%;
  left: 50%;
  transform: translateX(-50%);
  border-bottom-color: rgb(31, 41, 55);
}
.bcl-tooltip--left::after {
  left: 100%;
  top: 50%;
  transform: translateY(-50%);
  border-left-color: rgb(31, 41, 55);
}
.bcl-tooltip--right::after {
  right: 100%;
  top: 50%;
  transform: translateY(-50%);
  border-right-color: rgb(31, 41, 55);
}

@keyframes bcl-tooltip-in {
  from {
    opacity: 0;
    transform-origin: center;
  }
  to {
    opacity: 1;
  }
}
</style>
