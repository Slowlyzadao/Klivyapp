<template>
  <div class="svc-root">
    <!-- Header -->
    <div class="notif-header flex items-center justify-between mb-6">
      <div>
        <h2 class="section-title mb-1">Serviços</h2>
        <p class="section-sub-title">
          Cadastre os serviços oferecidos pela clínica. A duração é usada para
          sugerir o horário de término ao agendar.
        </p>
      </div>
      <button class="save-btn" @click="openServiceModal()">
        <i class="i-lucide-plus size-[15px]" />
        <span>Novo serviço</span>
      </button>
    </div>

    <!-- Loading -->
    <div v-if="agendaServicesLoading" class="notif-empty">
      <i class="i-lucide-loader-circle animate-spin notif-empty-ico" />
      <p class="notif-empty-title">Carregando serviços...</p>
    </div>

    <!-- Empty state -->
    <div
      v-else-if="!agendaServicesLoading && agendaServices.length === 0"
      class="svc-empty"
    >
      <div class="svc-empty-icon-wrap">
        <i class="i-lucide-scissors svc-empty-icon" />
      </div>
      <h3 class="svc-empty-title">Nenhum serviço cadastrado</h3>
      <p class="svc-empty-sub">
        Clique em <strong>Novo serviço</strong> para cadastrar avaliações,
        limpezas, tratamentos e outros procedimentos.
      </p>
      <button class="save-btn mt-4" @click="openServiceModal()">
        <i class="i-lucide-plus size-[15px]" /> Novo serviço
      </button>
    </div>

    <!-- Tabela de serviços -->
    <div v-else class="svc-card">
      <div class="svc-table-wrap">
        <table class="svc-table">
          <thead>
            <tr>
              <th class="svc-th svc-th-color">Cor</th>
              <th class="svc-th svc-th-name">Nome</th>
              <th class="svc-th svc-th-dur">Duração</th>
              <th class="svc-th svc-th-price">Preço</th>
              <th class="svc-th svc-th-room">Sala</th>
              <th class="svc-th svc-th-actions">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="service in agendaServices"
              :key="service.id"
              class="svc-row"
            >
              <!-- Cor -->
              <td class="svc-td svc-td-color">
                <span
                  class="svc-color-dot"
                  :style="{ background: service.color || '#3b82f6' }"
                />
              </td>
              <!-- Nome -->
              <td class="svc-td svc-td-name">
                <span class="svc-name-text">{{ service.name }}</span>
              </td>
              <!-- Duração -->
              <td class="svc-td svc-td-dur">
                <span class="svc-badge svc-badge-dur">
                  <i class="i-lucide-clock size-[11px]" />
                  {{ formatDuration(service.duration_minutes) }}
                </span>
              </td>
              <!-- Preço -->
              <td class="svc-td svc-td-price">
                <span class="svc-price-text">{{
                  formatPrice(service.price)
                }}</span>
              </td>
              <!-- Sala -->
              <td class="svc-td svc-td-room">
                <span
                  v-if="service.requires_room"
                  class="svc-badge svc-badge-room"
                >
                  <i class="i-lucide-building-2 size-[11px]" />
                  Exige sala
                </span>
                <span v-else class="svc-badge svc-badge-noroom">
                  <i class="i-lucide-minus size-[11px]" />
                  Sem sala
                </span>
              </td>
              <!-- Ações -->
              <td class="svc-td svc-td-actions">
                <button
                  class="svc-action-btn svc-action-edit"
                  title="Editar serviço"
                  @click.stop="openServiceModal(service)"
                >
                  <i class="i-lucide-pencil size-[14px]" />
                </button>
                <button
                  class="svc-action-btn svc-action-del"
                  title="Excluir serviço"
                  @click.stop="confirmDeleteService(service)"
                >
                  <i class="i-lucide-trash-2 size-[14px]" />
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- ─── Modal: Criar / Editar Serviço ─── -->
    <teleport to="body">
      <div
        v-if="serviceModal && serviceDraft"
        class="modal-overlay"
        @click.self="closeServiceModal"
      >
        <div class="modal-box svc-modal-box">
          <div class="modal-header">
            <h3 class="modal-title">
              {{ serviceDraft.id ? 'Editar serviço' : 'Novo serviço' }}
            </h3>
            <button class="modal-close-btn" @click="closeServiceModal">
              <i class="i-lucide-x size-[16px]" />
            </button>
          </div>

          <div class="modal-body">
            <!-- Nome -->
            <div class="svc-field">
              <label class="svc-label">Nome do serviço *</label>
              <input
                v-model="serviceDraft.name"
                type="text"
                class="svc-input"
                placeholder="Ex: Avaliação, Limpeza, Raio-X..."
                @keydown.enter="saveService"
              />
            </div>

            <!-- Duração + Preço (lado a lado) -->
            <div class="svc-row-fields">
              <div class="svc-field">
                <label class="svc-label">Duração (minutos) *</label>
                <input
                  v-model.number="serviceDraft.duration_minutes"
                  type="number"
                  min="1"
                  class="svc-input"
                  placeholder="60"
                />
              </div>
              <div class="svc-field">
                <label class="svc-label">Preço (R$)</label>
                <input
                  v-model.number="serviceDraft.price"
                  type="number"
                  min="0"
                  step="0.01"
                  class="svc-input"
                  placeholder="0,00"
                />
              </div>
            </div>

            <!-- Cor -->
            <div class="svc-field">
              <label class="svc-label">Cor de identificação</label>
              <div class="svc-color-picker">
                <button
                  v-for="c in serviceColors"
                  :key="c"
                  type="button"
                  class="svc-color-option"
                  :class="{ 'svc-color-selected': serviceDraft.color === c }"
                  :style="{ background: c }"
                  :title="c"
                  @click="
                    serviceDraft.color = c;
                    showColorPicker = false;
                  "
                />
                <!-- Botão que abre o seletor customizado -->
                <button
                  type="button"
                  class="svc-color-option svc-color-custom"
                  :class="{
                    'svc-color-selected': !serviceColors.includes(
                      serviceDraft.color
                    ),
                  }"
                  :style="{
                    background: !serviceColors.includes(serviceDraft.color)
                      ? serviceDraft.color
                      : 'rgb(var(--slate-4))',
                  }"
                  title="Cor personalizada"
                  ref="colorPickerTriggerRef"
                  @click.stop="toggleColorPickerPop"
                >
                  <i
                    class="i-lucide-pipette"
                    :style="{
                      color: !serviceColors.includes(serviceDraft.color)
                        ? 'rgba(255,255,255,0.9)'
                        : 'rgb(var(--slate-9))',
                      fontSize: '12px',
                    }"
                  />
                </button>
              <!-- Seletor de Cor Customizado -->
              <teleport to="body">
                <div
                  v-if="showColorPicker"
                  class="svc-cp-popover"
                  :style="cpStyle"
                  @click.stop
                >
                  <ColorPicker v-model="serviceDraft.color" />
                </div>
              </teleport>
              </div>
            </div>

            <!-- Exige sala -->
            <div class="svc-field svc-toggle-field">
              <div class="svc-toggle-info">
                <span class="svc-label" style="margin-bottom: 0">
                  Exige sala
                </span>
                <span class="svc-sublabel">
                  Marque se este serviço precisa de uma sala específica
                </span>
              </div>
              <button
                class="toggle-switch"
                :class="{ 'toggle-on': serviceDraft.requires_room }"
                @click="
                  serviceDraft.requires_room = !serviceDraft.requires_room
                "
              >
                <span class="toggle-thumb" />
              </button>
            </div>
          </div>

          <div class="modal-footer">
            <button class="modal-btn-cancel" @click="closeServiceModal">
              Cancelar
            </button>
            <button
              class="modal-btn-save"
              :disabled="serviceSaving || !serviceDraft.name?.trim()"
              @click="saveService"
            >
              <i
                v-if="serviceSaving"
                class="i-lucide-loader-circle animate-spin size-[14px]"
              />
              <i v-else class="i-lucide-check size-[14px]" />
              {{ serviceDraft.id ? 'Salvar alterações' : 'Criar serviço' }}
            </button>
          </div>
        </div>
      </div>
    </teleport>

    <!-- ─── Modal: Confirmar exclusão ─── -->
    <teleport to="body">
      <div
        v-if="serviceDeleteConfirm"
        class="modal-overlay"
        @click.self="cancelDeleteService"
      >
        <div class="modal-box svc-del-modal">
          <div class="modal-header">
            <h3 class="modal-title">Excluir serviço</h3>
            <button class="modal-close-btn" @click="cancelDeleteService">
              <i class="i-lucide-x size-[16px]" />
            </button>
          </div>
          <div class="modal-body">
            <p class="svc-del-msg">
              Tem certeza que deseja excluir o serviço
              <strong>{{ serviceDeleteName }}</strong>? Esta ação não pode ser desfeita.
            </p>
          </div>
          <div class="modal-footer">
            <button class="modal-btn-cancel" @click="cancelDeleteService">
              Cancelar
            </button>
            <button class="modal-btn-danger" @click="deleteService">
              <i class="i-lucide-trash-2 size-[14px]" />
              Excluir
            </button>
          </div>
        </div>
      </div>
    </teleport>
  </div>
