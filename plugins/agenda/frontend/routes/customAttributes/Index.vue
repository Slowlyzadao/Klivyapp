<!-- eslint-disable -->
<script>
/* eslint-disable */
import draggable from 'vuedraggable';
import AgendaCustomAttributesAPI from '@plugins/agenda/frontend/api/agendaCustomAttributes';
import ModernSelect from '../../components/ModernSelect.vue';
import DeleteModal from 'dashboard/components/widgets/modal/DeleteModal.vue';

export default {
  name: 'AgendaCustomAttributes',
  components: {
    draggable,
    ModernSelect,
    DeleteModal,
  },
  data() {
    return {
      // Custom attributes ONLY. The "Observação" / description field is a
      // fixed system field rendered separately above this list — never
      // included here, so it never disappears when the API returns custom
      // attrs and never collides with their IDs.
      attributes: [],
      isModalOpen: false,
      editingId: null,
      isSavingOrder: false,
      isDeleting: false,
      attrToDelete: null,
      draft: {
        name: '',
        type: 'text',
        required: false,
        validate_cpf: true,
        options: '',
      },
      attributeTypes: [
        { value: 'text', label: 'Texto Livre', icon: 'i-lucide-type' },
        { value: 'textarea', label: 'Área de Texto', icon: 'i-lucide-align-left' },
        {
          value: 'select',
          label: 'Caixa de Seleção (Dropdown)',
          icon: 'i-lucide-list',
        },
        { value: 'date', label: 'Data', icon: 'i-lucide-calendar' },
        { value: 'phone', label: 'Telefone', icon: 'i-lucide-phone' },
        { value: 'cpf', label: 'CPF', icon: 'i-lucide-contact' },
        { value: 'rg', label: 'RG / Documento', icon: 'i-lucide-id-card' },
      ],
    };
  },
  async mounted() {
    try {
      const { data } = await AgendaCustomAttributesAPI.getAll();
      this.attributes = Array.isArray(data) ? data : [];
    } catch (e) {
      this.attributes = [];
    }
  },
  methods: {
    getTypeLabel(val) {
      const found = this.attributeTypes.find(t => t.value === val);
      return found ? found.label : val;
    },
    getTypeIcon(val) {
      const found = this.attributeTypes.find(t => t.value === val);
      return found ? found.icon : 'i-lucide-file-text';
    },
    openNewModal() {
      this.editingId = null;
      this.draft = { name: '', type: 'text', required: false, validate_cpf: true, options: '' };
      this.isModalOpen = true;
    },
    openEditModal(attr) {
      this.editingId = attr.id;
      this.draft = { validate_cpf: true, ...attr };
      this.isModalOpen = true;
    },
    closeModal() {
      this.isModalOpen = false;
    },
    async saveAttribute() {
      if (!this.draft.name.trim()) return;
      try {
        if (this.editingId) {
          const { data } = await AgendaCustomAttributesAPI.update(this.editingId, {
            name: this.draft.name,
            field_type: this.draft.type,
            required: this.draft.required,
            validate_cpf: this.draft.validate_cpf,
            options: this.draft.options,
          });
          const idx = this.attributes.findIndex(a => a.id === this.editingId);
          if (idx > -1) this.attributes.splice(idx, 1, data);
        } else {
          const { data } = await AgendaCustomAttributesAPI.create({
            name: this.draft.name,
            field_type: this.draft.type,
            required: this.draft.required,
            validate_cpf: this.draft.validate_cpf,
            options: this.draft.options,
          });
          this.attributes.push(data);
        }
      } catch (e) {
        // keep UI consistent — silently fail
      }
      this.closeModal();
    },
    requestDelete(attr) {
      // Open the confirmation modal — the actual delete only happens on
      // confirm. Storing the full attr (not just id) so the modal can show
      // the field name in its message.
      this.attrToDelete = attr;
    },
    cancelDelete() {
      if (this.isDeleting) return;
      this.attrToDelete = null;
    },
    async confirmDelete() {
      if (!this.attrToDelete) return;
      this.isDeleting = true;
      const id = this.attrToDelete.id;
      try {
        await AgendaCustomAttributesAPI.delete(id);
        this.attributes = this.attributes.filter(a => a.id !== id);
        this.attrToDelete = null;
      } catch (e) {
        // silently fail — modal stays open so user knows it didn't work
      } finally {
        this.isDeleting = false;
      }
    },
    async onDragEnd() {
      // Persist new order to backend so it survives reload. The local
      // array is already updated by vuedraggable's v-model; we just
      // mirror its IDs to the API.
      if (this.attributes.length < 2) return;
      this.isSavingOrder = true;
      try {
        const ids = this.attributes.map(a => a.id);
        await AgendaCustomAttributesAPI.reorder(ids);
      } catch (e) {
        // silently fail — local order remains; next reload will sync.
      } finally {
        this.isSavingOrder = false;
      }
    },
  },
};
</script>

