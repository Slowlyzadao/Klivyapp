<script setup>
// Área central das FAQs já aprovadas/publicadas no RAG da Bea (agregadas de
// todas as conversas). Permite buscar, editar a resposta/pergunta (inline) e
// apagar — cada ação re-publica o RAG via backend.
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';

const store = useStore();

const records = computed(() => store.getters['aiAgentTrainingFaqs/getRecords']);
const uiFlags = computed(() => store.getters['aiAgentTrainingFaqs/getUIFlags']);

const search = ref('');
const filtered = computed(() => {
  const q = search.value.trim().toLowerCase();
  if (!q) return records.value;
  return records.value.filter(f =>
    [f.pergunta_paciente, f.resposta_clinica, f.categoria, f.origem]
      .filter(Boolean)
      .some(v => v.toLowerCase().includes(q))
  );
});

// --- Edição inline ---
const editingId = ref(null);
const draft = ref({ pergunta_paciente: '', resposta_clinica: '' });

const startEdit = faq => {
  editingId.value = faq.id;
  draft.value = {
    pergunta_paciente: faq.pergunta_paciente,
    resposta_clinica: faq.resposta_clinica,
  };
};
const cancelEdit = () => {
  editingId.value = null;
};
const saveEdit = async faq => {
  try {
    await store.dispatch('aiAgentTrainingFaqs/update', {
      id: faq.id,
      faq: { ...draft.value },
    });
    editingId.value = null;
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

// --- Apagar (ConfirmDangerModal) ---
const confirmDelete = ref(null);
const confirmDeleteOpen = computed({
  get: () => confirmDelete.value !== null,
  set: v => {
    if (!v) confirmDelete.value = null;
  },
});
const askDelete = faq => {
  confirmDelete.value = faq;
};
const doDelete = async () => {
  const faq = confirmDelete.value;
  if (!faq) return;
  try {
    await store.dispatch('aiAgentTrainingFaqs/delete', faq.id);
  } finally {
    confirmDelete.value = null;
  }
};

// --- Seleção em massa ---
const selecting = ref(false);
const selectedIds = ref([]);

const isSelected = id => selectedIds.value.includes(id);
const toggleSelect = id => {
  selectedIds.value = isSelected(id)
    ? selectedIds.value.filter(x => x !== id)
    : [...selectedIds.value, id];
};
const allFilteredSelected = computed(
  () => filtered.value.length > 0 && filtered.value.every(f => isSelected(f.id))
);
const toggleSelectAll = () => {
  const ids = filtered.value.map(f => f.id);
  if (allFilteredSelected.value) {
    const set = new Set(ids);
    selectedIds.value = selectedIds.value.filter(id => !set.has(id));
  } else {
    selectedIds.value = [...new Set([...selectedIds.value, ...ids])];
  }
};
const enterSelect = () => {
  selecting.value = true;
};
const exitSelect = () => {
  selecting.value = false;
  selectedIds.value = [];
};

// --- Apagar em massa (todas / selecionadas) — confirmação única ---
const bulkConfirm = ref(null); // { type: 'all' | 'selected', count }
const bulkConfirmOpen = computed({
  get: () => bulkConfirm.value !== null,
  set: v => {
    if (!v) bulkConfirm.value = null;
  },
});
const askDeleteAll = () => {
  bulkConfirm.value = { type: 'all', count: records.value.length };
};
const askDeleteSelected = () => {
  if (!selectedIds.value.length) return;
  bulkConfirm.value = { type: 'selected', count: selectedIds.value.length };
};
const doBulkDelete = async () => {
  const action = bulkConfirm.value;
  if (!action) return;
  try {
    const ids = action.type === 'all' ? [] : selectedIds.value;
    await store.dispatch('aiAgentTrainingFaqs/deleteMany', ids);
    exitSelect();
  } finally {
    bulkConfirm.value = null;
  }
};

onMounted(() => store.dispatch('aiAgentTrainingFaqs/fetch'));
</script>

<template>
  <div>
    <!-- Busca + contador -->
    <div class="flex items-center gap-3 mb-5">
      <div class="relative flex-1 max-w-md">
        <svg
          class="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-n-slate-10"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <circle cx="11" cy="11" r="8" />
          <path d="m21 21-4.3-4.3" />
        </svg>
        <input
          v-model="search"
          type="text"
          :placeholder="$t('AI_AGENT.TRAINING.FAQS_TAB.SEARCH')"
          class="w-full pl-9 pr-3 py-2 text-sm rounded-lg border border-n-weak bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-10 focus:border-woot-500 focus:outline-none transition-colors"
        />
      </div>
      <span class="text-xs text-n-slate-10">
        {{ $t('AI_AGENT.TRAINING.FAQS_TAB.COUNT', { count: filtered.length }) }}
      </span>

      <!-- Ações em massa -->
      <div
        v-if="records.length > 0"
        class="ml-auto flex items-center gap-2 shrink-0"
      >
        <template v-if="!selecting">
          <BeclinicButton
            :label="$t('AI_AGENT.TRAINING.FAQS_TAB.SELECT')"
            icon="i-lucide-list-checks"
            variant="outline"
            color="slate"
            size="sm"
            @click="enterSelect"
          />
          <BeclinicButton
            :label="$t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_ALL')"
            icon="i-lucide-trash-2"
            variant="outline"
            color="ruby"
            size="sm"
            @click="askDeleteAll"
          />
        </template>
        <template v-else>
          <BeclinicButton
            :label="$t('AI_AGENT.TRAINING.FAQS_TAB.CANCEL')"
            variant="ghost"
            color="slate"
            size="sm"
            @click="exitSelect"
          />
          <BeclinicButton
            :label="$t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_SELECTED')"
            icon="i-lucide-trash-2"
            color="ruby"
            size="sm"
            :disabled="selectedIds.length === 0"
            @click="askDeleteSelected"
          />
        </template>
      </div>
    </div>

    <!-- Barra de seleção (selecionar todas + contador) -->
    <div
      v-if="selecting && filtered.length > 0"
      class="flex items-center gap-3 mb-3 px-1"
    >
      <Checkbox
        :model-value="allFilteredSelected"
        :label="$t('AI_AGENT.TRAINING.FAQS_TAB.SELECT_ALL')"
        @change="toggleSelectAll"
      />
      <span class="text-xs text-n-slate-10">
        {{
          $t('AI_AGENT.TRAINING.FAQS_TAB.SELECTED_COUNT', {
            count: selectedIds.length,
          })
        }}
      </span>
    </div>

    <!-- Loading -->
    <div
      v-if="uiFlags.isFetching && records.length === 0"
      class="flex items-center justify-center py-16 text-sm text-n-slate-10 gap-3"
    >
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

    <!-- Vazio -->
    <div
      v-else-if="filtered.length === 0"
      class="flex flex-col items-center justify-center py-16 text-center"
    >
      <p class="text-sm font-medium text-n-slate-12">
        {{ $t('AI_AGENT.TRAINING.FAQS_TAB.EMPTY_TITLE') }}
      </p>
      <p class="text-sm text-n-slate-10 mt-1 max-w-md">
        {{ $t('AI_AGENT.TRAINING.FAQS_TAB.EMPTY_HINT') }}
      </p>
    </div>

    <!-- Lista -->
    <div v-else class="space-y-3">
      <article
        v-for="faq in filtered"
        :key="faq.id"
        class="rounded-xl border p-4 transition-shadow"
        :class="[
          faq.duplicate
            ? 'border-amber-300 bg-amber-50'
            : 'border-n-weak bg-n-solid-1',
          selecting && isSelected(faq.id) ? 'ring-2 ring-woot-400' : '',
        ]"
      >
        <div class="flex gap-3">
          <Checkbox
            v-if="selecting"
            class="mt-0.5 shrink-0"
            :model-value="isSelected(faq.id)"
            :aria-label="$t('AI_AGENT.TRAINING.FAQS_TAB.SELECT')"
            @change="toggleSelect(faq.id)"
          />
          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-2 mb-2 flex-wrap">
              <span
                v-if="faq.categoria"
                class="inline-flex items-center px-2 py-0.5 text-[11px] font-medium rounded-md bg-woot-50 text-woot-700"
              >
                {{ faq.categoria }}
              </span>
              <span
                v-if="faq.duplicate"
                class="inline-flex items-center px-2 py-0.5 text-[11px] font-medium rounded-md bg-amber-100 text-amber-700"
                :title="$t('AI_AGENT.TRAINING.FAQS_TAB.DUPLICATE_HINT')"
              >
                {{ $t('AI_AGENT.TRAINING.FAQS_TAB.DUPLICATE') }}
              </span>
              <span class="text-[11px] text-n-slate-10">
                {{
                  $t('AI_AGENT.TRAINING.FAQS_TAB.ORIGIN', { name: faq.origem })
                }}
              </span>
            </div>

            <!-- Modo edição -->
            <template v-if="editingId === faq.id">
              <input
                v-model="draft.pergunta_paciente"
                type="text"
                class="w-full px-3 py-2 text-sm font-medium rounded-lg border border-n-weak bg-n-alpha-1 text-n-slate-12 focus:border-woot-500 focus:outline-none mb-2"
              />
              <textarea
                v-model="draft.resposta_clinica"
                rows="3"
                class="w-full px-3 py-2 text-sm rounded-lg border border-n-weak bg-n-alpha-1 text-n-slate-12 focus:border-woot-500 focus:outline-none resize-y"
              />
              <div class="flex items-center justify-end gap-2 mt-2">
                <BeclinicButton
                  :label="$t('AI_AGENT.TRAINING.FAQS_TAB.CANCEL')"
                  variant="outline"
                  color="slate"
                  size="sm"
                  @click="cancelEdit"
                />
                <BeclinicButton
                  :label="$t('AI_AGENT.TRAINING.FAQS_TAB.SAVE')"
                  size="sm"
                  :is-loading="uiFlags.isUpdating"
                  @click="saveEdit(faq)"
                />
              </div>
            </template>

            <!-- Modo visualização -->
            <template v-else>
              <p class="text-sm font-semibold text-n-slate-12">
                {{ faq.pergunta_paciente }}
              </p>
              <p class="text-sm text-n-slate-11 mt-1 leading-relaxed">
                {{ faq.resposta_clinica }}
              </p>
              <div class="flex items-center gap-1 mt-3">
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                  @click="startEdit(faq)"
                >
                  <svg
                    class="w-3.5 h-3.5"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path
                      d="M12 20h9M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"
                    />
                  </svg>
                  {{ $t('AI_AGENT.TRAINING.FAQS_TAB.EDIT') }}
                </button>
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1.5 text-xs font-medium text-ruby-600 hover:bg-ruby-100 rounded-lg transition-colors"
                  @click="askDelete(faq)"
                >
                  <svg
                    class="w-3.5 h-3.5"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path
                      d="M3 6h18M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"
                    />
                  </svg>
                  {{ $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE') }}
                </button>
              </div>
            </template>
          </div>
        </div>
      </article>
    </div>

    <ConfirmDangerModal
      v-model:show="confirmDeleteOpen"
      :title="$t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_TITLE')"
      :message="$t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_MESSAGE')"
      :confirm-label="$t('AI_AGENT.TRAINING.FAQS_TAB.DELETE')"
      :loading="uiFlags.isDeleting"
      @confirm="doDelete"
    />

    <ConfirmDangerModal
      v-model:show="bulkConfirmOpen"
      :title="
        bulkConfirm?.type === 'all'
          ? $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_ALL_TITLE')
          : $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_SELECTED_TITLE')
      "
      :message="
        bulkConfirm?.type === 'all'
          ? $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_ALL_MESSAGE', {
              count: bulkConfirm?.count,
            })
          : $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_SELECTED_MESSAGE', {
              count: bulkConfirm?.count,
            })
      "
      :confirm-label="
        bulkConfirm?.type === 'all'
          ? $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_ALL')
          : $t('AI_AGENT.TRAINING.FAQS_TAB.DELETE_SELECTED')
      "
      :loading="uiFlags.isDeleting"
      @confirm="doBulkDelete"
    />
  </div>
</template>
