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
import { ref, onBeforeUnmount, nextTick } from 'vue';

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
const bubbleRef = ref(null);
const bubbleStyle = ref({});
// Offset do arrow (em px) quando o bubble é clampado no viewport — mantém
// a setinha apontando pro centro do trigger mesmo com o balão deslocado.
const arrowOffset = ref(0);
const isVisible = ref(false);
// Posição efetivamente aplicada — pode diferir da prop `position` quando
// o flip vertical/horizontal entra (ex: prop='top' mas não cabe → vira
// 'bottom'). O class binding usa `effectivePosition` pra a seta apontar
// na direção correta após flip.
const effectivePosition = ref(props.position);
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

// Margem de segurança contra a borda do viewport ao clampar.
const VIEWPORT_PAD = 8;

// Pares opostos pra flip automático. Quando o bubble não cabe na posição
// pedida, troca pelo oposto (top↔bottom, left↔right).
const OPPOSITE = { top: 'bottom', bottom: 'top', left: 'right', right: 'left' };

// Clamp inteligente em DUAS fases:
//   1) FLIP — se a posição pedida não cabe no eixo principal, inverte pro
//      lado oposto (ex: trigger na header do app, prop='top' → vira
//      'bottom' pra renderizar abaixo). A seta acompanha via classe
//      `.bcl-tooltip--<effectivePosition>`.
//   2) SHIFT — depois do flip (ou na posição original se coube), empurra
//      o bubble pra dentro do viewport no eixo ORTOGONAL e compensa o
//      arrowOffset pra seta continuar apontando pro trigger.
const adjustWithinViewport = async (triggerRect) => {
  await nextTick();
  if (!bubbleRef.value) return;
  let bubbleRect = bubbleRef.value.getBoundingClientRect();
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  // ── Fase 1: FLIP no eixo principal ────────────────────────────────
  const pos = effectivePosition.value;
  let needsFlip = false;
  if (pos === 'top' && bubbleRect.top < VIEWPORT_PAD) needsFlip = true;
  else if (pos === 'bottom' && bubbleRect.bottom > vh - VIEWPORT_PAD) needsFlip = true;
  else if (pos === 'left' && bubbleRect.left < VIEWPORT_PAD) needsFlip = true;
  else if (pos === 'right' && bubbleRect.right > vw - VIEWPORT_PAD) needsFlip = true;

  if (needsFlip) {
    const flipped = OPPOSITE[pos];
    // Só aplica o flip se o lado oposto tem espaço suficiente — evita
    // ping-pong em viewports muito pequenos (pior dos casos: deixa onde
    // estava e o shift clamp vai resolver o que dá).
    const bubbleH = bubbleRect.height;
    const bubbleW = bubbleRect.width;
    const fits =
      (flipped === 'top' && triggerRect.top - bubbleH - 10 >= VIEWPORT_PAD) ||
      (flipped === 'bottom' && triggerRect.bottom + bubbleH + 10 <= vh - VIEWPORT_PAD) ||
      (flipped === 'left' && triggerRect.left - bubbleW - 10 >= VIEWPORT_PAD) ||
      (flipped === 'right' && triggerRect.right + bubbleW + 10 <= vw - VIEWPORT_PAD);
    if (fits) {
      effectivePosition.value = flipped;
      bubbleStyle.value = computeBubblePosition(triggerRect, flipped);
      await nextTick();
      bubbleRect = bubbleRef.value.getBoundingClientRect();
    }
  }

  // ── Fase 2: SHIFT no eixo ortogonal ───────────────────────────────
  const final = effectivePosition.value;
  if (final === 'top' || final === 'bottom') {
    let shiftX = 0;
    if (bubbleRect.right > vw - VIEWPORT_PAD) {
      shiftX = vw - VIEWPORT_PAD - bubbleRect.right;
    } else if (bubbleRect.left < VIEWPORT_PAD) {
      shiftX = VIEWPORT_PAD - bubbleRect.left;
    }
    if (shiftX !== 0) {
      // Aplica o shift mantendo `transform: translate(-50%, ...)` — pra isso
      // a forma mais simples é trocar `left` pra o valor já corrigido.
      const triggerCenterX = triggerRect.left + triggerRect.width / 2;
      bubbleStyle.value = {
        ...bubbleStyle.value,
        left: `${triggerCenterX + shiftX}px`,
      };
      // Seta segue o trigger original (compensa o shift na direção oposta).
      arrowOffset.value = -shiftX;
    }
  } else {
    // left/right — clamp vertical
    let shiftY = 0;
    if (bubbleRect.bottom > vh - VIEWPORT_PAD) {
      shiftY = vh - VIEWPORT_PAD - bubbleRect.bottom;
    } else if (bubbleRect.top < VIEWPORT_PAD) {
      shiftY = VIEWPORT_PAD - bubbleRect.top;
    }
    if (shiftY !== 0) {
      const triggerCenterY = triggerRect.top + triggerRect.height / 2;
      bubbleStyle.value = {
        ...bubbleStyle.value,
        top: `${triggerCenterY + shiftY}px`,
      };
      arrowOffset.value = -shiftY;
    }
  }
};

const show = () => {
  if (showTimer) return;
  showTimer = window.setTimeout(() => {
    if (!wrapperRef.value) return;
    const rect = wrapperRef.value.getBoundingClientRect();
    // Reset effectivePosition pra prop a cada show — caso o trigger anterior
    // tenha tido flip, próximo show começa do zero pra reavaliar viewport.
    effectivePosition.value = props.position;
    bubbleStyle.value = computeBubblePosition(rect, props.position);
    arrowOffset.value = 0;
    isVisible.value = true;
    showTimer = null;
    adjustWithinViewport(rect);
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
        ref="bubbleRef"
        class="bcl-tooltip"
        :class="[
          `bcl-tooltip--${effectivePosition}`,
          { 'bcl-tooltip--multiline': multiline },
          variant ? `bcl-tooltip--${variant}` : null,
        ]"
        :style="{ ...bubbleStyle, '--bcl-arrow-offset': `${arrowOffset}px` }"
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

/* `--bcl-arrow-offset` (default 0px) compensa o deslocamento do bubble quando
   ele é clampado pra dentro do viewport — a seta continua apontando pro
   centro do trigger original mesmo com o balão deslocado lateralmente. */
.bcl-tooltip--top::after {
  top: 100%;
  left: calc(50% + var(--bcl-arrow-offset, 0px));
  transform: translateX(-50%);
  border-top-color: rgb(31, 41, 55);
}
.bcl-tooltip--bottom::after {
  bottom: 100%;
  left: calc(50% + var(--bcl-arrow-offset, 0px));
  transform: translateX(-50%);
  border-bottom-color: rgb(31, 41, 55);
}
.bcl-tooltip--left::after {
  left: 100%;
  top: calc(50% + var(--bcl-arrow-offset, 0px));
  transform: translateY(-50%);
  border-left-color: rgb(31, 41, 55);
}
.bcl-tooltip--right::after {
  right: 100%;
  top: calc(50% + var(--bcl-arrow-offset, 0px));
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
