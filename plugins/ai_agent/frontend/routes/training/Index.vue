<script setup>
// Aba "Treinamento" da Bea. State + dispatches concentrados aqui; os filhos
// (Header, EmptyState, Card, modais) só recebem props e emitem eventos.
// Faz polling do status enquanto algum upload está sendo processado pelo job.
import { ref, computed, onMounted, onUnmounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import TrainingDeleteModal from './components/TrainingDeleteModal.vue';
import TrainingBulkApproveModal from './components/TrainingBulkApproveModal.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { PROCESSING_STATUSES } from '@plugins/ai_agent/frontend/store/aiAgentTraining';
import TrainingHeader from './components/TrainingHeader.vue';
import TrainingEmptyState from './components/TrainingEmptyState.vue';
import TrainingCard from './components/TrainingCard.vue';
import TrainingUploadModal from './components/TrainingUploadModal.vue';
import TrainingDetailModal from './components/TrainingDetailModal.vue';
import TrainingFaqsList from './components/TrainingFaqsList.vue';

const store = useStore();
const route = useRoute();

const records = computed(() => store.getters['aiAgentTraining/getRecords']);
const uiFlags = computed(() => store.getters['aiAgentTraining/getUIFlags']);

// Abas: conversas (uploads/pipeline) | faqs (gestão das FAQs aprovadas no RAG).
const activeTab = ref('conversations');

const totalCount = computed(() => records.value.length);
const processing = computed(() =>
  records.value.filter(r => PROCESSING_STATUSES.includes(r.status))
);

// --- Polling de status (job assíncrono) ---
let pollTimer = null;
const POLL_INTERVAL = 3000;

const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};

const startPolling = () => {
  if (pollTimer) return;
  pollTimer = setInterval(() => {
    if (processing.value.length === 0) {
      stopPolling();
      return;
    }
    processing.value.forEach(r =>
      store.dispatch('aiAgentTraining/refresh', r.id)
    );
  }, POLL_INTERVAL);
};

// --- Upload modal ---
const showUpload = ref(false);

const openUpload = () => {
  showUpload.value = true;
};
const closeUpload = () => {
  showUpload.value = false;
};

