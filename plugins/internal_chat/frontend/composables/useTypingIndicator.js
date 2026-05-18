import { onBeforeUnmount } from 'vue';
import TypingAPI from '@plugins/internal_chat/frontend/api/typing';

// Debounce de "typing": 1ª keystroke envia active=true; depois de 3s sem
// novas teclas, envia active=false. Reenvia active=true a cada 4s pra
// renovar (em conversas longas).
export function useTypingIndicator(getRoomId) {
  let lastSentAt = 0;
  let stopTimer = null;

  const sendActive = active => {
    const roomId = typeof getRoomId === 'function' ? getRoomId() : getRoomId;
    if (!roomId) return;
    TypingAPI.set(roomId, active).catch(() => {});
  };

  const onKeystroke = () => {
    const now = Date.now();
    if (now - lastSentAt > 4000) {
      sendActive(true);
      lastSentAt = now;
    }
    if (stopTimer) clearTimeout(stopTimer);
    stopTimer = setTimeout(() => {
      sendActive(false);
      lastSentAt = 0;
    }, 3000);
  };

  const stopNow = () => {
    if (stopTimer) clearTimeout(stopTimer);
    stopTimer = null;
    if (lastSentAt > 0) {
      sendActive(false);
      lastSentAt = 0;
    }
  };

  onBeforeUnmount(stopNow);

  return { onKeystroke, stopNow };
}
