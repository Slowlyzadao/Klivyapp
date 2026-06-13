/**
 * useNotification — composable de toast com variantes semânticas.
 *
 * Roadmap #10 (forward-compat, sem tocar Chatwoot core):
 *
 * O Chatwoot expõe `useAlert(message, action)` mas a UI do
 * `Snackbar.vue` é sempre slate dark — sem distinção visual entre
 * sucesso/erro/aviso/info. Para variantes coloridas seria preciso
 * mexer no `Snackbar.vue`/`SnackbarContainer.vue` do core.
 *
 * Estratégia escolhida: encadear no evento `newToastMessage` existente
 * (zero mudança no core) e codificar a variante via:
 *   1. Emoji prefix no `message` (✓ ✕ ⚠ ℹ) — visual cue imediato.
 *   2. Duration ajustada por severidade (erros ficam mais tempo).
 *
 * Quando o core for migrado para suportar variantes nativamente,
 * basta atualizar este composable — os call-sites em plugins não
 * precisam mudar.
 *
 * Uso:
 *   import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
 *
 *   useNotification.success('Plano salvo com sucesso!');
 *   useNotification.error('Falha ao gravar consentimento.');
 *   useNotification.warning('Item já vencido.');
 *   useNotification.info('Aprovação pendente.');
 *
 *   // Com action (link / callback) — passa direto pra Snackbar:
 *   useNotification.info('Paciente criado', {
 *     action: { type: 'link', to: '/pacientes/123', message: 'Abrir' },
 *   });
 *
 *   // Duration custom:
 *   useNotification.error('Erro crítico', { duration: 8000 });
 *
 *   // API neutra (sem variante) — equivalente ao useAlert:
 *   useNotification('Mensagem genérica');
 */

import { emitter } from 'shared/helpers/mitt';

const VARIANT_CONFIG = {
  success: { prefix: '✓ ', defaultDuration: 2500 },
  error: { prefix: '✕ ', defaultDuration: 5000 },
  warning: { prefix: '⚠ ', defaultDuration: 4000 },
  info: { prefix: 'ℹ ', defaultDuration: 3000 },
  neutral: { prefix: '', defaultDuration: 2500 },
};

function emitToast(message, { variant = 'neutral', duration, action = null } = {}) {
  const cfg = VARIANT_CONFIG[variant] || VARIANT_CONFIG.neutral;
  const finalMessage = `${cfg.prefix}${message}`;
  const finalDuration = duration || cfg.defaultDuration;

  // O SnackbarContainer.vue do core lê `action.duration` para o tempo de
  // exibição. Mesclamos a duration no objeto action sem perder os outros
  // campos (link/callback).
  const finalAction = action ? { ...action, duration: finalDuration } : { duration: finalDuration };

  emitter.emit('newToastMessage', { message: finalMessage, action: finalAction });
}

// API base: chamada direta como função (compat. com `useAlert` quando o caller
// não precisa de variante).
const useNotification = (message, opts) => emitToast(message, opts);

useNotification.success = (message, opts = {}) =>
  emitToast(message, { ...opts, variant: 'success' });

useNotification.error = (message, opts = {}) =>
  emitToast(message, { ...opts, variant: 'error' });

useNotification.warning = (message, opts = {}) =>
  emitToast(message, { ...opts, variant: 'warning' });

useNotification.info = (message, opts = {}) =>
  emitToast(message, { ...opts, variant: 'info' });

export { useNotification };
export default useNotification;