const save = async ({ zipFiles }) => {
  try {
    // Uma conversa de treinamento por arquivo enviado.
    await Promise.all(
      zipFiles.map(zipFile =>
        store.dispatch('aiAgentTraining/create', { zipFile })
      )
    );
    closeUpload();
    startPolling();
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

// --- Detail modal ---
const showDetail = ref(false);
const detailRecord = ref(null);

const openDetail = async training => {
  // A lista guarda só o resumo — busca o registro completo (parsed_messages).
  detailRecord.value = await store.dispatch(
    'aiAgentTraining/refresh',
    training.id
  );
  showDetail.value = true;
};

const handlePublish = async faqs => {
  if (!detailRecord.value) return;
  try {
    detailRecord.value = await store.dispatch('aiAgentTraining/publish', {
      id: detailRecord.value.id,
      faqs,
    });
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

// --- Seleção da clínica (status awaiting_clinic) ---
const handleSelectClinic = async (training, clinicSenderName) => {
  try {
    await store.dispatch('aiAgentTraining/selectClinic', {
      id: training.id,
      clinicSenderName,
    });
    startPolling();
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

// --- Delete (ConfirmDangerModal) ---
const confirmDeleteRecord = ref(null);
const confirmDeleteOpen = computed({
  get: () => confirmDeleteRecord.value !== null,
  set: val => {
    if (!val) confirmDeleteRecord.value = null;
  },
});

const removeRecord = training => {
  confirmDeleteRecord.value = training;
};

const handleConfirmDelete = async mode => {
  const training = confirmDeleteRecord.value;
  if (!training) return;
  try {
    await store.dispatch('aiAgentTraining/delete', { id: training.id, mode });
  } finally {
    confirmDeleteRecord.value = null;
  }
};

// --- Revisar e aprovar TODAS as FAQs sugeridas (em massa) ---
// Pendentes = conversas concluídas que ainda não foram publicadas.
const pendingFaqCount = computed(() =>
  records.value
    .filter(r => r.status === 'completed' && !r.published_at)
    .reduce((sum, r) => sum + (r.faq_count || 0), 0)
);
const showBulkApprove = ref(false);
const bulkApproveFaqs = ref([]);
const loadingPending = ref(false);

const openBulkApprove = async () => {
  showBulkApprove.value = true;
  loadingPending.value = true;
  try {
    bulkApproveFaqs.value =
      (await store.dispatch('aiAgentTraining/fetchPendingFaqs')) || [];
  } finally {
    loadingPending.value = false;
  }
};
const handleApproveAll = async ids => {
  try {
    await store.dispatch('aiAgentTraining/approveAll', { ids });
    showBulkApprove.value = false;
    bulkApproveFaqs.value = [];
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

// --- Apagar TODAS as conversas (em massa) ---
const showBulkDelete = ref(false);
const openBulkDelete = () => {
  showBulkDelete.value = true;
};
const handleBulkDelete = async mode => {
  try {
    await store.dispatch('aiAgentTraining/deleteAll', { mode });
  } finally {
    showBulkDelete.value = false;
  }
};

// MT-19 — defesa em profundidade pra account-switch.
watch(
  () => Number(route.params.accountId),
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      stopPolling();
      store.dispatch('aiAgentTraining/reset');
      store.dispatch('aiAgentTraining/fetch').then(() => {
        if (processing.value.length > 0) startPolling();
      });
    }
  }
);

onMounted(async () => {
  await store.dispatch('aiAgentTraining/fetch');
  if (processing.value.length > 0) startPolling();
});

onUnmounted(stopPolling);
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background overflow-hidden">
    <TrainingHeader :total-count="totalCount" @create="openUpload" />

    <main class="flex-1 overflow-y-auto">
      <div class="px-8 py-8 w-full">
        <!-- Abas -->
        <div class="flex items-center gap-1 mb-6 border-b border-n-weak">
          <button
            type="button"
            class="px-4 py-2.5 text-sm font-medium -mb-px border-b-2 transition-colors"
            :class="
              activeTab === 'conversations'
                ? 'border-woot-500 text-woot-600'
                : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
            "
            @click="activeTab = 'conversations'"
          >
            {{ $t('AI_AGENT.TRAINING.TABS.CONVERSATIONS') }}
          </button>
          <button
            type="button"
            class="px-4 py-2.5 text-sm font-medium -mb-px border-b-2 transition-colors"
            :class="
              activeTab === 'faqs'
                ? 'border-woot-500 text-woot-600'
                : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
            "
            @click="activeTab = 'faqs'"
          >
            {{ $t('AI_AGENT.TRAINING.TABS.FAQS') }}
          </button>

          <!-- Revisar + aprovar todas as FAQs sugeridas pendentes -->
          <BeclinicButton
            v-if="activeTab === 'conversations' && pendingFaqCount > 0"
            class="ml-auto mb-1.5"
            :label="
              $t('AI_AGENT.TRAINING.REVIEW_FAQS_BUTTON', {
                count: pendingFaqCount,
              })
            "
            icon="i-lucide-sparkles"
            variant="outline"
            color="teal"
            size="sm"
            @click="openBulkApprove"
          />

          <!-- Apagar todas as conversas (em massa) -->
          <BeclinicButton
            v-if="activeTab === 'conversations' && records.length > 0"
            class="mb-1.5"
            :class="{ 'ml-auto': pendingFaqCount === 0 }"
            :label="$t('AI_AGENT.TRAINING.DELETE_ALL_BUTTON')"
            icon="i-lucide-trash-2"
            variant="outline"
            color="ruby"
            size="sm"
            @click="openBulkDelete"
          />
        </div>

        <!-- Aba: conversas -->
        <template v-if="activeTab === 'conversations'">
          <!-- Loading -->
          <div
            v-if="uiFlags.isFetching && records.length === 0"
            class="flex items-center justify-center py-20"
          >
            <div class="flex items-center gap-3 text-sm text-n-slate-10">
              <svg
                class="w-4 h-4 animate-spin"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
              >
                <path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round" />
              </svg>
              {{ $t('AI_AGENT.TRAINING.LOADING') }}
            </div>
          </div>

          <!-- Empty state -->
          <TrainingEmptyState
            v-else-if="records.length === 0"
            @create="openUpload"
          />

          <!-- Grid de cards -->
          <div
            v-else
            class="grid gap-4 grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3"
          >
            <TrainingCard
              v-for="training in records"
              :key="training.id"
              :training="training"
              @view="openDetail"
              @delete="removeRecord"
              @select-clinic="name => handleSelectClinic(training, name)"
            />
          </div>
        </template>

        <!-- Aba: FAQs aprovadas -->
        <TrainingFaqsList v-else />
      </div>
    </main>

    <TrainingUploadModal
      v-model:show="showUpload"
      :is-saving="uiFlags.isCreating"
      @save="save"
    />

    <TrainingDetailModal
      v-model:show="showDetail"
      :training="detailRecord"
      :is-publishing="uiFlags.isPublishing"
      @publish="handlePublish"
    />

    <TrainingDeleteModal
      v-model:show="confirmDeleteOpen"
      :name="confirmDeleteRecord ? confirmDeleteRecord.name : ''"
      :loading="uiFlags.isDeleting"
      @confirm="handleConfirmDelete"
    />

    <TrainingDeleteModal
      v-model:show="showBulkDelete"
      :count="totalCount"
      :loading="uiFlags.isDeleting"
      @confirm="handleBulkDelete"
    />

    <TrainingBulkApproveModal
      v-model:show="showBulkApprove"
      :faqs="bulkApproveFaqs"
      :is-loading="loadingPending"
      :is-approving="uiFlags.isApproving"
      @approve="handleApproveAll"
    />
  </div>
</template>
