import { ref, computed } from 'vue';
import { useAlert } from 'dashboard/composables';

export function useAgendaCategories(store) {
  const categoryModal = ref(false);
  const categoryDraft = ref(null);
  const categoryDeleteId = ref(null);
  const categoryDeleteName = ref('');
  const categoryDeleteConfirm = ref(false);
  const categorySaving = ref(false);
  const showColorPicker = ref(false);

  // Mesma paleta usada em Serviços para manter consistência visual entre as
  // duas entidades. Se o produto evoluir para um conjunto compartilhado,
  // extrair daqui — por enquanto duplicar a constante (10 cores) é o caminho
  // mais barato.
  const categoryColors = ref([
    '#3b82f6',
    '#22c55e',
    '#f59e0b',
    '#ef4444',
    '#a855f7',
    '#ec4899',
    '#14b8a6',
    '#f97316',
    '#6366f1',
    '#64748b',
  ]);

  const categories = computed(() => {
    return store.getters['agendaCategories/allCategories'] || [];
  });

  const categoriesLoading = computed(() => {
    return store.getters['agendaCategories/getUIFlags'].isFetching;
  });

  const totalAppointments = computed(() => {
    return categories.value.reduce(
      (acc, c) => acc + (c.appointments_count || 0),
      0
    );
  });

  const openCategoryModal = (category = null) => {
    if (category) {
      categoryDraft.value = { ...category };
    } else {
      categoryDraft.value = {
        name: '',
        color: '#3b82f6',
        active: true,
      };
    }
    categoryModal.value = true;
  };

  const closeCategoryModal = () => {
    categoryModal.value = false;
    categoryDraft.value = null;
    showColorPicker.value = false;
  };

  const saveCategory = async () => {
    if (!categoryDraft.value) return;
    if (!categoryDraft.value.name?.trim()) return;
    categorySaving.value = true;
    try {
      if (categoryDraft.value.id) {
        const { id, ...data } = categoryDraft.value;
        await store.dispatch('agendaCategories/update', { id, ...data });
        useAlert('Categoria atualizada com sucesso!');
      } else {
        await store.dispatch('agendaCategories/create', categoryDraft.value);
        useAlert('Categoria criada com sucesso!');
      }
      closeCategoryModal();
    } catch (e) {
      useAlert('Falha ao salvar a categoria.');
    } finally {
      categorySaving.value = false;
    }
  };

  const confirmDeleteCategory = (category) => {
    categoryDeleteId.value = category.id;
    categoryDeleteName.value = category.name;
    categoryDeleteConfirm.value = true;
  };

  const cancelDeleteCategory = () => {
    categoryDeleteId.value = null;
    categoryDeleteName.value = '';
    categoryDeleteConfirm.value = false;
  };

  const deleteCategory = async () => {
    if (!categoryDeleteId.value) return;
    try {
      await store.dispatch('agendaCategories/delete', categoryDeleteId.value);
      useAlert('Categoria desativada.');
      cancelDeleteCategory();
    } catch (e) {
      useAlert('Falha ao desativar a categoria.');
    }
  };

  return {
    categoryModal,
    categoryDraft,
    categoryDeleteId,
    categoryDeleteName,
    categoryDeleteConfirm,
    categorySaving,
    showColorPicker,
    categoryColors,
    categories,
    categoriesLoading,
    totalAppointments,
    openCategoryModal,
    closeCategoryModal,
    saveCategory,
    confirmDeleteCategory,
    cancelDeleteCategory,
    deleteCategory,
  };
}