</template>

<script setup>
import { ref, watch, nextTick, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useSettingsServices } from '../composables/useSettingsServices';
import ColorPicker from '../../../routes/settings/ColorPicker.vue';

const store = useStore();

const {
  serviceModal,
  serviceDraft,
  serviceDeleteId,
  serviceDeleteName,
  serviceDeleteConfirm,
  serviceSaving,
  showColorPicker,
  serviceColors,
  agendaServices,
  agendaServicesLoading,
  openServiceModal,
  closeServiceModal,
  saveService,
  confirmDeleteService,
  cancelDeleteService,
  deleteService,
  formatPrice,
  formatDuration,
} = useSettingsServices(store);

// Floating CP Logic
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

const handleOutsideClickCP = (e) => {
  if (!showColorPicker.value) return;
  if (colorPickerTriggerRef.value && colorPickerTriggerRef.value.contains(e.target)) return;
  const popover = document.querySelector('.svc-cp-popover');
  if (popover && popover.contains(e.target)) return;
  
  showColorPicker.value = false;
};

watch(() => showColorPicker.value, (newVal) => {
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
});

onUnmounted(() => {
  window.removeEventListener('click', handleOutsideClickCP);
  window.removeEventListener('scroll', calculateCPPosition, true);
  window.removeEventListener('resize', calculateCPPosition);
});
</script>

