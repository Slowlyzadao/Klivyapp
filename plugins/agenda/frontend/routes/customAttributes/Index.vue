<!-- eslint-disable -->
<script>
/* eslint-disable */
import draggable from 'vuedraggable';
import AgendaCustomAttributesAPI from '@plugins/agenda/frontend/api/agendaCustomAttributes';
import ModernSelect from '../../components/ModernSelect.vue';

export default {
  name: 'AgendaCustomAttributes',
  components: {
    draggable,
    ModernSelect,
  },
  data() {
    return {
      attributes: [
        {
          id: 1,
          name: 'Observação',
          type: 'textarea',
          required: false,
          options: '',
        },
      ],
      isModalOpen: false,
      editingId: null,
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
      if (data && data.length) this.attributes = data;
    } catch (e) {
      // keep default
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
    async deleteAttribute(id) {
      try {
        await AgendaCustomAttributesAPI.delete(id);
        this.attributes = this.attributes.filter(a => a.id !== id);
      } catch (e) {
        // silently fail
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
          Crie novos campos para enriquecer o cadastro de agendamentos.
        </p>
      </div>
      <button class="add-btn-premium" @click="openNewModal">
        <i class="i-lucide-plus size-4" />
        <span>Adicionar atributo</span>
      </button>
    </div>

    <!-- Empty state -->
    <div v-if="attributes.length === 0" class="empty-state">
      <i class="i-lucide-layers empty-ico" />
      <p class="empty-title">Nenhum atributo criado ainda</p>
      <p class="empty-sub">
        Clique em "+ Adicionar atributo" para criar o primeiro campo
        personalizado.
      </p>
    </div>

    <!-- Grid de cards -->
    <draggable v-else v-model="attributes" item-key="id" class="cards-list" handle=".drag-handle" :animation="200">
      <template #item="{ element: attr }">
        <div class="rule-item">
          <div class="rule-main">
            <!-- Ícone de Drag e Info principal -->
            <div class="rule-info">
              <div class="drag-handle" style="cursor: grab; margin-right: 12px; display: flex; align-items: center; color: rgb(var(--slate-8));">
                <i class="i-lucide-grip-vertical size-5" />
              </div>
              <div class="rule-icon-sq bg-blue-500/10 text-blue-400">
                <i :class="getTypeIcon(attr.type)" class="size-4" />
              </div>
              <div class="rule-details">
                <div class="rule-header-row">
                  <span class="rule-name">{{ attr.name }}</span>
                <div class="rule-badges">
                  <span class="badge-type">
                    {{ getTypeLabel(attr.type) }}
                  </span>
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
              <i class="i-lucide-pencil size-4.5" />
            </button>
            <div class="divider" />
            <button
              class="action-icon text-red-400 hover:bg-red-500/10"
              title="Excluir"
              @click="deleteAttribute(attr.id)"
            >
              <i class="i-lucide-trash-2 size-4.5" />
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

/* ───────── CARDS LIST ───────── */
.cards-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
  margin-top: 10px;
}

.rule-item {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  padding: 14px 18px;
  transition: all 0.2s ease;
}
.rule-item:hover {
  border-color: rgb(var(--slate-6));
  background: rgb(var(--slate-3));
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
  gap: 8px;
}

.action-icon {
  width: 32px;
  height: 32px;
  border-radius: 6px;
  display: flex;
  align-items: center;
  justify-content: center;
  color: rgb(var(--slate-9));
  background: transparent;
  border: none;
  cursor: pointer;
  transition: all 0.15s;
}
.action-icon:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}

.divider {
  width: 1px;
  height: 16px;
  background: rgb(var(--slate-5));
  margin: 0 4px;
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
