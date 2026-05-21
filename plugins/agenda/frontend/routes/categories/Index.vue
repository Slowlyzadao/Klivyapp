<script setup>
import { ref, watch, nextTick, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useAgendaCategories } from '../../features/categories/composables/useAgendaCategories';
import ColorPicker from '../settings/ColorPicker.vue';

const store = useStore();

const {
  categoryModal,
  categoryDraft,
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
} = useAgendaCategories(store);

const colorPickerTriggerRef = ref(null);
const cpStyle = ref({});

const toggleColorPickerPop = () => {
  showColorPicker.value = !showColorPicker.value;
};

const calculateCPPosition = () => {
  if (!colorPickerTriggerRef.value || !showColorPicker.value) return;
  const rect = colorPickerTriggerRef.value.getBoundingClientRect();
  const spaceBelow = window.innerHeight - rect.bottom;
  const spaceAbove = rect.top;
  const pickerHeight = 220;

  cpStyle.value = {
    position: 'fixed',
    left: `${rect.left}px`,
  };

  if (spaceBelow < pickerHeight && spaceAbove > spaceBelow) {
    cpStyle.value.bottom = `${window.innerHeight - rect.top + 8}px`;
    cpStyle.value.top = 'auto';
  } else {
    cpStyle.value.top = `${rect.bottom + 8}px`;
    cpStyle.value.bottom = 'auto';
  }
};

const handleOutsideClickCP = e => {
  if (!showColorPicker.value) return;
  if (
    colorPickerTriggerRef.value &&
    colorPickerTriggerRef.value.contains(e.target)
  )
    return;
  const popover = document.querySelector('.cat-cp-popover');
  if (popover && popover.contains(e.target)) return;
  showColorPicker.value = false;
};

watch(
  () => showColorPicker.value,
  newVal => {
    if (newVal) {
      nextTick(() => {
        calculateCPPosition();
        window.addEventListener('click', handleOutsideClickCP);
        window.addEventListener('scroll', calculateCPPosition, true);
        window.addEventListener('resize', calculateCPPosition);
      });
    } else {
      window.removeEventListener('click', handleOutsideClickCP);
      window.removeEventListener('scroll', calculateCPPosition, true);
      window.removeEventListener('resize', calculateCPPosition);
    }
  }
);

onMounted(() => {
  store.dispatch('agendaCategories/fetch');
});

onUnmounted(() => {
  window.removeEventListener('click', handleOutsideClickCP);
  window.removeEventListener('scroll', calculateCPPosition, true);
  window.removeEventListener('resize', calculateCPPosition);
});
</script>

