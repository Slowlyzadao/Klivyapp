/**
 * useConsents — fetch + mutations da aba Consentimentos.
 *
 *   fetch()                      → carrega lista
 *   create(payload)              → cria + refresh
 *   sign(consentId, dataUrl)     → POST com base64 da assinatura
 *   sendRemote(consentId)        → envia link WhatsApp
 *   revoke(consentId)            → revoga (com confirm)
 *   loadDetailIfSigned(consent)  → busca detalhes (hash, IP, blob) para
 *                                  consentimentos assinados; best-effort.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import ConsentsAPI from '@plugins/patients/frontend/api/patients/consents';

export function useConsents(patientIdRef) {
  const { t } = useI18n();

  const consents = ref([]);
  const isLoading = ref(false);
  const isSubmitting = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetch = async () => {
    isLoading.value = true;
    try {
      const res = await ConsentsAPI.get(resolveId());
      consents.value = res.data?.data || res.data || [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Consents] Falha ao carregar lista', error);
      useNotification.error(t('PATIENT_CONSENTS.MESSAGES.LOAD_ERROR'));
    } finally {
      isLoading.value = false;
    }
  };

  const create = async payload => {
    if (!payload?.document_type || !payload?.title) {
      useNotification.warning(t('PATIENT_CONSENTS.MESSAGES.MISSING_TYPE'));
      return { ok: false };
    }
    isSubmitting.value = true;
    try {
      await ConsentsAPI.create(resolveId(), payload);
      await fetch();
      useNotification.success(t('PATIENT_CONSENTS.MESSAGES.CREATE_SUCCESS'));
      return { ok: true };
    } catch (error) {
      const detail =
        error?.response?.data?.error ||
        t('PATIENT_CONSENTS.MESSAGES.CREATE_ERROR_FALLBACK');
      useNotification.error(
        t('PATIENT_CONSENTS.MESSAGES.CREATE_ERROR_PREFIX', { detail })
      );
      return { ok: false };
    } finally {
      isSubmitting.value = false;
    }
  };

  const sign = async (consentId, dataUrl) => {
    if (!dataUrl) {
      useNotification.warning(t('PATIENT_CONSENTS.MESSAGES.SIGN_MISSING'));
      return { ok: false };
    }
    isSubmitting.value = true;
    try {
      await ConsentsAPI.sign(resolveId(), consentId, dataUrl);
      await fetch();
      useNotification.success(t('PATIENT_CONSENTS.MESSAGES.SIGN_SUCCESS'));
      return { ok: true };
    } catch (error) {
      const detail =
        error?.response?.data?.error ||
        t('PATIENT_CONSENTS.MESSAGES.CREATE_ERROR_FALLBACK');
      useNotification.error(
        t('PATIENT_CONSENTS.MESSAGES.SIGN_ERROR_PREFIX', { detail })
      );
      return { ok: false };
    } finally {
      isSubmitting.value = false;
    }
  };

  const sendRemote = async consentId => {
    try {
      await ConsentsAPI.sendRemote(resolveId(), consentId);
      useNotification.success(
        t('PATIENT_CONSENTS.MESSAGES.SEND_REMOTE_SUCCESS')
      );
      return { ok: true };
    } catch (error) {
      useNotification.error(t('PATIENT_CONSENTS.MESSAGES.SEND_REMOTE_ERROR'));
      return { ok: false };
    }
  };

  const revoke = async consentId => {
    // eslint-disable-next-line no-alert
    if (!window.confirm(t('PATIENT_CONSENTS.MESSAGES.REVOKE_CONFIRM'))) {
      return { ok: false };
    }
    try {
      await ConsentsAPI.revoke?.(resolveId(), consentId);
      await fetch();
      useNotification.info(t('PATIENT_CONSENTS.MESSAGES.REVOKE_SUCCESS'));
      return { ok: true };
    } catch (error) {
      useNotification.error(t('PATIENT_CONSENTS.MESSAGES.REVOKE_ERROR'));
      return { ok: false };
    }
  };

  // Best-effort: se o fetch detalhado falhar, retorna o consent original
  // sem alerta — caller continua mostrando dados básicos.
  const loadDetailIfSigned = async consent => {
    if (consent?.status !== 'signed') return consent;
    try {
      const { data } = await ConsentsAPI.show(resolveId(), consent.id);
      return data;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Consents] Falha ao carregar detalhes', error);
      return consent;
    }
  };

  return {
    consents,
    isLoading,
    isSubmitting,
    fetch,
    create,
    sign,
    sendRemote,
    revoke,
    loadDetailIfSigned,
  };
}