<style scoped>
/* ═══════════════ SERVIÇOS E TIPOS ═══════════════ */
.svc-root {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

/* Card que envolve a tabela */
.svc-card {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 12px;
  overflow: hidden;
}

/* Wrapper com overflow horizontal */
.svc-table-wrap {
  overflow-x: auto;
}

/* Tabela */
.svc-table {
  width: 100%;
  border-collapse: collapse;
  min-width: 480px;
}

.svc-th {
  padding: 10px 16px;
  text-align: left;
  @apply text-sm;
  font-weight: 600;
  letter-spacing: 0.05em;
  text-transform: uppercase;
  color: rgb(var(--slate-9));
  background: rgb(var(--slate-3));
  border-bottom: 1px solid rgb(var(--slate-4));
  white-space: nowrap;
}

.svc-th-color {
  width: 48px;
}
.svc-th-name {
  min-width: 160px;
}
.svc-th-dur {
  width: 110px;
}
.svc-th-price {
  width: 120px;
}
.svc-th-room {
  width: 120px;
}
.svc-th-actions {
  width: 80px;
  text-align: center;
}

.svc-row {
  border-bottom: 1px solid rgb(var(--slate-3));
  transition: background 0.12s;
}
.svc-row:last-child {
  border-bottom: none;
}
.svc-row:hover {
  background: rgb(var(--slate-3));
}

.svc-td {
  padding: 12px 16px;
  vertical-align: middle;
}

.svc-td-color {
  width: 48px;
}
.svc-td-actions {
  text-align: center;
}

/* Bolinha de cor */
.svc-color-dot {
  display: inline-block;
  width: 14px;
  height: 14px;
  border-radius: 50%;
  flex-shrink: 0;
  border: 2px solid rgba(0, 0, 0, 0.08);
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.15);
}

/* Nome */
.svc-name-text {
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-12));
}

/* Preço */
.svc-price-text {
  @apply text-sm;
  color: rgb(var(--slate-11));
  font-variant-numeric: tabular-nums;
}

/* Badges */
.svc-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 0;
  @apply text-sm;
  font-weight: 500;
  background: transparent !important;
}
.svc-badge-dur {
  color: rgb(var(--slate-11));
}
.svc-badge-room {
  color: rgb(var(--slate-12)) !important;
  background: rgb(var(--slate-4)) !important;
  padding: 4px 8px !important;
  border-radius: 6px;
  font-size: 13px !important;
  font-weight: 600 !important;
  white-space: nowrap !important;
}
.svc-badge-noroom {
  color: rgb(var(--slate-8));
}

/* Botões de ação na tabela */
.svc-action-btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 30px;
  height: 30px;
  border-radius: 6px;
  border: none;
  cursor: pointer;
  padding: 0;
  transition:
    background 0.15s,
    color 0.15s;
  background: transparent;
}
.svc-action-edit {
  color: rgb(var(--slate-9));
}
.svc-action-edit:hover {
  background: rgba(59, 130, 246, 0.1);
  color: rgb(var(--blue-9));
}
.svc-action-del {
  color: rgb(var(--slate-9));
}
.svc-action-del:hover {
  background: rgba(239, 68, 68, 0.1);
  color: #dc2626;
}

