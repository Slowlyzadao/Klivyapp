/**
 * useMediaLightbox — abre/fecha lightbox + ESC keyboard.
 *
 * Mount/unmount cuidados pelo caller via `attachKeyboard`/`detachKeyboard`
 * (ou via onMounted/onUnmounted no componente que renderiza o lightbox).
 */

import { ref } from 'vue';

export function useMediaLightbox() {
  const lightboxMedia = ref(null);

  const open = media => {
    lightboxMedia.value = media;
  };

  const close = () => {
    lightboxMedia.value = null;
  };

  const handleKey = e => {
    if (e.key === 'Escape') lightboxMedia.value = null;
  };

  const attachKeyboard = () => {
    window.addEventListener('keydown', handleKey);
  };

  const detachKeyboard = () => {
    window.removeEventListener('keydown', handleKey);
  };

  return {
    lightboxMedia,
    open,
    close,
    attachKeyboard,
    detachKeyboard,
  };
}