<template>
  <div class="settings-root">
    <!-- Header -->
    <div class="flex items-center justify-between mb-6">
      <div>
        <h2 class="section-title mb-0">Atributos Personalizados da Agenda</h2>
        <p class="section-sub-title">
          O campo "Observação" é nativo do agendamento. Crie campos adicionais
          abaixo para enriquecer o cadastro.
        </p>
      </div>
      <button class="add-btn-premium" @click="openNewModal">
        <i class="i-lucide-plus size-4" />
        <span>Adicionar atributo</span>
      </button>
    </div>

    <!-- ── CAMPO DO SISTEMA (Observação) ────────────────────
         Fixo: representa a textarea "Observações" do modal de evento
         (newEvent.description). Não pode ser editado, removido ou
         reordenado para fora desta posição. -->
    <div class="section-label">
      <i class="i-lucide-shield-check size-3.5" />
      <span>Campo do sistema</span>
    </div>
    <div class="rule-item rule-item--system">
      <div class="rule-main">
        <div class="rule-info">
          <div class="rule-icon-sq bg-slate-500/10 text-slate-400">
            <i class="i-lucide-align-left size-4" />
          </div>
          <div class="rule-details">
            <div class="rule-header-row">
              <span class="rule-name">Observação</span>
              <div class="rule-badges">
                <span class="badge-type">Área de Texto</span>
                <span class="badge-system">Padrão</span>
              </div>
            </div>
            <div class="rule-sub-info">
              Aparece como "Observações" no modal de novo evento. Nativo do
              sistema — não pode ser editado nem removido.
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- ── ATRIBUTOS PERSONALIZADOS ───────────────────────── -->
    <div class="section-label section-label--custom">
      <i class="i-lucide-layers size-3.5" />
      <span>Atributos personalizados</span>
      <span v-if="isSavingOrder" class="saving-indicator">
        <i class="i-lucide-loader-2 size-3 spin" />
        Salvando ordem…
      </span>
    </div>

    <!-- Empty state -->
    <div v-if="attributes.length === 0" class="empty-state">
      <i class="i-lucide-layers empty-ico" />
      <p class="empty-title">Nenhum atributo personalizado ainda</p>
      <p class="empty-sub">
        Clique em "+ Adicionar atributo" para criar o primeiro campo
        personalizado.
      </p>
    </div>

    <!-- Drag list -->
    <draggable
      v-else
      v-model="attributes"
      item-key="id"
      class="cards-list"
      handle=".drag-handle"
      :animation="220"
      ghost-class="drag-ghost-card"
      drag-class="drag-active-card"
      chosen-class="drag-chosen-card"
      @end="onDragEnd"
    >
      <template #item="{ element: attr }">
        <div class="rule-item">
          <div class="rule-main">
            <div class="rule-info">
              <button
                type="button"
                class="drag-handle"
                title="Arrastar para reordenar"
                aria-label="Arrastar para reordenar"
              >
                <i class="i-lucide-grip-vertical size-5" />
              </button>
              <div class="rule-icon-sq bg-blue-500/10 text-blue-400">
                <i :class="getTypeIcon(attr.type)" class="size-4" />
              </div>
              <div class="rule-details">
                <div class="rule-header-row">
                  <span class="rule-name">{{ attr.name }}</span>
                  <div class="rule-badges">
                    <span class="badge-type">{{ getTypeLabel(attr.type) }}</span>
                    <span v-if="attr.required" class="badge-required">
                      Obrigatório
                    </span>
                  </div>
                </div>
                <div v-if="attr.type === 'select'" class="rule-sub-info">
                  Opções: {{ attr.options || 'Nenhuma opção definida' }}
                </div>
              </div>
            </div>

            <!-- Ações -->
            <div class="rule-actions">
              <button
                class="action-icon"
                title="Editar"
                @click="openEditModal(attr)"
              >
                <i class="i-lucide-pencil size-4" />
              </button>
              <button
                class="action-icon action-icon--danger"
                title="Excluir"
                @click="requestDelete(attr)"
              >
                <i class="i-lucide-trash-2 size-4" />
              </button>
            </div>
          </div>
        </div>
      </template>
    </draggable>

    <!-- Modal -->
    <teleport to="body">
      <div v-if="isModalOpen" class="modal-overlay" @click.self="closeModal">
        <div class="modal-box" @click.stop>
          <div class="modal-header">
            <span class="modal-title">{{
              editingId ? 'Editar atributo' : 'Novo atributo'
            }}</span>
            <button class="modal-close" @click="closeModal">
              <i class="i-lucide-x size-[16px]" />
            </button>
          </div>
          <div class="modal-body">
            <label class="modal-label">Nome do campo *</label>
            <input
              v-model="draft.name"
              class="modal-input"
              placeholder="Ex: Como conheceu a clínica?"
            />

            <!-- Tipo -->
            <label class="modal-label"