<template>
  <div class="categories-root">
    <!-- Header -->
    <div class="cat-header">
      <div class="cat-header-text">
        <h2 class="cat-title">Categorias da Agenda</h2>
        <p class="cat-subtitle">
          Organize seus agendamentos por categoria. Cada categoria tem cor
          própria e aparece como filtro no calendário.
        </p>
      </div>
      <button class="cat-add-btn" @click="openCategoryModal()">
        <i class="i-lucide-plus size-[15px]" />
        <span>Nova categoria</span>
      </button>
    </div>

    <!-- Resumo -->
    <div v-if="categories.length" class="cat-summary">
      <div class="cat-summary-item">
        <span class="cat-summary-num">{{ categories.length }}</span>
        <span class="cat-summary-lbl">
          {{ categories.length === 1 ? 'categoria' : 'categorias' }}
        </span>
      </div>
      <div class="cat-summary-divider" />
      <div class="cat-summary-item">
        <span class="cat-summary-num">{{ totalAppointments }}</span>
        <span class="cat-summary-lbl">
          {{ totalAppointments === 1 ? 'agendamento' : 'agendamentos' }}
        </span>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="categoriesLoading" class="cat-empty">
      <i class="i-lucide-loader-circle animate-spin cat-empty-icon" />
      <p class="cat-empty-title">Carregando categorias...</p>
    </div>

    <!-- Empty state -->
    <div
      v-else-if="!categoriesLoading && categories.length === 0"
      class="cat-empty"
    >
      <div class="cat-empty-icon-wrap">
        <i class="i-lucide-tag cat-empty-icon" />
      </div>
      <h3 class="cat-empty-title">Nenhuma categoria cadastrada</h3>
      <p class="cat-empty-sub">
        Crie sua primeira categoria para organizar e filtrar agendamentos no
        calendário.
      </p>
      <button class="cat-add-btn mt-4" @click="openCategoryModal()">
        <i class="i-lucide-plus size-[15px]" />
        Nova categoria
      </button>
    </div>

    <!-- Cards de categorias -->
    <div v-else class="cat-grid">
      <div
        v-for="category in categories"
        :key="category.id"
        class="cat-card"
        :class="{ 'cat-card--inactive': category.active === false }"
      >
        <div class="cat-card-color" :style="{ background: category.color }" />
        <div class="cat-card-body">
          <div class="cat-card-name">
            {{ category.name }}
            <span v-if="category.active === false" class="cat-card-pill">
              Inativa
            </span>
          </div>
          <div class="cat-card-count">
            <i class="i-lucide-calendar-check size-[12px]" />
            {{ category.appointments_count || 0 }}
            {{
              (category.appointments_count || 0) === 1
                ? 'agendamento'
                : 'agendamentos'
            }}
          </div>
        </div>
        <div class="cat-card-actions">
          <button
            class="cat-action-btn cat-action-edit"
            title="Editar categoria"
            @click="openCategoryModal(category)"
          >
            <i class="i-lucide-pencil size-[14px]" />
          </button>
          <button
            class="cat-action-btn cat-action-del"
            title="Desativar categoria"
            @click="confirmDeleteCategory(category)"
          >
            <i class="i-lucide-trash-2 size-[14px]" />
          </button>
        </div>
      </div>
    </div>

    <!-- ─── Modal: Criar / Editar ─── -->
    <teleport to="body">
      <div
        v-if="categoryModal && categoryDraft"
        class="cat-modal-overlay"
        @click.self="closeCategoryModal"
      >
        <div class="cat-modal-box">
          <div class="cat-modal-header">
            <h3 class="cat-modal-title">
              {{ categoryDraft.id ? 'Editar categoria' : 'Nova categoria' }}
            </h3>
            <button class="cat-modal-close" @click="closeCategoryModal">
              <i class="i-lucide-x size-[16px]" />
            </button>
          </div>
          <div class="cat-modal-body">
            <div class="cat-field">
              <label class="cat-label">Nome da categoria *</label>
              <input
                v-model="categoryDraft.name"
                type="text"
                class="cat-input"
                placeholder="Ex: Particular, Convênio Unimed, Bloqueio..."
                @keydown.enter="saveCategory"
              />
            </div>

            <div class="cat-field">
              <label class="cat-label">Cor de identificação</label>
              <div class="cat-color-picker">
                <button
                  v-for="c in categoryColors"
                  :key="c"
                  type="button"
                  class="cat-color-option"
                  :class="{
                    'cat-color-selected': categoryDraft.color === c,
                  }"
                  :style="{ background: c }"
                  :title="c"
                  @click="
                    categoryDraft.color = c;
                    showColorPicker = false;
                  "
                />
                <button
                  ref="colorPickerTriggerRef"
                  type="button"
                  class="cat-color-option cat-color-custom"
                  :class="{
                    'cat-color-selected': !categoryColors.includes(
                      categoryDraft.color
                    ),
                  }"
                  :style="{
                    background: !categoryColors.includes(categoryDraft.color)
                      ? categoryDraft.color
                      : 'rgb(var(--slate-4))',
                  }"
                  title="Cor personalizada"
                  @click.stop="toggleColorPickerPop"
                >
                  <i
                    class="i-lucide-pipette"
                    :style="{
                      color: !categoryColors.includes(categoryDraft.color)
                        ? 'rgba(255,255,255,0.9)'
                        : 'rgb(var(--slate-9))',
                      fontSize: '12px',
                    }"
                  />
                </button>
                <teleport to="body">
                  <div
                    v-if="showColorPicker"
                    class="cat-cp-popover"
                    :style="cpStyle"
                    @click.stop
                  >
                    <ColorPicker v-model="categoryDraft.color" />
                  </div>
                </teleport>
              </div>
            </div>
          </div>
          <div class="cat-modal-footer">
            <button class="cat-btn-cancel" @click="closeCategoryModal">
              Cancelar
            </button>
            <button
              class="cat-btn-save"
              :disabled="categorySaving || !categoryDraft.name?.trim()"
              @click="saveCategory"
            >
              <i
                v-if="categorySaving"
                class="i-lucide-loader-circle animate-spin size-[14px]"
              />
              <i v-else class="i-lucide-check size-[14px]" />
              {{ categoryDraft.id ? 'Salvar alterações' : 'Criar categoria' }}
            </button>
          </div>
        </div>
      </div>
    </teleport>

    <!-- ─── Modal: Confirmar exclusão ─── -->
    <teleport to="body">
      <div
        v-if="categoryDeleteConfirm"
        class="cat-modal-overlay"
        @click.self="cancelDeleteCategory"
      >
        <div class="cat-modal-box cat-modal-box-sm">
          <div class="cat-modal-header">
            <h3 class="cat-modal-title">Desativar categoria</h3>
            <button class="cat-modal-close" @click="cancelDeleteCategory">
              <i class="i-lucide-x size-[16px]" />
            </button>
          </div>
          <div class="cat-modal-body">
            <p class="cat-del-msg">
              Tem certeza que deseja desativar a categoria
              <strong>{{ categoryDeleteName }}</strong
              >? Eventos antigos continuarão referenciando-a, mas ela não estará
              disponível para novos agendamentos.
            </p>
          </div>
          <div class="cat-modal-footer">
            <button class="cat-btn-cancel" @click="cancelDeleteCategory">
              Cancelar
            </button>
            <button class="cat-btn-danger" @click="deleteCategory">
              <i class="i-lucide-trash-2 size-[14px]" />
              Desativar
            </button>
          </div>
        </div>
      </div>
    </teleport>
  </div>
