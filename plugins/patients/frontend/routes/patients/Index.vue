<script setup>
import './patients-index.css';
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useRouter } from 'vue-router';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import NewPatientModal from './components/NewPatientModal.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useAlert } from 'dashboard/composables';

const formatCpf = cpfStr => {
  if (!cpfStr) return '-';
  const v = String(cpfStr).replace(/\D/g, '').slice(0, 11);
  if (v.length > 9)
    return v.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  if (v.length > 6) return v.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  if (v.length > 3) return v.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  return v;
};

const formatDate = dateStr => {
  if (!dateStr) return '-';
  return new Date(dateStr).toLocaleDateString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
  });
};

const showNewPatientModal = ref(false);
const rawPatients = ref([]);
const isLoading = ref(false);
const searchQuery = ref('');
const viewMode = ref('list');
const activeFilter = ref('Todos');
const sortOrder = ref('az');
const showSortMenu = ref(false);
const showDeleteModal = ref(false);
const patientToDelete = ref(null);

// ── Pagination ─────────────────────────────────────────────────
const currentPage = ref(1);
const perPage = ref(15);
const perPageOptions = [15, 20, 50, 100];

// ── Archived ───────────────────────────────────────────────────
const showArchived = ref(false);
const archivedPatients = ref([]);
const isLoadingArchived = ref(false);
const isRestoring = ref(null); // id do que está sendo restaurado

const toggleArchived = () => {
  showArchived.value = !showArchived.value;
  if (showArchived.value) fetchArchived();
};

const fetchArchived = async () => {
  try {
    isLoadingArchived.value = true;
    const response = await PatientsAPI.archived(searchQuery.value);
    archivedPatients.value =
      response.data?.payload?.map?.(p => ({ ...p })) || [];
  } catch {
    // ignorar
  } finally {
    isLoadingArchived.value = false;
  }
};

const restorePatient = async patient => {
  try {
    isRestoring.value = patient.id;
    await PatientsAPI.restore(patient.id);
    archivedPatients.value = archivedPatients.value.filter(
      p => p.id !== patient.id
    );
    useAlert(`${patient.name} foi restaurado com sucesso!`);
    // Atualiza lista ativa tb
    fetchPatients();
  } catch {
    useAlert('Não foi possível restaurar o paciente.');
  } finally {
    isRestoring.value = null;
  }
};
// ──────────────────────────────────────────────────────────────

const sortLabels = {
  az: 'A → Z',
  za: 'Z → A',
  newest: 'Mais recente',
  oldest: 'Mais antigo',
};

const setSortOrder = value => {
  sortOrder.value = value;
  showSortMenu.value = false;
};

const sortedPatients = computed(() => {
  const list = [...rawPatients.value];
  if (sortOrder.value === 'az')
    return list.sort((a, b) =>
      (a.name || '').localeCompare(b.name || '', 'pt-BR')
    );
  if (sortOrder.value === 'za')
    return list.sort((a, b) =>
      (b.name || '').localeCompare(a.name || '', 'pt-BR')
    );
  if (sortOrder.value === 'newest')
    return list.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
  if (sortOrder.value === 'oldest')
    return list.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  return list;
});

const totalPages = computed(
  () => Math.ceil(sortedPatients.value.length / perPage.value) || 1
);

const pagedPatients = computed(() => {
  const start = (currentPage.value - 1) * perPage.value;
  return sortedPatients.value.slice(start, start + perPage.value);
});

const pageNumbers = computed(() => {
  const total = totalPages.value;
  const cur = currentPage.value;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages = new Set([1, total, cur]);
  if (cur > 1) pages.add(cur - 1);
  if (cur < total) pages.add(cur + 1);
  return [...pages].sort((a, b) => a - b);
});

function goToPage(n) {
  currentPage.value = Math.max(1, Math.min(n, totalPages.value));
}

function setPerPage(n) {
  perPage.value = n;
  currentPage.value = 1;
}