style="margin-top: 14px"
              >Tipo de campo *</label>
            <ModernSelect
              v-model="draft.type"
              :options="attributeTypes"
              class="modal-input"
            />

            <!-- Opções (se for select) -->
            <div v-if="draft.type === 'select'" style="margin-top: 14px">
              <label class="modal-label">Opções (separadas por vírgula)</label>
              <input
                v-model="draft.options"
                class="modal-input"
                placeholder="Ex: Instagram, Google, Indicação"
              />
            </div>

            <!-- Obrigatório -->
            <div class="toggle-field" style="margin-top: 18px">
              <div class="toggle-info">
                <span class="toggle-label">Campo obrigatório</span>
                <span class="toggle-sub"
                  >O agendamento exigirá o preenchimento deste campo</span
                >
              </div>
              <button
                class="toggle-switch"
                :class="{ 'toggle-on': draft.required }"
                @click="draft.required = !draft.required"
              >
                <span class="toggle-thumb" />
              </button>
            </div>

            <!-- Validate CPF -->
            <div v-if="draft.type === 'cpf'" class="toggle-field" style="margin-top: 18px">
              <div class="toggle-info">
                <span class="toggle-label">Verificação de CPF</span>
                <span class="toggle-sub"
                  >Confirmar se o CPF é válido ou não</span
                >
              </div>
              <button
                class="toggle-switch"
                :class="{ 'toggle-on': draft.validate_cpf }"
                @click="draft.validate_cpf = !draft.validate_cpf"
              >
                <span class="toggle-thumb" />
              </button>
            </div>
          </div>

          <div class="modal-footer">
            <button class="modal-btn-cancel" @click="closeModal">
              Cancelar
            </button>
            <button
              class="modal-btn-save"
              :disabled="!draft.name.trim()"
              @click="saveAttribute"
            >
              Salvar atributo
            </button>
          </div>
        </div>
      </div>
    </teleport>

    <!-- Confirmação de exclusão (reutiliza componente compartilhado do dashboard) -->
    <DeleteModal
      :show="!!attrToDelete"
      :title="'Excluir atributo personalizado'"
      :message="'Tem certeza que deseja excluir o campo'"
      :message-value="attrToDelete ? `“${attrToDelete.name}”?` : ''"
      :confirm-text="isDeleting ? 'Excluindo…' : 'Excluir'"
      :reject-text="'Cancelar'"
      :on-confirm="confirmDelete"
      :on-close="cancelDelete"
    />
  </div>
