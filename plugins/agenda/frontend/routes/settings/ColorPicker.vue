<script>
// ─── Conversão de cores ────────────────────────────────────────────────────

function hsvToRgb(h, s, v) {
  const i = Math.floor((h / 360) * 6);
  const f = (h / 360) * 6 - i;
  const p = v * (1 - s);
  const q = v * (1 - f * s);
  const t = v * (1 - (1 - f) * s);
  let r;
  let g;
  let b;
  switch (i % 6) {
    case 0:
      r = v;
      g = t;
      b = p;
      break;
    case 1:
      r = q;
      g = v;
      b = p;
      break;
    case 2:
      r = p;
      g = v;
      b = t;
      break;
    case 3:
      r = p;
      g = q;
      b = v;
      break;
    case 4:
      r = t;
      g = p;
      b = v;
      break;
    case 5:
      r = v;
      g = p;
      b = q;
      break;
    default:
      r = 0;
      g = 0;
      b = 0;
  }
  return {
    r: Math.round(r * 255),
    g: Math.round(g * 255),
    b: Math.round(b * 255),
  };
}

function hexToHsv(hex) {
  const clean = hex.replace('#', '');
  if (clean.length !== 6) return { h: 210, s: 0.85, v: 0.95 };
  const r = parseInt(clean.slice(0, 2), 16) / 255;
  const g = parseInt(clean.slice(2, 4), 16) / 255;
  const b = parseInt(clean.slice(4, 6), 16) / 255;
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const d = max - min;
  let h = 0;
  const s = max === 0 ? 0 : d / max;
  const v = max;
  if (d !== 0) {
    switch (max) {
      case r:
        h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
        break;
      case g:
        h = ((b - r) / d + 2) / 6;
        break;
      case b:
        h = ((r - g) / d + 4) / 6;
        break;
      default:
        h = 0;
    }
  }
  return { h: Math.round(h * 360), s, v };
}

function toHex(r, g, b) {
  return (
    '#' +
    [r, g, b].map(x => Math.round(x).toString(16).padStart(2, '0')).join('')
  );
}

export default {
  name: 'ColorPicker',

  props: {
    modelValue: {
      type: String,
      default: '#3b82f6',
    },
  },

  emits: ['update:modelValue'],

  data() {
    const { h, s, v } = hexToHsv(this.modelValue);
    return {
      hue: h,
      sat: s,
      val: v,
      hexInput: this.modelValue.replace('#', '').toUpperCase(),
    };
  },

  computed: {
    hueBackground() {
      return `hsl(${this.hue}, 100%, 50%)`;
    },
    cursorStyle() {
      return {
        left: `${this.sat * 100}%`,
        top: `${(1 - this.val) * 100}%`,
      };
    },
    currentColor() {
      const { r, g, b } = hsvToRgb(this.hue, this.sat, this.val);
      return toHex(r, g, b);
    },
  },

  watch: {
    modelValue(newVal) {
      if (newVal.toLowerCase() !== this.currentColor.toLowerCase()) {
        const { h, s, v } = hexToHsv(newVal);
        this.hue = h;
        this.sat = s;
        this.val = v;
        this.hexInput = newVal.replace('#', '').toUpperCase();
      }
    },
    currentColor(newColor) {
      this.$emit('update:modelValue', newColor);
      this.hexInput = newColor.replace('#', '').toUpperCase();
    },
  },

  methods: {
    // ─── Quadrado de Saturação/Brilho ──────────────────────────────────────
    startDragSV(e) {
      this.updateSV(e);
      const onMove = ev => this.updateSV(ev);
      const onUp = () => {
        window.removeEventListener('mousemove', onMove);
        window.removeEventListener('mouseup', onUp);
      };
      window.addEventListener('mousemove', onMove);
      window.addEventListener('mouseup', onUp);
    },

    updateSV(e) {
      const box = this.$refs.svBox.getBoundingClientRect();
      const x = Math.max(0, Math.min(1, (e.clientX - box.left) / box.width));
      const y = Math.max(0, Math.min(1, (e.clientY - box.top) / box.height));
      this.sat = x;
      this.val = 1 - y;
    },

    // ─── Slider de Matiz ───────────────────────────────────────────────────
    onHueInput(e) {
      this.hue = Number(e.target.value);
    },

    // ─── Input Hex ─────────────────────────────────────────────────────────
    onHexInput(e) {
      const raw = e.target.value.replace(/[^0-9a-fA-F]/g, '').slice(0, 6);
      this.hexInput = raw.toUpperCase();
      if (raw.length === 6) {
        const { h, s, v } = hexToHsv('#' + raw);
        this.hue = h;
        this.sat = s;
        this.val = v;
      }
    },
  },
};
</script>

