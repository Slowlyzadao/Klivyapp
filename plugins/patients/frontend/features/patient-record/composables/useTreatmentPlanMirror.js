import { ref, computed } from 'vue';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';

// Mirror leve dos planos de tratamento, usado pela aba Geral para exibir
// `activePlanSummary`. A aba "Plano de Tratamento" mantém seu próprio state
// completo em tabs/TreatmentPlanTab.vue. Após editar plano lá, F5 sincroniza
// este mirror.
export function useTreatmentPlanMirror(patientId) {
  const treatmentPlans = ref([]);

  const fetchTreatmentPlans = async () => {
    try {
      const { data } = await TreatmentPlansAPI.get(patientId);
      treatmentPlans.value = data?.data || data || [];
    } catch (error) {
      // Best-effort: aba "Plano de Tratamento" é a fonte oficial e mostra
      // alerta proper se o fetch falhar. Aqui é só mirror — só logamos.
      // eslint-disable-next-line no-console
      console.error('[Patient] Falha ao carregar mirror de planos', error);
    }
  };

  const activePlanSummary = computed(() => {
    if (!treatmentPlans.value?.length) return null;
    const found = treatmentPlans.value.find(
      p => p.status === 'in_progress' || p.status === 'approved'
    );
    return found || treatmentPlans.value[0] || null;
  });

  return { treatmentPlans, fetchTreatmentPlans, activePlanSummary };
}