</template>

<style scoped>
/* ───────── ROOT E HEADINGS ───────── */
.settings-root {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 24px 28px 120px;
  color: rgb(var(--slate-12));
  box-sizing: border-box;
}

.section-title {
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0 0 4px 0;
}
.section-sub-title {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0;
}

/* ───────── BOTÕES ───────── */
.add-btn-premium {
  display: inline-flex;
  align-items: center;
  gap: 8px;
  background: transparent;
  color: rgb(var(--blue-9));
  border: 1px solid rgb(var(--blue-9));
  border-radius: 8px;
  padding: 8px 16px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
.add-btn-premium:hover {
  background: rgba(59, 130, 246, 0.1);
}

/* ───────── EMPTY STATE ───────── */
.empty-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 60px 20px;
  background: rgb(var(--slate-2));
  border: 1px dashed rgb(var(--slate-5));
  border-radius: 12px;
  margin-top: 20px;
}
.empty-ico {
  font-size: 40px;
  color: rgb(var(--slate-7));
  margin-bottom: 16px;
}
.empty-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-11));
  margin: 0 0 6px 0;
}
.empty-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0;
  max-width: 320px;
}

/* ───────── SECTION LABELS ───────── */
.section-label {
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: rgb(var(--slate-9));
  margin: 16px 0 8px;
}
.section-label--custom {
  margin-top: 28px;
}
.saving-indicator {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  margin-left: auto;
  font-size: 11px;
  font-weight: 600;
  color: rgb(var(--blue-11));
  text-transform: none;
  letter-spacing: normal;
}
.spin {
  animation: spin 0.8s linear infinite;
}
@keyframes spin {
  to { transform: rotate(360deg); }
}

/* ───────── CARDS LIST ───────── */
.cards-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-top: 4px;
}

.rule-item {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 14px 18px;
  transition: border-color 0.18s ease, background 0.18s ease,
    transform 0.18s ease, box-shadow 0.18s ease;
}
.rule-item:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
}

/* Sistema (não draggable, sem ações) */
.rule-item--system {
  background: rgba(var(--slate-4), 0.4);
  border-style: dashed;
  border-color: rgb(var(--slate-5));
  cursor: default;
}
.rule-item--system:hover {
  background: rgba(var(--slate-4), 0.5);
  border-color: rgb(var(--slate-6));
}
.rule-item--system .rule-info {
  padding-left: 2px;
}

.badge-system {
  font-size: 11px;
  font-weight: 700;
  padding: 2px 8px;
  border-radius: 20px;
  background: rgba(var(--blue-9), 0.12);
  color: rgb(var(--blue-11));
  border: 1px solid rgba(var(--blue-9), 0.25);
}

/* ───────── DRAG VISUAL FEEDBACK ───────── */
.drag-handle {
  cursor: grab;
  margin-right: 12px;
  display: flex;
  align-items: center;
  justify-content: center;
  width: 28px;
  height: 28px;
  border-radius: 6px;
  color: rgb(var(--slate-8));
  background: transparent;
  border: none;
  padding: 0;
  transition: background 0.15s, color 0.15s;
}
.drag-handle:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.drag-handle:active {
  cursor: grabbing;
  background: rgb(var(--slate-5));
}

/* Item sendo arrastado (clone visual seguindo o cursor) */
.drag-active-card {
  cursor: grabbing !important;
  box-shadow: 0 14px 32px rgba(0, 0, 0, 0.25),
    0 0 0 1px rgba(var(--blue-9), 0.4) !important;
  transform: rotate(0.5deg);
  background: rgb(var(--slate-1)) !important;
  border-color: rgba(var(--blue-9), 0.5) !important;
}

