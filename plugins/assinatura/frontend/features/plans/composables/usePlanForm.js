import { reactive, ref } from 'vue';
import { PLAN_COLORS } from '../../../shared/constants.js';
import { plansApi } from '../api/plansApi.js';

function emptyForm() {
  return {
    name: '',
    description: '',
    price_monthly: '',
    price_yearly: '',
    color: PLAN_COLORS[0],
    features: [],
    limits: {},
    active: true,
    display_order: 0,
  };
}

export function usePlanForm(onSuccess) {
  const form = reactive(emptyForm());
  const editingId = ref(null);
  const saving = ref(false);
  const formError = ref(null);

  function openNew() {
    Object.assign(form, emptyForm());
    editingId.value = null;
    formError.value = null;
  }

  function openEdit(plan) {
    Object.assign(form, {
      name:          plan.name,
      description:   plan.description || '',
      price_monthly: plan.price_monthly,
      price_yearly:  plan.price_yearly || '',
      color:         plan.color || PLAN_COLORS[0],
      features:      [...(plan.features || [])],
      limits:        { ...(plan.limits || {}) },
      active:        plan.active,
      display_order: plan.display_order,
    });
    editingId.value = plan.id;
    formError.value = null;
  }

  function toggleFeature(key) {
    const idx = form.features.indexOf(key);
    if (idx >= 0) {
      form.features.splice(idx, 1);
    } else {
      form.features.push(key);
    }
  }

  function buildLimits() {
    const result = {};
    for (const [key, val] of Object.entries(form.limits)) {
      const n = parseInt(val, 10);
      if (!isNaN(n) && n > 0) result[key] = n;
    }
    return result;
  }

  async function save() {
    saving.value = true;
    formError.value = null;
    try {
      const payload = {
        ...form,
        price_monthly: parseFloat(form.price_monthly) || 0,
        price_yearly:  form.price_yearly ? parseFloat(form.price_yearly) : null,
        limits:        buildLimits(),
      };
      const result = editingId.value
        ? await plansApi.update(editingId.value, payload)
        : await plansApi.create(payload);
      onSuccess(result);
    } catch (e) {
      formError.value = e.message;
    } finally {
      saving.value = false;
    }
  }

  return { form, editingId, saving, formError, openNew, openEdit, toggleFeature, save };
}
