<template>
  <div class="svc-root">
    <!-- Header compacto — empilha em mobile via flex-wrap -->
    <div class="svc-header">
      <div class="svc-header__intro">
        <h2 class="section-title">Serviços</h2>
        <p class="section-sub-title">
          Cadastre os serviços oferecidos pela clínica. A duração é usada para
          sugerir o horário de término ao agendar.
        </p>
      </div>
      <div class="svc-header__actions">
        <BeclinicButton
          variant="faded"
          color="amber"
          icon="i-lucide-broom"
          label="Limpar sem uso"
          size="sm"
          @click="openCleanupModal"
        />
        <BeclinicButton
          icon="i-lucide-plus"
          label="Novo serviço"
          size="sm"
          @click="openServiceModal()"
        />
      </div>
    </div>

    <!-- Toolbar: busca (SearchInput global do beclinic_core) + contador + hint -->
    <div class="svc-toolbar mb-3">
      <SearchInput
        :model-value="searchQuery"
        placeholder="Buscar por nome ou ID..."
        @update:model-value="onSearchChange"
      />
      <span class="svc-toolbar-meta">
        <template v-if="pageMeta.total_count > 0">
          {{ pageMeta.total_count }}
          {{ pageMeta.total_count === 1 ? 'serviço' : 'serviços' }}
        </template>
      </span>
      <span
        v-if="reorderSaving"
        class="svc-toolbar-meta svc-toolbar-meta--saving"
      >
        <i class="i-lucide-loader-circle animate-spin size-[12px]" />
        Salvando ordem...
      </span>
      <span
        v-else-if="!searchQuery && pageServices.length > 1"
        class="svc-toolbar-meta svc-toolbar-meta--hint"
      >
        <i class="i-lucide-move size-[12px]" />
        Arraste as linhas para reordenar
      </span>
    </div>

    <!-- Loading -->
    <div v-if="pageLoading && pageServices.length === 0" class="notif-empty">
      <i class="i-lucide-loader-circle animate-spin notif-empty-ico" />
      <p class="notif-empty-title">Carregando serviços...</p>
    </div>

    <!-- Empty state (busca sem resultados ou tabela vazia) -->
    <div
      v-else-if="!pageLoading && pageServices.length === 0"
      class="svc-empty"
    >
      <div class="svc-empty-icon-wrap">
        <i class="i-lucide-scissors svc-empty-icon" />
      </div>
      <h3 class="svc-empty-title">
        {{ searchQuery ? 'Nenhum serviço encontrado' : 'Nenhum serviço cadastrado' }}
      </h3>
      <p class="svc-empty-sub">
        <template v-if="searchQuery">
          Nenhum serviço corresponde a "<strong>{{ searchQuery }}</strong>".
        </template>
        <template v-else>
          Clique em <strong>Novo serviço</strong> para cadastrar avaliações,
          limpezas, tratamentos e outros procedimentos.
        </template>
      </p>
      <button v-if="!searchQuery" class="save-btn mt-4" @click="openServiceModal()">
        <i class="i-lucide-plus size-[15px]" /> Novo serviço
      </button>
    </div>

    <!-- Tabela de serviços -->
    <div v-else class="svc-card" :class="{ 'svc-card--reloading': pageLoading }">
      <div class="svc-table-wrap">
        <table class="svc-table">
          <thead>
            <tr>
              <th class="svc-th svc-th-color">Cor</th>
              <th class="svc-th svc-th-name">Nome</th>
              <th class="svc-th svc-th-usage">Uso</th>
              <th class="svc-th svc-th-dur">Duração</th>
              <th class="svc-th svc-th-price">Preço</th>
              <th class="svc-th svc-th-room">Sala</th>
              <th class="svc-th svc-th-actions">Ações</th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(service, idx) in pageServices"
              :key="service.id"
              class="svc-row"
              :class="{
                'svc-row--draggable': !searchQuery,
                'svc-row--dragging': dragState.srcIndex === idx,
                'svc-row--drag-over':
                  dragState.srcIndex !== null &&
                  dragState.overIndex === idx &&
                  dragState.srcIndex !== idx,
              }"
              :draggable="!searchQuery"
              @dragstart="onDragStart($event, idx)"
              @dragover.prevent="onDragOver(idx)"
              @drop.prevent="onDrop(idx)"
              @dragend="onDragEnd"
            >
              <!-- Cor -->
              <td class="svc-td svc-td-color">
                <span
                  class="svc-color-dot"
                  :style="{ background: service.color || '#3b82f6' }"
                />
              </td>
              <!-- Nome + ID badge (clique copia o ID) -->
              <td class="svc-td svc-td-name">
                <div class="svc-name-stack">
                  <span class="svc-name-text">{{ service.name }}</span>
                  <button
                    type="button"
                    class="svc-id-badge"
                    :title="`Copiar ID #${service.id}`"
                    @click.stop="copyServiceId(service.id)"
                  >
                    <span class="svc-id-badge__hash">#</span>{{ service.id }}
                    <i class="i-lucide-copy svc-id-badge__copy" />
                  </button>
                </div>
              </td>
              <!-- Uso (contadores inline, não empilhados) -->
              <td class="svc-td svc-td-usage">
                <div class="svc-usage-inline">
                  <Badge
                    :label="`${service.agenda_events_count} agend.`"
                    icon="i-lucide-calendar"
                    :color="service.agenda_events_count ? 'blue' : 'slate'"
                    size="xs"
                    variant="faded"
                  />
                  <Badge
                    :label="`${service.treatment_items_count} planos`"
                    icon="i-lucide-clipboard-list"
                    :color="service.treatment_items_count ? 'violet' : 'slate'"
                    size="xs"
                    variant="faded"
                  />
                </div>
              </td>
              <!-- Duração -->
              <td class="svc-td svc-td-dur">
                <span class="svc-meta-text">
                  <i class="i-lucide-clock size-[12px]" />
                  {{ formatDuration(service.duration_minutes) }}
                </span>
              </td>
              <!-- Preço -->
              <td class="svc-td svc-td-price">
                <span class="svc-price-text">{{ formatPrice(service.price) }}</span>
              </td>
              <!-- Sala -->
              <td class="svc-td svc-td-room">
                <Badge
                  v-if="service.requires_room"
                  label="Exige sala"
                  icon="i-lucide-building-2"
                  color="slate"
                  size="xs"
                  variant="faded"
                />
                <span v-else class="svc-meta-muted">—</span>
              </td>
              <!-- Ações: ícones lado a lado via flex inline. -->
              <td class="svc-td svc-td-actions">
                <Tooltip label="Editar serviço">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="slate"
                    icon="i-lucide-pencil"
                    @click.stop="openServiceModal(service)"
                  />
                </Tooltip>
                <Tooltip label="Excluir serviço">
                  <BeclinicButton
                    size="xs"
                    variant="ghost"
                    color="ruby"
                    icon="i-lucide-trash-2"
                    @click.stop="confirmDeleteService(service)"
                  />
                </Tooltip>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Paginação (componente global Pagination — mesmo usado em Financial v2) -->
    <Pagination
      :current-page="pageMeta.current_page"
      :per-page="pageMeta.per_page"
      :total-count="pageMeta.total_count"
      item-label="serviços"
      class="mt-3"
      @update:current-page="goToPage"
      @update:per-page="setPerPage"
    />

    <!-- ─── Modal: Confirmar limpeza em massa ─── -->
    <teleport to="body">
      <div
        v-if="cleanupModalOpen"
        class="modal-overlay"
        @click.self="closeCleanupModal"
      >
        <div class="modal-box svc-del-modal">
          <div class="modal-header">
            <h3 class="modal-title">Limpar serviços sem uso</h3>
            <button class="modal-close-btn" @click="closeCleanupModal">
              <i class="i-lucide-x size-[16px]" />
            </button>
          </div>
          <div class="modal-body">
            <div v-if="cleanupPreviewLoading" class="svc-del-stats svc-del-stats--loading">
              <i class="i-lucide-loader-circle animate-spin size-[14px]" />
              <span>Verificando serviços sem vínculo...</span>
            </div>

            <template v-else-if="cleanupPreview">
              <p v-if="cleanupPreview.count === 0" class="svc-del-msg">
                Não há serviços sem nenhum agendamento ou item de plano de
                tratamento. Tudo está em uso.
              </p>
              <template v-else>
                <p class="svc-del-msg">
                  <strong>{{ cleanupPreview.count }}</strong>
                  {{ cleanupPreview.count === 1 ? 'serviço' : 'serviços' }} sem
                  nenhum vínculo
                  {{ cleanupPreview.count === 1 ? 'será excluído permanentemente' : 'serão excluídos permanentemente' }}:
                </p>

                <!-- Lista dos serviços que serão excluídos — com scroll. -->
                <ul class="svc-cleanup-list">
                  <li
                    v-for="svc in cleanupPreview.services"
                    :key="svc.id"
                    class="svc-cleanup-item"
                  >
                    <span
                      class="svc-color-dot svc-cleanup-dot"
                      :style="{ background: svc.color || '#3b82f6' }"
                    />
                    <span class="svc-cleanup-name">{{ svc.name }}</span>
                  </li>
                </ul>

                <!-- Aviso fixo de irreversibilidade — cleanup é sempre hard-delete.
                     Serviços listados não têm vínculo nenhum, não há audit trail
                     a preservar. Por isso é seguro (e mais limpo) hard-deletar. -->
                <div class="svc-del-stats svc-del-stats--danger">
                  <i class="i-lucide-alert-triangle size-[14px] mt-[2px]" />
                  <span>
                    <strong>Ação irreversível.</strong> Os registros serão
                    removidos fisicamente do banco. Como esses serviços não
                    têm nenhum agendamento nem item de plano associado, não há
                    histórico a preservar.
                  </span>
                </div>

                <!-- Checkbox obrigatório — habilita o botão somente após confirmação. -->
                <label class="svc-cleanup-mode">
                  <input
                    type="checkbox"
                    :checked="cleanupConfirmed"
                    @change="cleanupConfirmed = $event.target.checked"
                  />
                  <span>
                    <strong>Confirmo</strong> que entendi que esta ação é
                    irreversível.
                  </span>
                </label>
              </template>
            </template>
          </div>
          <div class="modal-footer">
            <BeclinicButton
              variant="outline"
              color="slate"
              label="Cancelar"
              size="sm"
              @click="closeCleanupModal"
            />
            <BeclinicButton
              color="ruby"
              icon="i-lucide-trash-2"
              :label="cleanupRunning ? 'Excluindo...' : 'Excluir permanentemente'"
              size="sm"
              :is-loading="cleanupRunning"
              :disabled="
                cleanupPreviewLoading ||
                  cleanupRunning ||
                  !cleanupPreview ||
                  cleanupPreview.count === 0 ||
                  !cleanupConfirmed
              "
              @click="confirmCleanup"
            />
          </div>
        </div>
      </div>
    </teleport>

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
            <BeclinicButton
              variant="outline"
              color="slate"
              label="Cancelar"
              size="sm"
              @click="closeServiceModal"
            />
            <BeclinicButton
              :icon="serviceSaving ? null : 'i-lucide-check'"
              :label="serviceDraft.id ? 'Salvar alterações' : 'Criar serviço'"
              size="sm"
              :is-loading="serviceSaving"
              :disabled="serviceSaving || !serviceDraft.name?.trim()"
              @click="saveService"
            />
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
              <strong>{{ serviceDeleteName }}</strong>?
            </p>

            <!-- PR #7 da auditoria: exibe contadores reais de uso antes da confirmação. -->
            <div v-if="serviceDeleteStatsLoading" class="svc-del-stats svc-del-stats--loading">
              <i class="i-lucide-loader-circle animate-spin size-[14px]" />
              <span>Verificando uso...</span>
            </div>

            <div
              v-else-if="hasUsage"
              class="svc-del-stats svc-del-stats--warn"
            >
              <i class="i-lucide-alert-triangle size-[16px] mt-[2px]" />
              <div>
                <div class="svc-del-stats-title">Este serviço está em uso:</div>
                <ul class="svc-del-stats-list">
                  <li v-if="serviceDeleteStats?.agenda_events_count > 0">
                    <strong>{{ serviceDeleteStats.agenda_events_count }}</strong>
                    {{ serviceDeleteStats.agenda_events_count === 1 ? 'agendamento' : 'agendamentos' }}
                  </li>
                  <li v-if="serviceDeleteStats?.treatment_items_count > 0">
                    <strong>{{ serviceDeleteStats.treatment_items_count }}</strong>
                    {{ serviceDeleteStats.treatment_items_count === 1 ? 'item de plano de tratamento' : 'itens de plano de tratamento' }}
                  </li>
                </ul>
                <p class="svc-del-stats-note">
                  <strong>Ação irreversível.</strong> O serviço será removido
                  fisicamente do banco. Esses registros permanecem visíveis com
                  o nome histórico do procedimento (preservado em
                  <code>custom_attributes.treatment</code> /
                  <code>procedure_name</code>), mas o link com o serviço será
                  desfeito (set null).
                </p>
              </div>
            </div>

            <div
              v-else-if="serviceDeleteStats && !hasUsage"
              class="svc-del-stats svc-del-stats--ok"
            >
              <i class="i-lucide-check-circle size-[14px]" />
              <span>Nenhum agendamento ou plano de tratamento referencia este serviço.</span>
            </div>
          </div>
          <div class="modal-footer">
            <BeclinicButton
              variant="outline"
              color="slate"
              label="Cancelar"
              size="sm"
              @click="cancelDeleteService"
            />
            <BeclinicButton
              color="ruby"
              icon="i-lucide-trash-2"
              label="Excluir"
              size="sm"
              :disabled="serviceDeleteStatsLoading"
              @click="deleteService"
            />
          </div>
        </div>
      </div>
    </teleport>

  </div>