const filters = ['Todos', 'Novo', 'Ativo', 'Inativo', 'Faltoso', 'Alta'];
const statusMap = {
  Todos: '',
  Novo: 'novo',
  Ativo: 'ativo',
  Inativo: 'inativo',
  Faltoso: 'faltoso',
  Alta: 'alta',
};

const fetchPatients = async () => {
  try {
    isLoading.value = true;
    const response = await PatientsAPI.get(
      1,
      'name',
      searchQuery.value,
      statusMap[activeFilter.value]
    );
    rawPatients.value =
      response.data?.payload?.map?.(patient => ({ ...patient })) || [];
  } catch {
    // ignorar erro
  } finally {
    isLoading.value = false;
  }
};

const closeSortMenu = e => {
  if (!e.target.closest('.pt-sort-wrap')) showSortMenu.value = false;
};

onMounted(() => {
  fetchPatients();
  document.addEventListener('click', closeSortMenu);
});
onUnmounted(() => {
  document.removeEventListener('click', closeSortMenu);
});

let searchTimeout;
watch(searchQuery, () => {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => {
    currentPage.value = 1;
    showArchived.value ? fetchArchived() : fetchPatients();
  }, 300);
});
watch(activeFilter, () => {
  currentPage.value = 1;
  fetchPatients();
});

const setFilter = filter => {
  activeFilter.value = filter;
};
const setViewMode = mode => {
  viewMode.value = mode;
};
const openNewPatientModal = () => {
  showNewPatientModal.value = true;
};

const router = useRouter();
const openRecord = id => {
  router.push({ name: 'patients_dashboard_record', params: { patientId: id } });
};

const handlePatientCreated = newPatient => {
  if (newPatient?.id) openRecord(newPatient.id);
  else fetchPatients();
};

const openDeleteModal = patient => {
  patientToDelete.value = patient;
  showDeleteModal.value = true;
};

const closeDeleteModal = () => {
  showDeleteModal.value = false;
  patientToDelete.value = null;
};

const confirmDelete = async () => {
  if (!patientToDelete.value) return;
  try {
    await PatientsAPI.delete(patientToDelete.value.id);
    fetchPatients();
  } catch {
    useAlert('Não foi possível arquivar o paciente. Tente novamente.');
  } finally {
    closeDeleteModal();
  }
};

const statusCls = patient =>
  'pt-status pt-status--' +
  (patient.patient_status
    ? patient.patient_status.toLowerCase().replace(' ', '-')
    : 'novo');
</script>