<template>
  <div class="cp-root" @mousedown.stop>
    <!-- Quadrado Saturação / Brilho -->
    <div
      ref="svBox"
      class="cp-sv-box"
      :style="{ backgroundColor: hueBackground }"
      @mousedown.prevent="startDragSV"
    >
      <div class="cp-sv-white" />
      <div class="cp-sv-black" />
      <div class="cp-sv-cursor" :style="cursorStyle" />
    </div>

    <!-- Controles: preview + slider de matiz -->
    <div class="cp-controls">
      <div class="cp-preview" :style="{ backgroundColor: currentColor }" />
      <div class="cp-hue-wrap">
        <input
          class="cp-hue-slider"
          type="range"
          min="0"
          max="360"
          :value="hue"
          @input="onHueInput"
        />
      </div>
    </div>

    <!-- Input Hex -->
    <div class="cp-hex-row">
      <div class="cp-hex-wrap">
        <span class="cp-hex-label">{{ 'HEX' }}</span>
        <input
          class="cp-hex-input"
          type="text"
          maxlength="6"
          :value="hexInput"
          @input="onHexInput"
        />
      </div>
      <div class="cp-hex-preview" :style="{ backgroundColor: currentColor }" />
    </div>
  </div>
</template>

<style scoped>
/* ─── Root ────────────────────────────────────────────────────────────────── */
.cp-root {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 12px;
  padding: 14px;
  width: 240px;
  box-shadow:
    0 4px 6px -1px rgba(0, 0, 0, 0.4),
    0 20px 40px -10px rgba(0, 0, 0, 0.6);
  display: flex;
  flex-direction: column;
  gap: 12px;
  user-select: none;
}

/* ─── SV Box ──────────────────────────────────────────────────────────────── */
.cp-sv-box {
  position: relative;
  width: 100%;
  height: 140px;
  border-radius: 7px;
  cursor: crosshair;
  overflow: hidden;
}

.cp-sv-white {
  position: absolute;
  inset: 0;
  background: linear-gradient(to right, #fff, transparent);
}

.cp-sv-black {
  position: absolute;
  inset: 0;
  background: linear-gradient(to top, #000, transparent);
}

.cp-sv-cursor {
  position: absolute;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  border: 2px solid #fff;
  transform: translate(-50%, -50%);
  pointer-events: none;
  box-shadow:
    0 0 0 1px rgba(0, 0, 0, 0.4),
    0 2px 6px rgba(0, 0, 0, 0.5);
}

/* ─── Controles ───────────────────────────────────────────────────────────── */
.cp-controls {
  display: flex;
  align-items: center;
  gap: 10px;
}

.cp-preview {
  width: 28px;
  height: 28px;
  border-radius: 50%;
  flex-shrink: 0;
  border: 2px solid rgba(255, 255, 255, 0.12);
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.3);
}

.cp-hue-wrap {
  flex: 1;
}

.cp-hue-slider {
  -webkit-appearance: none;
  appearance: none;
  width: 100%;
  height: 10px;
  border-radius: 5px;
  background: linear-gradient(
    to right,
    #f00 0%,
    #ff0 17%,
    #0f0 33%,
    #0ff 50%,
    #00f 67%,
    #f0f 83%,
    #f00 100%
  );
  cursor: pointer;
  outline: none;
  border: none;
}

.cp-hue-slider::-webkit-slider-thumb {
  -webkit-appearance: none;
  width: 16px;
  height: 16px;
  border-radius: 50%;
  background: #fff;
  border: 2px solid rgba(255, 255, 255, 0.9);
  box-shadow:
    0 0 0 1px rgba(0, 0, 0, 0.3),
    0 2px 5px rgba(0, 0, 0, 0.4);
  cursor: grab;
}

.cp-hue-slider::-webkit-slider-thumb:active {
  cursor: grabbing;
  transform: scale(1.1);
}

/* ─── Input Hex ───────────────────────────────────────────────────────────── */
.cp-hex-row {
  display: flex;
  align-items: center;
  gap: 10px;
  padding-top: 4px;
  border-top: 1px solid rgb(var(--slate-4));
}

.cp-hex-wrap {
  flex: 1;
  display: flex;
  align-items: center;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 7px;
  padding: 6px 10px;
  gap: 6px;
}

.cp-hex-label {
  @apply text-sm;
  font-weight: 700;
  letter-spacing: 0.08em;
  color: rgb(var(--slate-8));
  flex-shrink: 0;
}

.cp-hex-input {
  background: transparent;
  border: none;
  outline: none;
  color: rgb(var(--slate-12));
  font-family: 'JetBrains Mono', 'Fira Code', 'Courier New', monospace;
  @apply text-sm;
  letter-spacing: 0.05em;
  width: 100%;
  text-transform: uppercase;
}

.cp-hex-preview {
  width: 28px;
  height: 28px;
  border-radius: 7px;
  flex-shrink: 0;
  border: 1px solid rgba(255, 255, 255, 0.08);
  box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.2);
}
</style>
