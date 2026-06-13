/**
 * useAppointments — fetch + envio de recall da aba Agenda do paciente.
 *
 *   fetch()                              → carrega lista
 *   sendRecall(patientPhone, patientName)→ envia recall WhatsApp; em falha
 *                                          de API, abre wa.me direto
 *   dismissRecallForever()               → grava recall_dismissed_at no patient
 *
 * Auditoria UX 2026-05-15: `reschedule` e `markNoShow` removidos.
 * Operação da agenda passou a ser exclusiva do calendário principal —
 * elimina duplicação que causava AgendaEvent/PatientAppointment divergentes.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import PatientAppointmentsAPI from '@plugins/patients/frontend/api/patients/appointments';

export function useAppointments(patientIdRef) {
  const { t } = useI18n();

  const appointments = ref([]);
  const isLoading = ref(false);
  const isSendingRecall = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetch = async () => {
    isLoading.value = true;
    try {
      const { data } = await PatientAppointmentsAPI.get(resolveId());
      appointments.value =
        data?.appointments || data?.data || (Array.isArray(data) ? data : []);
    } catch (error) {
      useNotification.error(t('PATIENT_SCHEDULE.MESSAGES.LOAD_ERROR'));
    } finally {
      isLoading.value = false;
    }
  };

  // Fallback: se a API de recall não estiver configurada, abre wa.me direto
  // com mensagem pronta. Sucesso é registrado mas falha não bloqueia o flow.
  const sendRecall = async ({ phone, name } = {}) => {
    isSendingRecall.value = true;
    try {
      await PatientAppointmentsAPI.sendRecall(resolveId());
      useNotification.success(t('PATIENT_SCHEDULE.MESSAGES.RECALL_SUCCESS'));
      await fetch();
      return { ok: true };
    } catch (error) {
      if (phone) {
        const clean = String(phone).replace(/\D/g, '');
        const msg = encodeURIComponent(
          t('PATIENT_SCHEDULE.MESSAGES.RECALL_FALLBACK_MESSAGE', {
            name: name ? ` ${name}` : '',
          })
        );
        window.open(`https://wa.me/${clean}?text=${msg}`, '_blank');
      } else {
        useNotification.info(
          t('PATIENT_SCHEDULE.MESSAGES.RECALL_FALLBACK_NO_PHONE')
        );
      }
      return { ok: false, fallback: true };
    } finally {
      isSendingRecall.value = false;
    }
  };

  // Best-effort: UI já dispensou; backend grava timestamp para persistência
  // entre sessões. Não alerta o usuário se falhar.
  const dismissRecallForever = async () => {
    try {
      await PatientsAPI.update(resolveId(), {
        recall_dismissed_at: new Date().toISOString(),
      });
      return { ok: true };
    } catch (error) {
      return { ok: false };
    }
  };

  return {
    appointments,
    isLoading,
    isSendingRecall,
    fetch,
    sendRecall,
    dismissRecallForever,
  };
}
