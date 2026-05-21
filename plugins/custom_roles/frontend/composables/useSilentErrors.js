import { useAlert } from 'dashboard/composables';

/**
 * Returns a notifier that suppresses alerts for permission-denied responses.
 * Use it in catch blocks where the failure can be a legitimate 403 from RBAC —
 * e.g. fetching data for a tab the user doesn't have permission to see.
 *
 * Usage:
 *   const notifyError = useSilentErrors();
 *   try { ... } catch (error) { notifyError('Erro ao carregar X.', error); }
 */
export function useSilentErrors() {
  return (message, error) => {
    const status = error?.response?.status;
    if (status === 403 || status === 401) return;
    useAlert(message);
  };
}
