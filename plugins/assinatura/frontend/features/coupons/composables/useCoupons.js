import { ref } from 'vue';
import { couponsApi } from '../api/couponsApi.js';

export function useCoupons() {
  const coupons = ref([]);
  const loading = ref(false);
  const error = ref(null);

  async function fetchCoupons() {
    loading.value = true;
    error.value = null;
    try {
      coupons.value = await couponsApi.list();
    } catch (e) {
      error.value = e.message;
    } finally {
      loading.value = false;
    }
  }

  async function deleteCoupon(id) {
    await couponsApi.destroy(id);
    coupons.value = coupons.value.filter(c => c.id !== id);
  }

  function upsertCoupon(coupon) {
    const idx = coupons.value.findIndex(c => c.id === coupon.id);
    if (idx >= 0) {
      coupons.value[idx] = coupon;
    } else {
      coupons.value.unshift(coupon);
    }
  }

  return { coupons, loading, error, fetchCoupons, deleteCoupon, upsertCoupon };
}