/* Empty state */
.svc-empty {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 64px 24px;
  text-align: center;
}
.svc-empty-icon-wrap {
  width: 56px;
  height: 56px;
  border-radius: 16px;
  background: rgb(var(--slate-3));
  border: 1px solid rgb(var(--slate-4));
  display: flex;
  align-items: center;
  justify-content: center;
}
.svc-empty-icon {
  font-size: 24px;
  color: rgb(var(--slate-8));
}
.svc-empty-title {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0;
}
.svc-empty-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  max-width: 380px;
  line-height: 1.5;
  margin: 0;
}

/* Modal de serviços */
.svc-modal-box {
  width: 480px;
  max-width: 96vw;
}
.svc-del-modal {
  width: 420px;
  max-width: 96vw;
}

/* Campos do formulário */
.svc-field {
  display: flex;
  flex-direction: column;
  gap: 6px;
  margin-bottom: 16px;
}
.svc-field:last-child {
  margin-bottom: 0;
}
.svc-label {
  @apply text-sm;
  font-weight: 600;
  color: rgb(var(--slate-10));
  letter-spacing: 0.02em;
  text-transform: uppercase;
  margin-bottom: 2px;
}
.svc-sublabel {
  @apply text-sm;
  color: rgb(var(--slate-8));
  line-height: 1.4;
}
.svc-input {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  padding: 9px 12px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-family: inherit;
  outline: none;
  transition:
    border-color 0.15s,
    background 0.15s;
  width: 100%;
  box-sizing: border-box;
}
.svc-input:focus {
  border-color: rgb(var(--blue-8));
  background: rgb(var(--slate-1));
}

/* Linha de campos (duração + preço lado a lado) */
.svc-row-fields {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
}

/* Color picker */
.svc-color-picker {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  position: relative;
}
.svc-color-option {
  width: 26px;
  height: 26px;
  border-radius: 50%;
  border: 2.5px solid transparent;
  cursor: pointer;
  transition:
    border-color 0.15s,
    transform 0.15s;
}
.svc-color-option:hover {
  transform: scale(1.15);
}
.svc-color-selected {
  border-color: #fff !important;
  box-shadow: 0 0 0 2px rgba(255, 255, 255, 0.4);
}

/* Botão de cor personalizada */
.svc-color-custom {
  display: flex;
  align-items: center;
  justify-content: center;
  cursor: pointer;
  border-style: dashed;
  border-color: rgb(var(--slate-6));
  position: relative;
  overflow: hidden;
}
.svc-color-custom:hover {
  border-color: rgb(var(--slate-9));
  transform: scale(1.15);
}
.svc-color-native-input {
  position: absolute;
  width: 1px;
  height: 1px;
  opacity: 0;
  pointer-events: none;
  /* Força o popup do seletor a usar o tema escuro do navegador */
  color-scheme: dark;
}
/* Quando uma cor custom está selecionada, mostra o ícone com shadow para visibilidade */
.svc-color-selected.svc-color-custom {
  border-style: solid;
}

/* Popover do color picker customizado */
.svc-cp-popover {
  /* position, top, botttom, left definidos via inline style teletransportado */
  z-index: 10005; /* Alto o suficiente para ficar acima de modais */
}

/* Toggle field no modal */
.svc-toggle-field {
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 12px 0;
  border-top: 1px solid rgb(var(--slate-4));
  gap: 16px;
}
.svc-toggle-info {
  display: flex;
  flex-direction: column;
  gap: 2px;
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
  padding: 0 !important;
  box-sizing: border-box !important;
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
  padding: 0 !important;
  margin: 0 !important;
  box-sizing: border-box !important;
}
.toggle-switch.toggle-on .toggle-thumb {
  transform: translateX(20px);
}

/* Mensagem de exclusão */
.svc-del-msg {
  @apply text-sm;
  color: rgb(var(--slate-10));
  line-height: 1.55;
}

/* Botão de perigo (excluir) */
.modal-btn-danger {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 8px 18px;
  background: #dc2626;
  color: #fff;
  border: none;
  border-radius: 8px;
  @apply text-sm;
  font-weight: 600;
  font-family: inherit;
  cursor: pointer;
  transition: background 0.15s;
}
.modal-btn-danger:hover {
  background: #b91c1c;
}
</style>