</template>

<style>
.categories-root {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  overflow-y: auto;
  padding: 24px 28px 120px;
  color: rgb(var(--slate-12));
  box-sizing: border-box;
  gap: 24px;
}

/* Header */
.cat-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  flex-wrap: wrap;
}
.cat-header-text {
  flex: 1;
  min-width: 240px;
}
.cat-title {
  font-size: 18px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0 0 6px 0;
}
.cat-subtitle {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0;
  line-height: 1.5;
  max-width: 720px;
}
.cat-add-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgb(var(--blue-9));
  color: white;
  padding: 8px 14px;
  border-radius: 8px;
  border: none;
  cursor: pointer;
  @apply text-sm;
  font-weight: 600;
  transition: background 0.15s, transform 0.1s;
  white-space: nowrap;
  flex-shrink: 0;
}
.cat-add-btn:hover {
  background: rgb(var(--blue-10));
}

/* Summary */
.cat-summary {
  display: inline-flex;
  align-items: center;
  gap: 14px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 12px 18px;
  align-self: flex-start;
}
.cat-summary-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 2px;
}
.cat-summary-num {
  @apply text-base;
  font-weight: 700;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}
.cat-summary-lbl {
  @apply text-xs;
  font-weight: 500;
  color: rgb(var(--slate-9));
  text-transform: uppercase;
  letter-spacing: 0.05em;
}
.cat-summary-divider {
  width: 1px;
  height: 28px;
  background: rgb(var(--slate-5));
}

/* Cards grid */
.cat-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 12px;
}
.cat-card {
  display: flex;
  align-items: center;
  gap: 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 14px 16px;
  transition: border-color 0.15s, transform 0.1s;
}
.cat-card:hover {
  border-color: rgb(var(--slate-6));
}
.cat-card--inactive {
  opacity: 0.55;
}
.cat-card-color {
  width: 14px;
  height: 14px;
  border-radius: 50%;
  flex-shrink: 0;
  border: 2px solid rgba(255, 255, 255, 0.1);
  box-shadow: 0 0 0 1px rgba(0, 0, 0, 0.25);
}
.cat-card-body {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.cat-card-name {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  display: inline-flex;
  align-items: center;
  gap: 8px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.cat-card-pill {
  @apply text-xs;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  color: rgb(var(--slate-9));
  background: rgb(var(--slate-4));
  padding: 2px 6px;
  border-radius: 4px;
}
.cat-card-count {
  @apply text-xs;
  display: inline-flex;
  align-items: center;
  gap: 4px;
  color: rgb(var(--slate-9));
  font-variant-numeric: tabular-nums;
}
.cat-card-actions {
  display: flex;
  gap: 4px;
  flex-shrink: 0;
}
.cat-action-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  padding: 0;
  background: transparent;
  color: rgb(var(--slate-9));
  transition: background 0.15s, color 0.15s;
}
.cat-action-edit:hover {
  background: rgba(59, 130, 246, 0.1);
  color: rgb(var(--blue-9));
}
.cat-action-del:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #dc2626;
}

