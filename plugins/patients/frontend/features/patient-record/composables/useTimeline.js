/**
 * useTimeline — fetch read-only dos eventos consolidados do paciente.
 *
 * Backend agrega eventos de múltiplos modules (consultas, prontuário,
 * financeiro, documentos) em um único stream ordenado por `occurred_at`.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import PatientTimelineAPI from '@plugins/patients/frontend/api/patients/patientTimeline';

export function useTimeline(patientIdRef) {
  const { t } = useI18n();

  const events = ref([]);
  const isLoading = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetch = async () => {
    isLoading.value = true;
    try {
      const response = await PatientTimelineAPI.get(resolveId());
      events.value = Array.isArray(response.data?.events)
        ? response.data.events
        : [];
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Timeline] Falha ao carregar eventos', error);
      useNotification.error(t('PATIENT_TIMELINE.MESSAGES.LOAD_ERROR'));
    } finally {
      isLoading.value = false;
    }
  };

  return { events, isLoading, fetch };
}
