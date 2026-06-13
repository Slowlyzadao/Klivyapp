<template>
  <canvas ref="canvasRef" class="pp-qr" :aria-label="`QR code para pagamento de ${value.slice(0, 12)}…`" />
</template>

<script setup>
import { onMounted, ref, watch } from 'vue';
import QRCode from 'qrcode';

const props = defineProps({
  value: { type: String, required: true },
  size:  { type: Number, default: 256 }
});

const canvasRef = ref(null);

async function render() {
  if (!canvasRef.value || !props.value) return;
  try {
    await QRCode.toCanvas(canvasRef.value, props.value, {
      width: props.size,
      margin: 1,
      color: { dark: '#0f172a', light: '#ffffff' }
    });
  } catch (e) {
    // Falha silenciosa — a página exibe fallback (copia-cola).
    console.warn('[QrCanvas] render falhou', e);
  }
}

onMounted(render);
watch(() => [props.value, props.size], render);
</script>

<style scoped>
.pp-qr { display: block; max-width: 100%; height: auto; border-radius: 12px; }
</style>
