import { reactive, ref } from 'vue';
import { couponsApi } from '../api/couponsApi.js';

function emptyForm() {
  return {
    code: '',
    description: '',
    kind: 'trial',
    discount_percent: '',
    discount_amount: '',
    trial_days: '',
    months_duration: '',
    active: true,
    max_uses: '',
    expires_at: '',
  };
}

function randomCode(length = 8) {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  return Array.from({ length }, () => chars[Math.floor(Math.random() * chars.length)]).join('');
}

export function useCouponForm(onSuccess) {
  const form = reactive(emptyForm());
  const editingId = ref(null);
  const saving = ref(false);
  const formError = ref(null);

  function openNew() {
    Object.assign(form, emptyForm());
    form.code = randomCode();
    editingId.value = null;
    formError.value = null;
  }

  function openEdit(coupon) {
    Object.assign(form, {
      code:             coupon.code,
      description:      coupon.description,
      kind:             coupon.kind,
      discount_percent: coupon.discount_percent || '',
      discount_amount:  coupon.discount_amount || '',
      trial_days:       coupon.trial_days || '',
      months_duration:  coupon.months_duration || '',
      active:           coupon.active,
      max_uses:         coupon.max_uses || '',
      expires_at:       coupon.expires_at
        ? coupon.expires_at.substring(0, 10)
        : '',
    });
    editingId.value = coupon.id;
    formError.value = null;
  }

  function generateCode() {
    form.code = randomCode();
  }

  async function save() {
    saving.value = true;
    formError.value = null;
    try {
      const payload = {
        code:             form.code,
        description:      form.description,
        kind:             form.kind,
        discount_percent: form.discount_percent ? parseInt(form.discount_percent) : null,
        discount_amount:  form.discount_amount ? parseFloat(form.discount_amount) : null,
        trial_days:       form.trial_days ? parseInt(form.trial_days) : null,
        months_duration:  form.months_duration ? parseInt(form.months_duration) : null,
        active:           form.active,
        max_uses:         form.max_uses ? parseInt(form.max_uses) : null,
        expires_at:       form.expires_at || null,
      };
      const result = editingId.value
        ? await couponsApi.update(editingId.value, payload)
        : await couponsApi.create(payload);
      onSuccess(result);
    } catch (e) {
      formError.value = e.message;
    } finally {
      saving.value = false;
    }
  }

  return { form, editingId, saving, formError, openNew, openEdit, generateCode, save };
}