/* Empty state */
.cat-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 64px 24px;
  text-align: center;
}
.cat-empty-icon-wrap {
  width: 56px;
  height: 56px;
  border-radius: 16px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
  display: flex;
  align-items: center;
  justify-content: center;
}
.cat-empty-icon {
  font-size: 24px;
  color: rgb(var(--slate-8));
}
.cat-empty-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0;
}
.cat-empty-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  max-width: 380px;
  line-height: 1.5;
  margin: 0;
}

/* Modal */
.cat-modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10000;
  backdrop-filter: blur(3px);
}
.cat-modal-box {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 16px;
  width: 480px;
  max-width: 96vw;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.6);
  overflow: hidden;
}
.cat-modal-box-sm {
  width: 420px;
}
.cat-modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid rgb(var(--slate-5));
  flex-shrink: 0;
}
.cat-modal-title {
  @apply text-sm;
  font-weight: 700;
  color: rgb(var(--slate-12));
}
.cat-modal-close {
  width: 28px;
  height: 28px;
  border-radius: 6px;
  border: none;
  background: transparent;
  color: rgb(var(--slate-9));
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.15s;
}
.cat-modal-close:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.cat-modal-body {
  padding: 20px;
  overflow-y: auto;
  flex: 1;
}
.cat-modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-5));
  flex-shrink: 0;
}
.cat-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 16px;
}
.cat-field:last-child {
  margin-bottom: 0;
}
.cat-label {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  letter-spacing: 0.02em;
  text-transform: uppercase;
}
.cat-input {
  width: 100%;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 9px 12px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  outline: none;
  transition: border-color 0.15s, background 0.15s;
}
.cat-input:focus {
  border-color: rgb(var(--blue-8));
  background: rgb(var(--slate-1));
}

/* Color picker (espelhando padrão dos serviços) */
.cat-color-picker {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  position: relative;
}
.cat-color-option {
  width: 26px;
  height: 26px;
  border-radius: 50%;
  border: 2.5px solid transparent;
  cursor: pointer;
  transition: border-color 0.15s, transform 0.15s;
  padding: 0;
}
.cat-color-option:hover {
  transform: scale(1.15);
}
.cat-color-selected {
  border-color: #fff !important;
  box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.4);
}
.cat-color-custom {
  display: flex;
  align-items: center;
  justify-content: center;
  border-style: dashed;
  border-color: rgb(var(--slate-6));
}
.cat-color-custom:hover {
  border-color: rgb(var(--slate-9));
}
.cat-color-selected.cat-color-custom {
  border-style: solid;
}
.cat-cp-popover {
  z-index: 10005;
}

/* Buttons */
.cat-btn-cancel {
  background: transparent;
  border: 1px solid rgb(var(--slate-6));
  color: rgb(var(--slate-10));
  border-radius: 8px;
  padding: 7px 16px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s;
}
.cat-btn-cancel:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.cat-btn-save {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgb(var(--blue-9));
  color: white;
  border: none;
  border-radius: 8px;
  padding: 7px 16px;
  @apply text-sm;
  font-weight: 700;
  cursor: pointer;
  transition: background 0.15s;
}
.cat-btn-save:hover {
  background: rgb(var(--blue-10));
}
.cat-btn-save:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
.cat-btn-danger {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 7px 16px;
  background: #dc2626;
  color: #fff;
  border: none;
  border-radius: 8px;
  @apply text-sm;
  font-weight: 700;
  cursor: pointer;
  transition: background 0.15s;
}
.cat-btn-danger:hover {
  background: #b91c1c;
}
.cat-del-msg {
  @apply text-sm;
  color: rgb(var(--slate-10));
  line-height: 1.55;
}
</style>
