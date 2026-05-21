import { ref } from 'vue';
import klivyRolesApi from '../api/klivyRolesApi.js';

export function useRolesList() {
  const roles = ref([]);
  const isLoading = ref(false);
  const error = ref(null);

  const load = async () => {
    isLoading.value = true;
    error.value = null;
    try {
      const { data } = await klivyRolesApi.list();
      roles.value = data;
    } catch (e) {
      error.value = e;
      roles.value = [];
    } finally {
      isLoading.value = false;
    }
  };

  const remove = async id => {
    await klivyRolesApi.delete(id);
    roles.value = roles.value.filter(r => r.id !== id);
  };

  return { roles, isLoading, error, load, remove };
}
