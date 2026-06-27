<script setup>
import '@plugins/patients/frontend/styles/patients-index.scss';
import { ref, computed, watch, onMounted, onUnmounted, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import {
  formatCpf as formatCpfBase,
  formatPhone,
} from '@plugins/patients/frontend/features/patient-record/utils/patientFormatters';
import NewPatientModal from './components/NewPatientModal.vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { useAlert } from 'dashboard/composables';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';

const formatCpf = cpfStr => formatCpfBase(cpfStr, { emptyFallback: '-' });

const formatDate = dateStr => {
  if (!dateStr) return '-';
  return new Date(dateStr).toLocaleDateString('pt-BR', {
    timeZone: 'America/Sao_Paulo',
  });
};

const brlFormatter = new Intl.NumberFormat('pt-BR', {
  style: 'currency',
  currency: 'BRL',
});
const formatBalance = cents => brlFormatter.format((Number(cents) || 0) / 100);

// `balance_due_cents` vem do backend POSITIVO quando o paciente DEVE (saldo em
// aberto) e negativo quando tem crédito. Na coluna mostramos pela ótica do
// paciente: devedor = negativo (−R$ 150,00 vermelho), crédito = positivo
// (R$ 50,00 verde). Negar o valor faz o Intl cuidar do sinal nos dois casos.
const formatBalanceSigned = cents => formatBalance(-(Number(cents) || 0));

// Quebra o saldo em vencido + a vencer pra reconciliar com os cards "Devedor
// (Vencido)" e "Em Aberto" da aba financeira do paciente (mesma definição:
// vencido = due_date < hoje). `overdue_cents` é subconjunto do saldo total.
const balanceTooltip = patient => {
  const total = Number(patient.balance_due_cents) || 0;
  const overdue = Number(patient.overdue_cents) || 0;
  if (total > 0) {
    const upcoming = total - overdue;
    if (overdue > 0 && upcoming > 0) {
      return `Saldo devedor: ${formatBalance(total)} — ${formatBalance(
        overdue
      )} vencido + ${formatBalance(upcoming)} a vencer`;
    }
    if (overdue > 0) return `Saldo devedor: ${formatBalance(total)} (vencido)`;
    return `Saldo devedor: ${formatBalance(total)} (a vencer)`;
  }
  if (total < 0) return `Crédito de ${formatBalance(-total)} a favor do paciente`;
  return 'Sem saldo em aberto';
};

const showNewPatientModal = ref(false);
const rawPatients = ref([]);
const isLoading = ref(false);
const searchQuery = ref('');
const viewMode = ref('list');
// Vazio = "Todos". Mapeia 1:1 pro `patient_status` do backend.
const activeFilter = ref('');
const sortOrder = ref('az');

// Opções do filtro de status com cor distinta — segue a mesma paleta do
// Badge do prontuário (PatientProfileBanner): novo=blue, ativo=teal,
// inativo=slate, faltoso=amber, alta=violet.
const STATUS_OPTIONS = [
  { value: '', label: 'Todos os status' },
  { value: 'novo', label: 'Novo', color: 'rgb(var(--blue-9))' },
  { value: 'ativo', label: 'Ativo', color: 'rgb(var(--teal-9))' },
  { value: 'inativo', label: 'Inativo', color: 'rgb(var(--slate-9))' },
  { value: 'faltoso', label: 'Faltoso', color: 'rgb(var(--amber-9))' },
  { value: 'alta', label: 'Alta', color: 'rgb(var(--violet-9))' },
];

// Filtro por situação financeira. Vazio = todas. "Inadimplente" = tem parcela
// VENCIDA (atrasada) — definição alinhada ao backend (`apply_financial_filter`).
const activeFinancialFilter = ref('');
const FINANCIAL_OPTIONS = [
  { value: '', label: 'Todas as situações' },
  { value: 'inadimplente', label: 'Inadimplentes', color: 'rgb(var(--ruby-9))' },
  { value: 'adimplente', label: 'Adimplentes', color: 'rgb(var(--teal-9))' },
];
const showSortMenu = ref(false);
const showDeleteModal = ref(false);
const patientToDelete = ref(null);

// ── Pagination (server-side) ───────────────────────────────────
const currentPage = ref(1);
const perPage = ref(25);
const perPageOptions = [25, 50, 100, 200];
const perPageSelectOptions = perPageOptions.map(n => ({
  value: n,
  label: `${n} por página`,
}));
const totalCount = ref(0);
const totalPagesFromServer = ref(1);

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
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[Patients] Falha ao carregar arquivados', error);
    useAlert('Erro ao carregar pacientes arquivados.');
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
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[Patients] Falha ao restaurar paciente', error);
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

const sortKeyToServer = {
  az: 'name_asc',
  za: 'name_desc',
  newest: 'created_at_desc',
  oldest: 'created_at_asc',
};

// Posicionamento inteligente do sort dropdown — Teleport pro body com
// position:fixed pra escapar do `overflow-x: hidden` do .pt-page e clamp
// dentro do viewport (sem corte mesmo quando o botão está perto da borda).
const sortBtnRef = ref(null);
const sortDropdownRef = ref(null);
const sortDropdownStyle = ref({});

const updateSortDropdownPosition = () => {
  const trigger = sortBtnRef.value;
  if (!trigger) return;
  const rect = trigger.getBoundingClientRect();
  const dropdownWidth = 170; // ≈ min-width do menu + padding
  const dropdownHeight = 180;
  const margin = 8;
  const vw = window.innerWidth;
  const vh = window.innerHeight;

  // Alinha pela direita do botão; se estourar a esquerda, gruda em margin.
  let left = rect.right - dropdownWidth;
  if (left < margin) left = margin;
  if (left + dropdownWidth > vw - margin) left = vw - margin - dropdownWidth;

  // Abre pra baixo se couber, senão pra cima.
  const spaceBelow = vh - rect.bottom;
  const goesUp = spaceBelow < dropdownHeight && rect.top > spaceBelow;
  const top = goesUp
    ? Math.max(margin, rect.top - dropdownHeight - 4)
    : rect.bottom + 4;

  sortDropdownStyle.value = {
    position: 'fixed',
    top: `${top}px`,
    left: `${left}px`,
    minWidth: `${dropdownWidth}px`,
    zIndex: 100000,
  };
};

const onSortScrollOrResize = () => {
  if (showSortMenu.value) updateSortDropdownPosition();
};

const toggleSortMenu = async () => {
  if (showSortMenu.value) {
    showSortMenu.value = false;
    return;
  }
  updateSortDropdownPosition();
  showSortMenu.value = true;
  await nextTick();
  updateSortDropdownPosition();
};

watch(showSortMenu, isOpen => {
  if (isOpen) {
    window.addEventListener('scroll', onSortScrollOrResize, true);
    window.addEventListener('resize', onSortScrollOrResize);
  } else {
    window.removeEventListener('scroll', onSortScrollOrResize, true);
    window.removeEventListener('resize', onSortScrollOrResize);
  }
});

const setSortOrder = value => {
  sortOrder.value = value;
  showSortMenu.value = false;
  currentPage.value = 1;
  fetchPatients();
};

const totalPages = computed(() => totalPagesFromServer.value || 1);

const pageNumbers = computed(() => {
  const total = totalPages.value;
  const cur = currentPage.value;
  if (total <= 7) return Array.from({ length: total }, (_, i) => i + 1);
  const pages = new Set([1, total, cur]);
  if (cur > 1) pages.add(cur - 1);
  if (cur < total) pages.add(cur + 1);
  return [...pages].sort((a, b) => a - b);
});

const rangeStart = computed(() =>
  totalCount.value === 0 ? 0 : (currentPage.value - 1) * perPage.value + 1
);
const rangeEnd = computed(() =>
  Math.min(currentPage.value * perPage.value, totalCount.value)
);

function goToPage(n) {
  const target = Math.max(1, Math.min(n, totalPages.value));
  if (target === currentPage.value) return;
  currentPage.value = target;
  fetchPatients();
}

function setPerPage(n) {
  perPage.value = n;
  currentPage.value = 1;
  fetchPatients();
}

// Contador monotônico — cada chamada de fetch incrementa e captura seu id.
// Usuário digita rápido na busca → 3 requests podem estar em vôo → só a
// última deve popular a lista. Descartamos respostas obsoletas.
let latestFetchId = 0;

// `silent` faz um refresh sem trocar a tabela pelo spinner — usado quando a
// aba volta a ficar visível (atualiza o saldo em segundo plano, sem flash).
const fetchPatients = async ({ silent = false } = {}) => {
  latestFetchId += 1;
  const requestId = latestFetchId;
  try {
    if (!silent) isLoading.value = true;
    const response = await PatientsAPI.get({
      page: currentPage.value,
      perPage: perPage.value,
      sort: sortKeyToServer[sortOrder.value] || 'name_asc',
      search: searchQuery.value,
      status: activeFilter.value,
      financialStatus: activeFinancialFilter.value,
    });
    // Descarta resposta obsoleta — outra request mais recente está em vôo
    // (ou já chegou e populou rawPatients).
    if (requestId !== latestFetchId) return;
    rawPatients.value =
      response.data?.payload?.map?.(patient => ({ ...patient })) || [];
    totalCount.value = response.data?.meta?.total_count ?? rawPatients.value.length;
    totalPagesFromServer.value =
      response.data?.meta?.total_pages ??
      Math.max(1, Math.ceil(totalCount.value / perPage.value));
  } catch (error) {
    if (requestId !== latestFetchId) return;
    // eslint-disable-next-line no-console
    console.error('[Patients] Falha ao carregar lista', error);
    useAlert('Erro ao carregar lista de pacientes.');
  } finally {
    // Só a request mais recente limpa o spinner — independente de `silent`,
    // pra um refresh silencioso nunca deixar um loader não-silencioso preso.
    if (requestId === latestFetchId) isLoading.value = false;
  }
};

// Click-outside considera tanto o botão (`pt-sort-wrap`) quanto o dropdown
// teleportado (`pt-sort-dropdown`), que está fora do .pt-sort-wrap no DOM.
const closeSortMenu = e => {
  if (!showSortMenu.value) return;
  if (
    e.target.closest('.pt-sort-wrap') ||
    e.target.closest('.pt-sort-dropdown')
  ) {
    return;
  }
  showSortMenu.value = false;
};

// Saldo é calculado ao vivo no backend a cada request — nunca fica velho lá.
// O que ficava velho era a LISTA montada (ex: aba aberta enquanto um
// lançamento é criado em outra aba/janela): ela só re-buscava no F5. Ao a aba
// voltar a ficar visível, refazemos um fetch silencioso preservando
// página/filtros/ordenação — o saldo se atualiza sem recarregar a página.
const onVisibilityChange = () => {
  if (document.visibilityState !== 'visible') return;
  if (showArchived.value) fetchArchived();
  else fetchPatients({ silent: true });
};

onMounted(() => {
  fetchPatients();
  document.addEventListener('click', closeSortMenu);
  document.addEventListener('visibilitychange', onVisibilityChange);
});
onUnmounted(() => {
  document.removeEventListener('click', closeSortMenu);
  document.removeEventListener('visibilitychange', onVisibilityChange);
  window.removeEventListener('scroll', onSortScrollOrResize, true);
  window.removeEventListener('resize', onSortScrollOrResize);
});

let searchTimeout;
watch(searchQuery, () => {
  clearTimeout(searchTimeout);
  searchTimeout = setTimeout(() => {
    currentPage.value = 1;
    if (showArchived.value) fetchArchived();
    else fetchPatients();
  }, 300);
});
watch(activeFilter, () => {
  currentPage.value = 1;
  fetchPatients();
});
watch(activeFinancialFilter, () => {
  currentPage.value = 1;
  fetchPatients();
});

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
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('[Patients] Falha ao arquivar paciente', error);
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
          <span
            v-if="!showArchived && totalCount > 0"
            class="pt-total-badge"
            :title="`${totalCount} pacientes ativos cadastrados`"
          >
            {{ totalCount }}
          </span>
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
        <!-- Desktop: ícone + label -->
        <BeclinicButton
          variant="faded"
          color="slate"
          icon="i-lucide-archive"
          :label="showArchived ? 'Fechar Arquivo' : 'Arquivados'"
          class="hidden md:inline-flex"
          @click="toggleArchived"
        />
        <BeclinicButton
          v-if="!showArchived"
          variant="solid"
          color="blue"
          icon="i-lucide-plus"
          label="Novo Paciente"
          class="hidden md:inline-flex"
          @click="openNewPatientModal"
        />

        <!-- Mobile: ícone-only no topo (substitui FAB) -->
        <BeclinicButton
          variant="faded"
          color="slate"
          :icon="showArchived ? 'i-lucide-x' : 'i-lucide-archive'"
          :title="showArchived ? 'Fechar Arquivo' : 'Arquivados'"
          class="md:hidden"
          @click="toggleArchived"
        />
        <BeclinicButton
          v-if="!showArchived"
          variant="solid"
          color="blue"
          icon="i-lucide-plus"
          title="Novo Paciente"
          class="md:hidden"
          @click="openNewPatientModal"
        />
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
        <!-- Filtro de status — dropdown com cor por status -->
        <div class="pt-status-select">
          <FormSelect
            v-model="activeFilter"
            :options="STATUS_OPTIONS"
            placeholder="Todos os status"
          />
        </div>

        <!-- Filtro de situação financeira (inadimplente/adimplente) -->
        <div class="pt-status-select">
          <FormSelect
            v-model="activeFinancialFilter"
            :options="FINANCIAL_OPTIONS"
            placeholder="Situação financeira"
          />
        </div>

        <!-- Divider -->
        <div class="pt-divider" />

        <!-- View toggle -->
        <div class="pt-view-toggle">
          <BeclinicButton
            size="sm"
            :variant="viewMode === 'list' ? 'faded' : 'ghost'"
            :color="viewMode === 'list' ? 'blue' : 'slate'"
            icon="i-lucide-list"
            title="Lista"
            @click="setViewMode('list')"
          />
          <BeclinicButton
            size="sm"
            :variant="viewMode === 'grid' ? 'faded' : 'ghost'"
            :color="viewMode === 'grid' ? 'blue' : 'slate'"
            icon="i-lucide-layout-grid"
            title="Grade"
            @click="setViewMode('grid')"
          />
        </div>

        <!-- Sort -->
        <div ref="sortBtnRef" class="pt-sort-wrap">
          <BeclinicButton
            size="sm"
            :variant="showSortMenu ? 'faded' : 'ghost'"
            :color="showSortMenu ? 'blue' : 'slate'"
            icon="i-lucide-arrow-up-down"
            title="Ordenar"
            @click="toggleSortMenu"
          />
          <Teleport to="body">
            <div
              v-if="showSortMenu"
              ref="sortDropdownRef"
              class="pt-sort-dropdown"
              :style="sortDropdownStyle"
            >
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
          </Teleport>
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
          <div class="pt-col pt-col--procedures">Procedimentos</div>
          <div class="pt-col pt-col--balance">Saldo</div>
          <div class="pt-col pt-col--actions" />
        </div>

        <!-- Empty -->
        <div v-if="rawPatients.length === 0" class="pt-empty">
          <div class="pt-empty-icon"><i class="i-lucide-users w-7 h-7" /></div>
          <p class="pt-empty-title">Nenhum paciente encontrado</p>
          <p class="pt-empty-hint">
            {{
              searchQuery || activeFilter || activeFinancialFilter
                ? 'Tente ajustar os filtros.'
                : 'Cadastre o primeiro paciente.'
            }}
          </p>
        </div>

        <!-- Rows -->
        <div
          v-for="patient in rawPatients"
          :key="patient.id"
          class="pt-row"
          @click="openRecord(patient.id)"
        >
          <div class="pt-col pt-col--patient pt-patient-cell">
            <Avatar
              :src="patient.avatar_url"
              :name="patient.name"
              :size="32"
              rounded-full
            />
            <div>
              <p class="pt-patient-name">{{ patient.name }}</p>
              <p class="pt-patient-email">{{ patient.email }}</p>
            </div>
          </div>

          <div class="pt-col pt-col--contact pt-cell-text">
            {{ formatPhone(patient.phone) || '-' }}
          </div>

          <div class="pt-col pt-col--cpf pt-cell-text">
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

          <div
            class="pt-col pt-col--procedures"
            :class="{ 'pt-procedures--zero': (patient.procedures_count || 0) === 0 }"
          >
            {{ patient.procedures_count ?? 0 }}
          </div>

          <div
            class="pt-col pt-col--balance"
            :class="{
              'pt-balance--due': (patient.balance_due_cents || 0) > 0,
              'pt-balance--credit': (patient.balance_due_cents || 0) < 0,
            }"
          >
            <Tooltip :label="balanceTooltip(patient)" position="left" multiline>
              <span class="pt-balance-value">{{
                formatBalanceSigned(patient.balance_due_cents)
              }}</span>
            </Tooltip>
          </div>

          <div class="pt-col pt-col--actions" @click.stop>
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-file-text"
              title="Abrir prontuário"
              @click="openRecord(patient.id)"
            />
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="ruby"
              icon="i-lucide-trash-2"
              title="Arquivar"
              @click="openDeleteModal(patient)"
            />
          </div>
        </div>

        <!-- Pagination footer (list view) -->
        <div v-if="totalCount > 0" class="pt-pagination">
          <div class="pt-pagination__info">
            Exibindo {{ rangeStart }}–{{ rangeEnd }} de {{ totalCount }} pacientes
          </div>
          <div class="pt-pagination__controls">
            <!-- Per-page selector -->
            <FormSelect
              :model-value="perPage"
              :options="perPageSelectOptions"
              class="pt-pagination__per-page mr-2"
              @update:model-value="setPerPage(Number($event))"
            />
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
        <div v-if="rawPatients.length === 0" class="pt-empty pt-empty--grid">
          <div class="pt-empty-icon"><i class="i-lucide-users w-7 h-7" /></div>
          <p class="pt-empty-title">Nenhum paciente encontrado</p>
          <p class="pt-empty-hint">
            {{
              searchQuery || activeFilter || activeFinancialFilter
                ? 'Tente ajustar os filtros.'
                : 'Cadastre o primeiro paciente.'
            }}
          </p>
        </div>

        <div v-for="patient in rawPatients" :key="patient.id" class="pt-card">
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
            <BeclinicButton
              size="sm"
              variant="faded"
              color="blue"
              icon="i-lucide-folder-open"
              label="Abrir Prontuário"
              class="w-full"
              @click="openRecord(patient.id)"
            />
          </div>
        </div>

        <!-- Pagination footer (grid view) -->
        <div v-if="totalCount > 0" class="pt-pagination">
          <div class="pt-pagination__info">
            Exibindo {{ rangeStart }}–{{ rangeEnd }} de {{ totalCount }} pacientes
          </div>
          <div class="pt-pagination__controls">
            <FormSelect
              :model-value="perPage"
              :options="perPageSelectOptions"
              class="pt-pagination__per-page mr-2"
              @update:model-value="setPerPage(Number($event))"
            />
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
              :size="32"
              rounded-full
              class="pt-archived-avatar"
            />
            <div>
              <p class="pt-patient-name">{{ patient.name }}</p>
              <p class="pt-patient-email">{{ patient.email }}</p>
            </div>
          </div>

          <div class="pt-col pt-col--contact pt-cell-text">
            {{ formatPhone(patient.phone) || '-' }}
          </div>

          <div class="pt-col pt-col--cpf pt-cell-text">
            {{ formatCpf(patient.cpf) }}
          </div>

          <div class="pt-col pt-col--date pt-cell-text">
            {{ formatDate(patient.created_at) }}
          </div>

          <div class="pt-col pt-col--actions">
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="slate"
              icon="i-lucide-file-text"
              title="Abrir prontuário"
              @click="openRecord(patient.id)"
            />
            <BeclinicButton
              size="sm"
              variant="ghost"
              color="teal"
              icon="i-lucide-archive-restore"
              :is-loading="isRestoring === patient.id"
              :disabled="isRestoring === patient.id"
              title="Restaurar paciente"
              @click="restorePatient(patient)"
            />
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