</template>

<script setup>
import { ref, computed, watch, onMounted, nextTick, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { useSettingsServices } from '../composables/useSettingsServices';
import ColorPicker from '../../../routes/settings/ColorPicker.vue';
// PR de polimento UI (2026-05-14): adota componentes globais do beclinic_core
// para alinhar visual com o padrão Financial v2 (CashFlow, Reclassify, Payables).
// Resolve: ícones de ação empilhados verticalmente, paginação inconsistente,
// botões com SCSS duplicado e métricas com pills empilhadas.
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';
import Pagination from '@plugins/beclinic_core/frontend/components/Pagination.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import SearchInput from '@plugins/beclinic_core/frontend/components/SearchInput.vue';

const store = useStore();

const {
  serviceModal,
  serviceDraft,
  serviceDeleteName,
  serviceDeleteConfirm,
  serviceDeleteStats,
  serviceDeleteStatsLoading,
  serviceSaving,
  showColorPicker,
  serviceColors,
  openServiceModal,
  closeServiceModal,
  saveService,
  confirmDeleteService,
  cancelDeleteService,
  deleteService,
  formatPrice,
  formatDuration,
  // PR de UI overhaul (2026-05-14):
  pageServices,
  pageMeta,
  pageLoading,
  searchQuery,
  cleanupPreview,
  cleanupRunning,
  fetchPage,
  goToPage,
  setPerPage,
  onSearchChange,
  loadCleanupPreview,
  runCleanupUnused,
  // PR #9 — drag-and-drop:
  dragState,
  reorderSaving,
  onDragStart,
  onDragOver,
  onDragEnd,
  onDrop,
} = useSettingsServices(store);

// PR ID visível (2026-05-14): copia o ID do serviço pra área de transferência.
// Usuário pode usar pra abrir tickets de suporte, scripts admin, debug rápido.
// Fallback: se clipboard API indisponível (Firefox sem permissão, http),
// exibe o ID num alert simples pra que o usuário copie manualmente.
const copyServiceId = async (id) => {
  const text = String(id);
  try {
    await navigator.clipboard.writeText(text);
    useAlert(`ID #${id} copiado`);
  } catch (e) {
    console.warn('[SettingsServices] clipboard API indisponível:', e);
    useAlert(`ID #${id} — copie manualmente`);
  }
};

// Modal de cleanup em massa
const cleanupModalOpen = ref(false);
const cleanupPreviewLoading = ref(false);
// Checkbox de confirmação: cleanup é sempre hard-delete; operador precisa
// marcar explicitamente "Confirmo que entendi que é irreversível" antes do
// botão habilitar. Reseta a cada abertura do modal.
const cleanupConfirmed = ref(false);


const openCleanupModal = async () => {
  cleanupModalOpen.value = true;
  cleanupPreviewLoading.value = true;
  cleanupConfirmed.value = false; // reset a cada abertura — força nova confirmação
  await loadCleanupPreview();
  cleanupPreviewLoading.value = false;
};

const closeCleanupModal = () => {
  cleanupModalOpen.value = false;
  cleanupPreview.value = null;
  cleanupConfirmed.value = false;
};

const confirmCleanup = async () => {
  await runCleanupUnused();
  cleanupModalOpen.value = false;
  cleanupConfirmed.value = false;
};

// Mount: carrega a primeira página.
onMounted(() => {
  fetchPage(1);
});

// PR #7: helper para o template — true se o serviço tem qualquer uso real.
const hasUsage = computed(() => {
  const s = serviceDeleteStats.value;
  if (!s) return false;
  return (s.agenda_events_count || 0) > 0 || (s.treatment_items_count || 0) > 0;
});

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

/* Card que envolve a tabela — padrão finv2-table-wrap */
.svc-card {
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  overflow: hidden;
}

/* Wrapper com overflow horizontal */
.svc-table-wrap {
  overflow-x: auto;
}

/* Tabela compactada — padrão visual `finv2-table` (CashFlow v2 / Reclassify v2). */
.svc-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
  min-width: 480px;
}

