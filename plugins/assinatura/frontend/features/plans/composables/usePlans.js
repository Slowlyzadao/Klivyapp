import { ref } from 'vue';
import { plansApi } from '../api/plansApi.js';

export function usePlans() {
  const plans = ref([]);
  const loading = ref(false);
  const error = ref(null);

  async function fetchPlans() {
    loading.value = true;
    error.value = null;
    try {
      plans.value = await plansApi.list();
    } catch (e) {
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  }

  async function deletePlan(id) {
    await plansApi.destroy(id);
    plans.value = plans.value.filter(p => p.id !== id);
  }

  function upsertPlan(plan) {
    const idx = plans.value.findIndex(p => p.id === plan.id);
    if (idx >= 0) {
      plans.value[idx] = plan;
    } else {
      plans.value.push(plan);
    }
  }

  return { plans, loading, error, fetchPlans, deletePlan, upsertPlan };
}
