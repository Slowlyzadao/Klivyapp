<template>
  <div class="pp-sigpad">
    <div class="pp-sigpad__frame">
      <canvas
        ref="canvasRef"
        class="pp-sigpad__canvas"
        :width="width"
        :height="height"
        @mousedown="startDraw"
        @mousemove="draw"
        @mouseup="endDraw"
        @mouseleave="endDraw"
        @touchstart.prevent="startDraw"
        @touchmove.prevent="draw"
        @touchend.prevent="endDraw"
      />
      <div v-if="empty" class="pp-sigpad__placeholder">
        Assine aqui usando o dedo ou mouse
      </div>
    </div>
    <div class="pp-sigpad__actions">
      <button type="button" class="pp-sigpad__clear" @click="clear">
        Limpar
      </button>
      <span v-if="!empty" class="pp-sigpad__hint">
        <IconCheck :size="14" /> Assinatura capturada
      </span>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue';
import IconCheck from './icons/IconCheck.vue';

const emit = defineEmits(['update:dataUrl']);

const canvasRef = ref(null);
const drawing   = ref(false);
const empty     = ref(true);

const width  = 600;  // resolução interna (CSS escala)
const height = 220;

let ctx = null;
let last = null;

function getPoint(evt) {
  const c = canvasRef.value;
  const rect = c.getBoundingClientRect();
  const scaleX = c.width  / rect.width;
  const scaleY = c.height / rect.height;
  const src = evt.touches ? evt.touches[0] : evt;
  return {
    x: (src.clientX - rect.left) * scaleX,
    y: (src.clientY - rect.top)  * scaleY
  };
}

function startDraw(evt) {
  drawing.value = true;
  last = getPoint(evt);
}

function draw(evt) {
  if (!drawing.value) return;
  const p = getPoint(evt);
  ctx.beginPath();
  ctx.moveTo(last.x, last.y);
  ctx.lineTo(p.x, p.y);
  ctx.stroke();
  last = p;
  if (empty.value) empty.value = false;
}

function endDraw() {
  if (!drawing.value) return;
  drawing.value = false;
  emitDataUrl();
}

function emitDataUrl() {
  if (empty.value) {
    emit('update:dataUrl', null);
  } else {
    emit('update:dataUrl', canvasRef.value.toDataURL('image/png'));
  }
}

function clear() {
  ctx.clearRect(0, 0, width, height);
  empty.value = true;
  emitDataUrl();
}

defineExpose({ clear });

onMounted(() => {
  ctx = canvasRef.value.getContext('2d');
  ctx.strokeStyle = '#0f172a';
  ctx.lineWidth   = 2.5;
  ctx.lineCap     = 'round';
  ctx.lineJoin    = 'round';
});

onBeforeUnmount(() => { ctx = null; last = null; });
</script>

<style scoped>
.pp-sigpad__frame {
  position: relative;
  background: #fff;
  border: 1px dashed var(--pp-color-border);
  border-radius: 12px;
  overflow: hidden;
  aspect-ratio: 600 / 220;
}
.pp-sigpad__canvas {
  display: block; width: 100%; height: 100%;
  touch-action: none;
  cursor: crosshair;
}
.pp-sigpad__placeholder {
  position: absolute; inset: 0;
  display: flex; align-items: center; justify-content: center;
  color: var(--pp-color-text-muted); font-size: 13px;
  pointer-events: none;
}
.pp-sigpad__actions {
  display: flex; justify-content: space-between; align-items: center;
  margin-top: 8px; padding: 0 4px;
}
.pp-sigpad__clear {
  background: transparent; border: none; cursor: pointer;
  color: var(--pp-color-text-muted); font-size: 13px; font-weight: 600;
  text-decoration: underline; padding: 0;
}
.pp-sigpad__clear:hover { color: var(--pp-color-text); }
.pp-sigpad__hint {
  display: inline-flex; align-items: center; gap: 4px;
  color: #047857; font-size: 12px; font-weight: 600;
}
</style>