.svc-table th,
.svc-table td {
  padding: 12px 16px;
  text-align: left;
  vertical-align: middle;
}

.svc-th {
  background: rgb(var(--slate-2));
  font-size: 11px;
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: rgb(var(--slate-9));
  border-bottom: 1px solid rgb(var(--slate-4));
  white-space: nowrap;
}

.svc-th-color {
  width: 40px;
}
.svc-th-name {
  min-width: 160px;
}
.svc-th-usage {
  width: 220px;
}
.svc-th-dur {
  width: 100px;
}
.svc-th-price {
  width: 110px;
  text-align: right;
}
.svc-th-room {
  width: 120px;
}
.svc-th-actions {
  width: 1%;
  white-space: nowrap;
  text-align: right;
}

.svc-row {
  border-bottom: 1px solid rgb(var(--slate-3));
  transition: background 0.1s ease;
}
.svc-row:last-child {
  border-bottom: 0;
}
.svc-row:hover {
  background: rgb(var(--slate-2) / 0.5);
}

/* Bolinha de cor — compactada (10x10 em vez de 14x14) */
.svc-color-dot {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
  border: 1.5px solid rgba(0, 0, 0, 0.08);
}

/* Nome */
.svc-name-text {
  font-size: 13px;
  font-weight: 500;
  color: rgb(var(--slate-12));
}