<template>
  <div class="pt-page">
    <!-- Header -->
    <div class="pt-header">
      <div>
        <h1 class="pt-title">
          Pacientes
          <span v-if="showArchived" class="pt-archived-badge">Arquivados</span>
        </h1>
        <p class="pt-subtitle">
          {{
            showArchived
              ? 'Pacientes arquivados podem ser restaurados a qualquer momento'
              : 'Gerencie os prontuários e informações de seus pacientes'
          }}
        </p>
      </div>
      <div class="pt-header-actions">
        <button
          class="pt-btn-archived"
          :class="{ 'pt-btn-archived--active': showArchived }"
          @click="toggleArchived"
        >
          <i class="i-lucide-archive w-4 h-4" />
          <span>{{ showArchived ? 'Fechar Arquivo' : 'Arquivados' }}</span>
        </button>
        <button
          v-if="!showArchived"
          class="pt-btn-new hidden md:flex"
          @click="openNewPatientModal"
        >
          <i class="i-lucide-plus w-4 h-4" />
          <span>Novo Paciente</span>
        </button>

        <!-- FAB Mobile: Novo Paciente -->
        <button
          v-if="!showArchived"
          class="md:hidden fixed bottom-6 right-6 w-14 h-14 bg-blue-600 hover:bg-blue-700 text-white rounded-full shadow-[0_4px_14px_rgba(37,99,235,0.4)] flex items-center justify-center z-50 transition-transform active:scale-95"
          @click="openNewPatientModal"
        >
          <i class="i-lucide-plus w-6 h-6" />
        </button>
      </div>
    </div>

    <!-- Controls: search + filters + toggles -->
    <div class="pt-controls">
      <!-- Search -->
      <div class="pt-search-wrap">
        <i class="i-lucide-search pt-search-icon" />
        <input
          v-model="searchQuery"
          type="text"
          placeholder="Buscar por nome, email ou CPF..."
          class="pt-search-input"
        />
      </div>

      <!-- Filtros de status + view/sort -->
      <div class="pt-controls-right">
        <!-- Pills de filtro -->
        <div class="pt-filters">
          <button
            v-for="filter in filters"
            :key="filter"
            class="pt-filter-btn"
            :class="{ 'pt-filter-btn--active': activeFilter === filter }"
            @click="setFilter(filter)"
          >
            {{ filter }}
          </button>
        </div>

        <!-- Divider -->
        <div class="pt-divider" />

        <!-- View toggle -->
        <div class="pt-view-toggle">
          <button
            class="pt-toggle-btn"
            :class="{ 'pt-toggle-btn--active': viewMode === 'list' }"
            title="Lista"
            @click="setViewMode('list')"
          >
            <i class="i-lucide-list w-4 h-4" />
          </button>
          <button
            class="pt-toggle-btn"
            :class="{ 'pt-toggle-btn--active': viewMode === 'grid' }"
            title="Grade"
            @click="setViewMode('grid')"
          >
            <i class="i-lucide-layout-grid w-4 h-4" />
          </button>
        </div>

        <!-- Sort -->
        <div class="pt-sort-wrap">
          <button
            class="pt-toggle-btn"
            :class="{ 'pt-toggle-btn--active': showSortMenu }"
            title="Ordenar"
            @click="showSortMenu = !showSortMenu"
          >
            <i class="i-lucide-arrow-up-down w-4 h-4" />
          </button>
          <div v-if="showSortMenu" class="pt-sort-dropdown">
            <button
              v-for="(label, key) in sortLabels"
              :key="key"
              class="pt-sort-option"
              :class="{ 'pt-sort-option--active': sortOrder === key }"
              @click="setSortOrder(key)"
            >
              {{ label }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- ACTIVE PATIENTS VIEWS -->
    <template v-if="!showArchived">
      <!-- Loading -->
      <div v-if="isLoading" class="pt-loading">
        <i class="i-lucide-loader-2 animate-spin w-5 h-5" />
        <span>Carregando pacientes...</span>
      </div>

      <!-- LIST VIEW -->
      <div v-else-if="viewMode === 'list'" class="pt-list-wrap">
        <div class="pt-table-head">
          <div class="pt-col pt-col--patient">Paciente</div>
          <div class="pt-col pt-col--contact">Contato</div>
          <div class="pt-col pt-col--cpf">CPF</div>
          <div class="pt-col pt-col--date">Cadastrado em</div>
          <div class="pt-col pt-col--visit">Última Consulta</div>
          <div class="pt-col pt-col--status">Status</div>
          <div class="pt-col pt-col--actions" />
        </div>

        <!-- Empty -->
        <div v-if="sortedPatients.length === 0" class="pt-empty">
          <div class="pt-empty-icon"><i class="i-lucide-users w-7 h-7" /></div>
          <p class="pt-empty-title">Nenhum paciente encontrado</p>
          <p class="pt-empty-hint">
            {{
              searchQuery || activeFilter !== 'Todos'
                ? 'Tente ajustar os filtros.'
                : 'Cadastre o primeiro paciente.'
            }}
          </p>
        </div>

        <!-- Rows -->
        <div
          v-for="patient in pagedPatients"
          :key="patient.id"
          class="pt-row"
          @click="openRecord(patient.id)"
        >
          <div class="pt-col pt-col--patient pt-patient-cell">
            <Avatar
              :src="patient.avatar_url"
              :name="patient.name"
              :size="38"
              rounded-full
            />
            <div>
              <p class="pt-patient-name">{{ patient.name }}</p>
              <p class="pt-patient-email">{{ patient.email }}</p>
            </div>
          </div>

          <div class="pt-col pt-col--contact pt-cell-text">
            {{ patient.phone || '-' }}
          </div>

          <div class="pt-col pt-col--cpf pt-cell-mono">
            {{ formatCpf(patient.cpf) }}
          </div>

          <div class="pt-col pt-col--date pt-cell-text">
            {{ formatDate(patient.created_at) }}
          </div>

          <div class="pt-col pt-col--visit">
            <div class="pt-visit-cell">
              <i class="i-lucide-calendar w-3.5 h-3.5 pt-visit-icon" />
              <span class="pt-cell-text">{{
                patient.last_visit
                  ? new Date(patient.last_visit).toLocaleDateString('pt-BR', {
                      timeZone: 'America/Sao_Paulo',
                    })
                  : '-'
              }}</span>
            </div>
          </div>

          <div class="pt-col pt-col--status">
            <span :class="statusCls(patient)">{{
              patient.patient_status || 'Novo'
            }}</span>
          </div>

          <div class="pt-col pt-col--actions" @click.stop>
            <button
              class="pt-action-btn"
              title="Abrir prontuário"
              @click="openRecord(patient.id)"
            >
              <i class="i-lucide-file-text w-4 h-4" />
            </button>
            <button
              class="pt-action-btn pt-action-btn--danger"
              title="Arquivar"
              @click="openDeleteModal(patient)"
            >
              <i class="i-lucide-trash-2 w-4 h-4" />
            </button>
          </div>
        </div>

        <!-- Pagination footer (list view) -->
        <div v-if="sortedPatients.length > 0" class="pt-pagination">
          <div class="pt-pagination__info">
            Exibindo
            {{ (currentPage - 1) * perPage + 1 }}–{{
              Math.min(currentPage * perPage, sortedPatients.length)
            }}
            de {{ sortedPatients.length }} pacientes
          </div>
          <div class="pt-pagination__controls">
            <!-- Per-page selector -->
            <select
              :value="perPage"
              class="mr-2 px-2 py-1 bg-transparent border border-n-strong rounded-md text-xs text-n-slate-11 focus:outline-none focus:ring-1 focus:ring-blue-500 cursor-pointer transition-colors hover:border-n-slate-10"
              @change="setPerPage(Number($event.target.value))"
            >
              <option v-for="n in perPageOptions" :key="n" :value="n">
                {{ n }} por página
              </option>
            </select>
            <!-- Page buttons -->
            <button
              class="pt-pagination__btn"
              :disabled="currentPage === 1"
              @click="goToPage(currentPage - 1)"
            >
              <i class="i-lucide-chevron-left w-4 h-4" />
            </button>
            <template v-for="(pg, idx) in pageNumbers" :key="pg">
              <span
                v-if="idx > 0 && pageNumbers[idx - 1] !== pg - 1"
                class="pt-pagination__ellipsis"
                >...</span>
              <button
                class="pt-pagination__btn"
                :class="{ 'pt-pagination__btn--active': currentPage === pg }"
                @click="goToPage(pg)"
              >
                {{ pg }}
              </button>
            </template>
            <button
              class="pt-pagination__btn"
              :disabled="currentPage === totalPages"
              @click="goToPage(currentPage + 1)"
            >
              <i class="i-lucide-chevron-right w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      <!-- GRID VIEW -->
      <div v-else class="pt-grid">
        <!-- Empty -->
        <div v-if="sortedPatients.length === 0" class="pt-empty pt-empty--grid">
          <div class="pt-empty-icon"><i class="i-lucide-users w-7 h-7" /></div>
          <p class="pt-empty-title">Nenhum paciente encontrado</p>
          <p class="pt-empty-hint">
            {{
              searchQuery || activeFilter !== 'Todos'
                ? 'Tente ajustar os filtros.'
                : 'Cadastre o primeiro paciente.'
            }}
          </p>
        </div>

        <div v-for="patient in pagedPatients" :key="patient.id" class="pt-card">
          <!-- Card header: avatar + status -->
          <div class="pt-card-head">
            <Avatar
              :src="patient.avatar_url"
              :name="patient.name"
              :size="52"
              rounded-full
              class="pt-card-avatar"
            />
            <span :class="statusCls(patient)">{{
              patient.patient_status || 'Novo'
            }}</span>
          </div>

          <!-- Card body -->
          <div class="pt-card-body">
            <p class="pt-card-name">{{ patient.name }}</p>
            <p class="pt-card-email">{{ patient.email }}</p>

            <div class="pt-card-info">
              <div class="pt-info-row">
                <i class="i-lucide-phone w-3.5 h-3.5 pt-info-icon" />
                <span>{{ patient.phone || '-' }}</span>
              </div>
              <div class="pt-info-row">
                <i class="i-lucide-credit-card w-3.5 h-3.5 pt-info-icon" />
                <span>{{ formatCpf(patient.cpf) }}</span>
              </div>
              <div class="pt-info-row">
                <i class="i-lucide-calendar-plus w-3.5 h-3.5 pt-info-icon" />
                <span>Cadastrado: {{ formatDate(patient.created_at) }}</span>
              </div>
              <div class="pt-info-row">
                <i class="i-lucide-calendar-check w-3.5 h-3.5 pt-info-icon" />
                <span>Ult. visita:
                  {{
                    patient.last_visit
                      ? new Date(patient.last_visit).toLocaleDateString(
                          'pt-BR',
                          {
                            timeZone: 'America/Sao_Paulo',
                          }
                        )
                      : '-'
                  }}</span>
              </div>
            </div>
          </div>

          <!-- Card footer -->
          <div class="pt-card-footer">
            <button class="pt-card-btn" @click="openRecord(patient.id)">
              <i class="i-lucide-folder-open w-3.5 h-3.5" />
              Abrir Prontuário
            </button>
          </div>
        </div>

        <!-- Pagination footer (grid view) -->
        <div v-if="sortedPatients.length > 0" class="pt-pagination">
          <div class="pt-pagination__info">
            Exibindo
            {{ (currentPage - 1) * perPage + 1 }}–{{
              Math.min(currentPage * perPage, sortedPatients.length)
            }}
            de {{ sortedPatients.length }} pacientes
          </div>
          <div class="pt-pagination__controls">
            <select
              :value="perPage"
              class="mr-2 px-2 py-1 bg-transparent border border-n-strong rounded-md text-xs text-n-slate-11 focus:outline-none focus:ring-1 focus:ring-blue-500 cursor-pointer transition-colors hover:border-n-slate-10"
              @change="setPerPage(Number($event.target.value))"
            >
              <option v-for="n in perPageOptions" :key="n" :value="n">
                {{ n }} por página
              </option>
            </select>
            <button
              class="pt-pagination__btn"
              :disabled="currentPage === 1"
              @click="goToPage(currentPage - 1)"
            >
              <i class="i-lucide-chevron-left w-4 h-4" />
            </button>
            <template v-for="(pg, idx) in pageNumbers" :key="pg">
              <span
                v-if="idx > 0 && pageNumbers[idx - 1] !== pg - 1"
                class="pt-pagination__ellipsis"
                >...</span>
              <button
                class="pt-pagination__btn"
                :class="{ 'pt-pagination__btn--active': currentPage === pg }"
                @click="goToPage(pg)"
              >
                {{ pg }}
              </button>
            </template>
            <button
              class="pt-pagination__btn"
              :disabled="currentPage === totalPages"
              @click="goToPage(currentPage + 1)"
            >
              <i class="i-lucide-chevron-right w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </template>

    <!-- ARCHIVED VIEW -->
    <div v-else class="pt-archived-wrap">
      <!-- Loading -->
      <div v-if="isLoadingArchived" class="pt-loading">
        <i class="i-lucide-loader-2 animate-spin w-5 h-5" />
        <span>Carregando arquivo...</span>
      </div>

      <!-- Empty -->
      <div
        v-else-if="archivedPatients.length === 0"
        class="pt-empty pt-empty--archived"
      >
        <div class="pt-empty-icon">
          <i class="i-lucide-archive w-7 h-7" />
        </div>
        <p class="pt-empty-title">Nenhum paciente arquivado</p>
        <p class="pt-empty-hint">
          Pacientes arquivados aparecerão aqui e podem ser restaurados.
        </p>
      </div>

      <!-- Table -->
      <div v-else class="pt-list-wrap">
        <div class="pt-table-head">
          <div class="pt-col pt-col--patient">Paciente</div>
          <div class="pt-col pt-col--contact">Contato</div>
          <div class="pt-col pt-col--cpf">CPF</div>
          <div class="pt-col pt-col--date">Cadastrado em</div>
          <div class="pt-col pt-col--actions" />
        </div>
        <div
          v-for="patient in archivedPatients"
          :key="patient.id"
          class="pt-row pt-row--archived"
        >
          <div class="pt-col pt-col--patient pt-patient-cell">
            <Avatar
              :src="patient.avatar_url"
              :name="patient.name"
              :size="38"
              rounded-full
              class="pt-archived-avatar"
            />
            <div>
              <p class="pt-patient-name">{{ patient.name }}</p>
              <p class="pt-patient-email">{{ patient.email }}</p>
            </div>
          </div>

          <div class="pt-col pt-col--contact pt-cell-text">
            {{ patient.phone || '-' }}
          </div>

          <div class="pt-col pt-col--cpf pt-cell-mono">
            {{ formatCpf(patient.cpf) }}
          </div>

          <div class="pt-col pt-col--date pt-cell-text">
            {{ formatDate(patient.created_at) }}
          </div>

          <div class="pt-col pt-col--actions">
            <button
              class="pt-action-btn"
              title="Abrir prontuário"
              @click="openRecord(patient.id)"
            >
              <i class="i-lucide-file-text w-4 h-4" />
            </button>
            <button
              class="pt-action-btn pt-action-btn--restore"
              :disabled="isRestoring === patient.id"
              title="Restaurar paciente"
              @click="restorePatient(patient)"
            >
              <i
                v-if="isRestoring === patient.id"
                class="i-lucide-loader-2 animate-spin w-4 h-4"
              />
              <i v-else class="i-lucide-archive-restore w-4 h-4" />
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal: Novo Paciente -->
    <teleport to="body">
      <div
        v-if="showNewPatientModal"
        class="modal-overlay fixed inset-0 z-[100] flex sm:items-center justify-center p-0 sm:p-4 bg-black/40 backdrop-blur-sm"
        @click.self="showNewPatientModal = false"
      >
        <div class="agenda-new-event-modal w-full h-full sm:w-[580px] sm:h-auto bg-n-solid-1 sm:shadow-2xl sm:rounded-2xl border-0 sm:border border-n-weak flex flex-col z-20 transition-all duration-300 overflow-hidden">
          <NewPatientModal
            @close="showNewPatientModal = false"
            @success="handlePatientCreated"
          />
        </div>
      </div>
    </teleport>

    <!-- Modal: Confirmar Arquivamento -->
    <woot-delete-modal
      v-model:show="showDeleteModal"
      :on-close="closeDeleteModal"
      :on-confirm="confirmDelete"
      title="Arquivar paciente"
      :message="`Tem certeza que deseja arquivar o paciente ${patientToDelete?.name}?`"
      message-value="Esta ação irá remover o paciente da lista ativa."
      confirm-text="Sim, arquivar"
      reject-text="Cancelar"
    />
  </div>
</template>
