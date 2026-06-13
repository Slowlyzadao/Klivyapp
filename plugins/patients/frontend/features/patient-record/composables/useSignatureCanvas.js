/**
 * useSignatureCanvas — captura de assinatura via canvas (mouse + touch).
 *
 * O caller monta o ref `canvasRef` no <canvas> e liga handlers
 * (onMousedown=startDrawing, onMousemove=draw, etc.). `clear()` limpa o
 * canvas e zera o flag `hasSignature`.
 *
 *   toDataURL(mime, quality)  → exporta imagem (default WebP 0.85;
 *                               browsers antigos caem pra PNG automaticamente).
 */

import { ref } from 'vue';

export function useSignatureCanvas() {
  const canvasRef = ref(null);
  const isDrawing = ref(false);
  const hasSignature = ref(false);

  let lastX = 0;
  let lastY = 0;

  const getCoords = (canvas, e) => {
    const rect = canvas.getBoundingClientRect();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const clientY = e.touches ? e.touches[0].clientY : e.clientY;
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    return {
      x: (clientX - rect.left) * scaleX,
      y: (clientY - rect.top) * scaleY,
    };
  };

  const startDrawing = e => {
    if (!canvasRef.value) return;
    isDrawing.value = true;
    const coords = getCoords(canvasRef.value, e);
    lastX = coords.x;
    lastY = coords.y;
  };

  const draw = e => {
    if (!isDrawing.value || !canvasRef.value) return;
    e.preventDefault();
    const canvas = canvasRef.value;
    const ctx = canvas.getContext('2d');
    const coords = getCoords(canvas, e);
    ctx.beginPath();
    ctx.moveTo(lastX, lastY);
    ctx.lineTo(coords.x, coords.y);
    ctx.strokeStyle = '#60a5fa';
    ctx.lineWidth = 2.5;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.stroke();
    lastX = coords.x;
    lastY = coords.y;
    hasSignature.value = true;
  };

  const stopDrawing = () => {
    isDrawing.value = false;
  };

  const clear = () => {
    if (!canvasRef.value) return;
    const canvas = canvasRef.value;
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    hasSignature.value = false;
  };

  const toDataURL = (mime = 'image/webp', quality = 0.85) => {
    if (!canvasRef.value) return '';
    return canvasRef.value.toDataURL(mime, quality);
  };

  return {
    canvasRef,
    hasSignature,
    startDrawing,
    draw,
    stopDrawing,
    clear,
    toDataURL,
  };
}
