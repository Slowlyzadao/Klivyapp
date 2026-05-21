/**
 * useSessionLogs — fetch + mutações da Evolução (procedimentos + evolução clínica unificados).
 *
 *   fetch(filterParams?)             → carrega lista (opcionalmente filtrada)
 *   create(payload, override?)       → cria sessão (caller cuida do clinical guard)
 *   update(id, payload)              → edição em janela draft
 *   sign(id)                         → profissional assina (draft → signed)
 *   markErratum(id, reason)          → marca como errata (signed → erratum)
 *   remove(id)                       → soft delete + refetch
 *   sendPatientSignatureLink(id, …)  → gera token remoto (link)
 *   signPatientLocally(id, blob, …)  → assinatura do paciente em canvas local
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import SessionLogsAPI from '@plugins/patients/frontend/api/patients/sessionLogs';

export function useSessionLogs(patientIdRef) {
  const { t } = useI18n();

  const sessionLogs = ref([]);
  const isLoading = ref(false);
  const isSaving = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const extractList = data =>
    Array.isArray(data) ? data : data?.data || data?.payload || [];

  const fetch = async (params = {}) => {
    isLoading.value = true;
    try {
      const { data } = await SessionLogsAPI.get(resolveId(), params);
      sessionLogs.value = extractList(data);
      return { ok: true, count: sessionLogs.value.length };
    } catch (error) {
      useNotification.error(t('PATIENT_EVOLUTION.MESSAGES.LOAD_ERROR'));
      return { ok: false };
    } finally {
      isLoading.value = false;
    }
  };

  const filter = async filterValues => {
    const params = {};
    if (filterValues.procedure_name) {
      params.procedure_name = filterValues.procedure_name;
    }
    if (filterValues.date_from) params.from = filterValues.date_from;
    if (filterValues.date_to) params.to = filterValues.date_to;

    isLoading.value = true;
    try {
      const { data } = await SessionLogsAPI.get(resolveId(), params);
      sessionLogs.value = extractList(data);
      useNotification.info(
        t('PATIENT_EVOLUTION.MESSAGES.FILTER_RESULTS', {
          count: sessionLogs.value.length,
        })
      );
      return { ok: true };
    } catch (error) {
      useNotification.error(t('PATIENT_EVOLUTION.MESSAGES.FILTER_ERROR'));
      return { ok: false };
    } finally {
      isLoading.value = false;
    }
  };

  const create = async (payload, { clinicalOverrideReason = null } = {}) => {
    isSaving.value = true;
    try {
      const finalPayload = { ...payload };
      if (clinicalOverrideReason) {
        finalPayload.clinical_override_reason = clinicalOverrideReason;
      }
      const { data } = await SessionLogsAPI.create(resolveId(), finalPayload);
      useNotification.success(t('PATIENT_EVOLUTION.MESSAGES.SAVE_SUCCESS'));
      await fetch();
      return { ok: true, sessionLog: data };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.SAVE_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  const update = async (id, payload) => {
    isSaving.value = true;
    try {
      const { data } = await SessionLogsAPI.update(resolveId(), id, payload);
      useNotification.success(t('PATIENT_EVOLUTION.MESSAGES.UPDATE_SUCCESS'));
      await fetch();
      return { ok: true, sessionLog: data };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.SAVE_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  const sign = async id => {
    isSaving.value = true;
    try {
      await SessionLogsAPI.sign(resolveId(), id);
      useNotification.success(t('PATIENT_EVOLUTION.MESSAGES.SIGN_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.SIGN_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  const markErratum = async (id, reason) => {
    isSaving.value = true;
    try {
      await SessionLogsAPI.markErratum(resolveId(), id, reason);
      useNotification.success(t('PATIENT_EVOLUTION.MESSAGES.ERRATUM_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.ERRATUM_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  const remove = async id => {
    try {
      await SessionLogsAPI.delete(resolveId(), id);
      useNotification.success(t('PATIENT_EVOLUTION.MESSAGES.DELETE_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.DELETE_ERROR');
      useNotification.error(msg);
      return { ok: false };
    }
  };

  const signPatientLocally = async (id, blob, deviceInfo = null) => {
    isSaving.value = true;
    try {
      await SessionLogsAPI.signPatientLocally(resolveId(), id, {
        signature: blob,
        deviceInfo,
      });
      useNotification.success(
        t('PATIENT_EVOLUTION.MESSAGES.PATIENT_SIGN_SUCCESS')
      );
      await fetch();
      return { ok: true };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.PATIENT_SIGN_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  const sendPatientSignatureLink = async (id, payload = {}) => {
    isSaving.value = true;
    try {
      const { data } = await SessionLogsAPI.sendPatientRemoteSignatureLink(
        resolveId(),
        id,
        payload
      );
      useNotification.success(
        t('PATIENT_EVOLUTION.MESSAGES.REMOTE_LINK_SUCCESS')
      );
      await fetch();
      return { ok: true, data };
    } catch (error) {
      const msg =
        error?.response?.data?.error ||
        t('PATIENT_EVOLUTION.MESSAGES.REMOTE_LINK_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      isSaving.value = false;
    }
  };

  return {
    sessionLogs,
    isLoading,
    isSaving,
    fetch,
    filter,
    create,
    update,
    sign,
    markErratum,
    remove,
    signPatientLocally,
    sendPatientSignatureLink,
  };
}
