import { ref, computed } from 'vue';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';

/**
 * usePatientActivePlanItems — carrega itens de planos de tratamento
 * `aprovado` / `em_execucao` que ainda têm sessões pendentes.
 *
 * Roadmap #14.A: viabiliza vincular uma sessão de procedimento a um item
 * específico do plano. O backend já reage automaticamente:
 *   - SessionLog.after_create dispara IncrementTreatmentSessionJob,
 *     que sobe `sessions_done` e move o item para `em_execucao` /
 *     `concluido`. UpdateTreatmentPlanStatusJob atualiza o plano.
 *
 * Uso:
 *   const { ensureLoaded, pendingItemOptions, findItem, refresh } =
 *     usePatientActivePlanItems(patientId);
 *   await ensureLoaded();
 *   // pendingItemOptions: [{ value: itemId, label: "Plano · Procedimento (3/5 sessões)" }]
 */
export function usePatientActivePlanItems(patientId) {
  const plans = ref([]);
  const isLoaded = ref(false);
  const isLoading = ref(false);

  const fetchPlans = async () => {
    if (!patientId) return;
    isLoading.value = true;
    try {
      const { data } = await TreatmentPlansAPI.get(patientId);
      const list = data?.data || data || [];
      plans.value = Array.isArray(list) ? list : [];
      isLoaded.value = true;
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[ActivePlanItems] Falha ao carregar planos', error);
      plans.value = [];
      isLoaded.value = true;
    } finally {
      isLoading.value = false;
    }
  };

  const ensureLoaded = async () => {
    if (isLoaded.value) return;
    await fetchPlans();
  };

  // Recarrega ignorando cache — usar após registrar uma sessão para refletir
  // o novo `sessions_done` no dropdown.
  const refresh = () => fetchPlans();

  // Itens com sessões pendentes em planos ativos. Concluídos/cancelados saem.
  const pendingItems = computed(() => {
    const out = [];
    plans.value.forEach(plan => {
      if (!['aprovado', 'em_execucao'].includes(plan.status)) return;
      (plan.treatment_items || []).forEach(item => {
        if (['concluido', 'cancelado'].includes(item.status)) return;
        const remaining =
          typeof item.remaining_sessions === 'number'
            ? item.remaining_sessions
            : Math.max(
                (item.sessions_planned || 0) - (item.sessions_done || 0),
                0
              );
        if (remaining <= 0) return;
        out.push({
          plan_id: plan.id,
          plan_title: plan.title || `Plano #${plan.id}`,
          item_id: item.id,
          item_name: item.procedure_name,
          sessions_done: item.sessions_done || 0,
          sessions_planned: item.sessions_planned || 0,
          remaining_sessions: remaining,
          status: item.status,
        });
      });
    });
    return out;
  });

  const pendingItemOptions = computed(() =>
    pendingItems.value.map(it => ({
      value: it.item_id,
      label: `${it.plan_title} · ${it.item_name} (${it.sessions_done}/${it.sessions_planned} sessões)`,
      __meta: it,
    }))
  );

  // Lookup: dado um item_id, devolve o registro completo (inclui plan_id).
  // Útil para preencher `treatment_plan_id` no payload de SessionLog.
  const findItem = itemId => {
    if (!itemId) return null;
    return pendingItems.value.find(it => it.item_id === itemId) || null;
  };

  return {
    plans,
    isLoaded,
    isLoading,
    pendingItems,
    pendingItemOptions,
    ensureLoaded,
    refresh,
    findItem,
  };
}