/* Placeholder na posição original (espaço fantasma) */
.drag-ghost-card {
  opacity: 0.35;
  background: rgb(var(--slate-3)) !important;
  border-style: dashed !important;
  border-color: rgb(var(--blue-9)) !important;
}

/* Item escolhido (no momento do click antes do drag começar) */
.drag-chosen-card {
  border-color: rgba(var(--blue-9), 0.45) !important;
  background: rgb(var(--slate-3)) !important;
}

.rule-main {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.rule-info {
  display: flex;
  align-items: center;
  gap: 14px;
}

.rule-icon-sq {
  width: 36px;
  height: 36px;
  border-radius: 8px;
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
}

.rule-details {
  display: flex;
  flex-direction: column;
}

.rule-header-row {
  display: flex;
  align-items: center;
  gap: 10px;
}

.rule-name {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
}

.rule-badges {
  display: flex;
  align-items: center;
  gap: 6px;
}

.badge-type {
  @apply text-sm;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 20px;
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-11));
}

.badge-required {
  @apply text-sm;
  font-weight: 600;
  padding: 2px 8px;
  border-radius: 20px;
  background: rgba(239, 68, 68, 0.1);
  color: #ef4444;
}

.rule-sub-info {
  margin-top: 4px;
  @apply text-sm;
  color: rgb(var(--slate-9));
}

.rule-actions {
  display: flex;
  align-items: center;
  gap: 14px;
}

.action-icon {
  padding: 0;
  width: auto;
  height: auto;
  border: none;
  background: transparent;
  color: rgb(var(--slate-9));
  cursor: pointer;
  transition: color 0.15s, transform 0.12s;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}
.action-icon:hover {
  background: transparent;
  color: rgb(var(--slate-12));
  transform: scale(1.08);
}
.action-icon--danger:hover {
  color: #ef4444;
}

/* ───────── MODAL ───────── */
.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.4);
  backdrop-filter: blur(4px);
  z-index: 9999;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.modal-box {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 14px;
  width: 100%;
  max-width: 460px;
  box-shadow: 0 20px 40px rgba(0, 0, 0, 0.3);
  display: flex;
  flex-direction: column;
}
.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid rgb(var(--slate-5));
}
.modal-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.modal-close {
  background: transparent;
  border: none;
  color: rgb(var(--slate-9));
  cursor: pointer;
  padding: 4px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.15s;
}
.modal-close:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}

.modal-body {
  padding: 20px;
  display: flex;
  flex-direction: column;
}
.modal-label {
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: rgb(var(--slate-9));
  margin-bottom: 6px;
  display: block;
}
.modal-input {
  width: 100%;
  box-sizing: border-box;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 500;
  padding: 8px 12px;
  outline: none;
  transition: border-color 0.15s;
}
.modal-input:focus {
  border-color: rgb(var(--blue-9));
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-5));
}

.modal-btn-cancel {
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
.modal-btn-cancel:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.modal-btn-save {
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
.modal-btn-save:hover {
  background: rgb(var(--blue-10));
}
.modal-btn-save:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}

/* ───────── TOGGLES ───────── */
.toggle-field {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.toggle-info {
  display: flex;
  flex-direction: column;
}
.toggle-label {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.toggle-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin-top: 2px;
}
.toggle-switch {
  position: relative;
  width: 44px;
  height: 24px;
  background: rgb(var(--slate-6));
  border-radius: 12px;
  border: none;
  cursor: pointer;
  transition: background 0.2s;
  flex-shrink: 0;
}
.toggle-switch.toggle-on {
  background: rgb(var(--blue-9));
}
.toggle-thumb {
  position: absolute;
  top: 3px;
  left: 3px;
  width: 18px;
  height: 18px;
  background: #fff;
  border-radius: 50%;
  transition: transform 0.2s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
}
.toggle-switch.toggle-on .toggle-thumb {
  transform: translateX(20px);
}
</style>
