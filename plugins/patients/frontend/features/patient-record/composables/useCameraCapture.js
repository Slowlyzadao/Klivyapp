/**
 * useCameraCapture — captura de foto via webcam frontal + processamento WebP.
 *
 * Encapsula:
 *   • getUserMedia (com cleanup automático em close/unmount)
 *   • processImageToWebP — crop quadrado central + resize 300x300 + WebP 0.8
 *     (usado tanto no upload de arquivo quanto no resultado da câmera)
 *
 * O componente caller só precisa montar refs `videoElement` e `canvasElement`
 * e ligar os handlers. Stream é encerrado automaticamente em `closeCamera`
 * e em `onBeforeUnmount` (ver caller).
 */

import { ref } from 'vue';

export const processImageToWebP = (fileOrBlob, targetSize = 300) =>
  new Promise((resolve, reject) => {
    const url = URL.createObjectURL(fileOrBlob);
    const img = new Image();
    img.onload = () => {
      URL.revokeObjectURL(url);
      const canvas = document.createElement('canvas');
      const size = Math.min(img.width, img.height);
      const startX = (img.width - size) / 2;
      const startY = (img.height - size) / 2;
      canvas.width = targetSize;
      canvas.height = targetSize;
      const ctx = canvas.getContext('2d');
      ctx.drawImage(img, startX, startY, size, size, 0, 0, targetSize, targetSize);
      canvas.toBlob(
        blob =>
          resolve(
            new File([blob], `avatar_${Date.now()}.webp`, {
              type: 'image/webp',
            })
          ),
        'image/webp',
        0.8
      );
    };
    img.onerror = reject;
    img.src = url;
  });

export function useCameraCapture() {
  const videoElement = ref(null);
  const canvasElement = ref(null);
  const cameraStream = ref(null);
  const cameraError = ref(false);
  const capturedPhoto = ref(null); // dataURL após capturar

  const startCamera = async () => {
    cameraError.value = false;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'user' },
      });
      cameraStream.value = stream;
      if (videoElement.value) {
        videoElement.value.srcObject = stream;
        videoElement.value.play().catch(e => {
          // eslint-disable-next-line no-console
          console.error('Error playing video:', e);
        });
      }
    } catch (err) {
      // eslint-disable-next-line no-console
      console.error('Error accessing camera:', err);
      cameraError.value = true;
    }
  };

  const stopCamera = () => {
    if (cameraStream.value) {
      cameraStream.value.getTracks().forEach(track => track.stop());
      cameraStream.value = null;
    }
  };

  const capturePhoto = () => {
    if (!videoElement.value || !canvasElement.value) return;
    const video = videoElement.value;
    const canvas = canvasElement.value;
    const size = Math.min(video.videoWidth, video.videoHeight);
    const startX = (video.videoWidth - size) / 2;
    const startY = (video.videoHeight - size) / 2;
    const targetSize = 300;
    canvas.width = targetSize;
    canvas.height = targetSize;
    const ctx = canvas.getContext('2d');
    // .cam-video já espelha o preview pro usuário; desenhar o video original
    // aqui e mostrar em <img> sem scaleX(-1) preserva o que o usuário viu.
    ctx.drawImage(video, startX, startY, size, size, 0, 0, targetSize, targetSize);
    capturedPhoto.value = canvas.toDataURL('image/webp', 0.8);
  };

  const retakePhoto = () => {
    capturedPhoto.value = null;
  };

  const dataUrlToFile = async dataUrl => {
    const res = await fetch(dataUrl);
    const blob = await res.blob();
    return new File([blob], `avatar_${Date.now()}.webp`, {
      type: 'image/webp',
    });
  };

  const reset = () => {
    capturedPhoto.value = null;
    cameraError.value = false;
  };

  return {
    videoElement,
    canvasElement,
    cameraStream,
    cameraError,
    capturedPhoto,
    startCamera,
    stopCamera,
    capturePhoto,
    retakePhoto,
    dataUrlToFile,
    reset,
  };
}