/* Stack: nome em cima + badge de ID embaixo (clicável pra copy) */
.svc-name-stack {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 3px;
}
.svc-id-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 1px 6px 1px 5px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 5px;
  font-size: 11px;
  font-family: ui-monospace, SFMono-Regular, 'JetBrains Mono', Consolas, monospace;
  font-variant-numeric: tabular-nums;
  color: rgb(var(--slate-9));
  cursor: pointer;
  transition: background 0.12s ease, border-color 0.12s ease, color 0.12s ease;
  line-height: 1;
}
.svc-id-badge:hover {
  background: rgb(var(--slate-3));
  border-color: rgb(var(--slate-6));
  color: rgb(var(--slate-12));
}
.svc-id-badge__hash {
  color: rgb(var(--slate-8));
  font-weight: 600;
}
.svc-id-badge__copy {
  width: 10px;
  height: 10px;
  opacity: 0.6;
  margin-left: 1px;
}
.svc-id-badge:hover .svc-id-badge__copy {
  opacity: 1;
}

/* Preço (numérico, alinhado à direita) */
.svc-td-price {
  text-align: right;
}
.svc-price-text {
  font-size: 13px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  font-variant-numeric: tabular-nums;
}

/* Texto + ícone inline (Duração, etc.) */
.svc-meta-text {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: rgb(var(--slate-11));
  font-size: 13px;
}
.svc-meta-muted {
  color: rgb(var(--slate-8));
  font-size: 13px;
}

/* Ações: ícones lado a lado (flex inline) — resolve o problema dos
   botões empilhados verticalmente. Mesmo padrão de `finv2-table__td-actions`. */
.svc-td-actions {
  display: flex;
  gap: 4px;
  justify-content: flex-end;
  align-items: center;
  white-space: nowrap;
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

/* PR de UI overhaul (2026-05-14) ─────────────────────────────────── */

/* Header compacto — empilha em mobile via flex-wrap.
   Antes usava `.notif-header` (legado) com `mb-6 justify-between` que
   espremia os botões em telas estreitas. */
.svc-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
  flex-wrap: wrap;
}
.svc-header__intro {
  flex: 1 1 320px;
  min-width: 0;
}
.svc-header__actions {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

@media (max-width: 640px) {
  .svc-header {
    gap: 12px;
    margin-bottom: 12px;
  }
  .svc-header__actions {
    width: 100%;
    /* Mobile: botões ocupam linha cheia e quebram se faltar espaço */
  }
  .svc-header__actions :deep(button) {
    flex: 1 1 auto;
  }
}

/* Toolbar (busca + meta) */
.svc-toolbar {
  display: flex;
  align-items: center;
  gap: 16px;
  flex-wrap: wrap;
}
.svc-toolbar-meta {
  font-size: 13px;
  color: rgb(var(--slate-9));
  white-space: nowrap;
}

/* Coluna de uso — Badges inline (lado a lado, sem stack vertical) */
.svc-usage-inline {
  display: flex;
  gap: 4px;
  flex-wrap: wrap;
}

/* Indicador sutil quando a tabela está recarregando (busca/refresh) */
.svc-card--reloading {
  opacity: 0.6;
  pointer-events: none;
  transition: opacity 0.12s;
}

/* Checkbox no modal de cleanup — confirmação obrigatória de hard-delete */
.svc-cleanup-mode {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  margin: 12px 0;
  padding: 10px 12px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  cursor: pointer;
  user-select: none;
}
.svc-cleanup-mode input[type='checkbox'] {
  margin-top: 2px;
  flex-shrink: 0;
  accent-color: rgb(var(--ruby-9));
}
.svc-cleanup-mode span {
  font-size: 13px;
  color: rgb(var(--slate-11));
  line-height: 1.4;
}
.svc-cleanup-mode strong {
  color: rgb(var(--slate-12));
}

/* Variante danger do bloco de stats (quando cleanup-mode === destroy) */
.svc-del-stats--danger {
  background: rgba(220, 38, 38, 0.08) !important;
  border-color: rgba(220, 38, 38, 0.35) !important;
  color: rgb(var(--ruby-11)) !important;
}

/* PR #9 — drag-and-drop visual states */
.svc-row--draggable {
  cursor: grab;
}
.svc-row--draggable:active {
  cursor: grabbing;
}
.svc-row--dragging {
  opacity: 0.4;
}
.svc-row--drag-over {
  /* Linha de destino: barra azul no topo (indica onde vai cair).
     box-shadow inset evita afetar o layout (mudaria altura da row). */
  box-shadow: inset 0 3px 0 0 rgb(var(--blue-9));
  background: rgba(59, 130, 246, 0.05);
}

.svc-toolbar-meta--hint,
.svc-toolbar-meta--saving {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  color: rgb(var(--slate-8));
  @apply text-sm;
}
.svc-toolbar-meta--saving {
  color: rgb(var(--blue-10));
}

/* Lista de serviços no modal de cleanup — com scroll para casos com dezenas */
.svc-cleanup-list {
  margin: 12px 0;
  padding: 8px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  max-height: 200px;
  overflow-y: auto;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 4px;
}
.svc-cleanup-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 4px 8px;
  border-radius: 4px;
  @apply text-sm;
  color: rgb(var(--slate-11));
}
.svc-cleanup-item:hover {
  background: rgb(var(--slate-3));
}
.svc-cleanup-dot {
  width: 10px;
  height: 10px;
  border-width: 1.5px;
  flex-shrink: 0;
}
.svc-cleanup-name {
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

/* PR #7 da auditoria: bloco de stats no modal de exclusão */
.svc-del-stats {
  margin-top: 16px;
  padding: 12px 14px;
  border-radius: 8px;
  @apply text-sm;
  display: flex;
  align-items: flex-start;
  gap: 10px;
  line-height: 1.45;
}
.svc-del-stats--loading {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-10));
}
.svc-del-stats--warn {
  background: rgba(245, 158, 11, 0.1);
  border: 1px solid rgba(245, 158, 11, 0.3);
  color: rgb(var(--slate-12));
}
.svc-del-stats--ok {
  background: rgba(34, 197, 94, 0.08);
  border: 1px solid rgba(34, 197, 94, 0.25);
  color: rgb(var(--slate-11));
}
.svc-del-stats-title {
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin-bottom: 4px;
}
.svc-del-stats-list {
  margin: 0;
  padding-left: 18px;
  display: flex;
  flex-direction: column;
  gap: 2px;
  list-style: disc;
}
.svc-del-stats-note {
  margin-top: 8px;
  color: rgb(var(--slate-10));
  font-size: 12.5px;
  line-height: 1.5;
}

</style>
