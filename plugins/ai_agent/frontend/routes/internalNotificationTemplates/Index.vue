<script setup>
import { ref, computed, onMounted, reactive, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
// FE-7 (auditoria 2026-05-18): ConfirmDangerModal padrão substituindo
// window.confirm (que bloqueia main thread e ignora tema dark).
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
// FE-4 (auditoria 2026-05-18): Index.vue decomposto em sub-componentes
// (Header, Card, FormModal). State + handlers + dispatches ficam aqui —
// filhos recebem props e emitem eventos.
import TemplatesHeader from './components/TemplatesHeader.vue';
import TemplateCard from './components/TemplateCard.vue';
import TemplateFormModal from './components/TemplateFormModal.vue';

const { t } = useI18n();

const store = useStore();
const route = useRoute();

const records = computed(() => store.getters['aiAgentInternalNotificationTemplates/getRecords']);
const catalog = computed(() => store.getters['aiAgentInternalNotificationTemplates/getCatalog']);
const uiFlags = computed(() => store.getters['aiAgentInternalNotificationTemplates/getUIFlags']);

const showModal = ref(false);
const editingId = ref(null);

const emptyForm = () => ({
  event_key: '',
  name: '',
  body: '',
  target_type: 'room',
  target_id: null,
  enabled: true,
});

const form = reactive(emptyForm());

const editingTemplate = computed(() =>
  records.value.find(r => r.id === editingId.value)
);

const openEdit = template => {
  Object.assign(form, {
    event_key: template.event_key,
    name: template.name,
    body: template.body,
    target_type: template.target_type,
    target_id: template.target_id,
    enabled: template.enabled,
  });
  editingId.value = template.id;
  showModal.value = true;
};

const closeModal = () => {
  showModal.value = false;
  editingId.value = null;
};

const save = async () => {
  const payload = { ...form };
  // se desactivated, target_id deve ser null
  if (payload.target_type === 'disabled') payload.target_id = null;

  try {
    await store.dispatch('aiAgentInternalNotificationTemplates/update', { id: editingId.value, ...payload });
    closeModal();
  } catch (e) {
    /* throwErrorMessage já dispara toast */
  }
};

// UX-fix 2026-05-19: antes este toggle só enviava `{ enabled }`. Como
// templates seedados nascem com `target_type='disabled'`, ativar via
// botão fazia o backend salvar `enabled=true` mas o Router continuava
// bloqueando o dispatch (`disabled?` exige `target_type != 'disabled'`).
// Resultado: clique sem feedback, badge "0 ativos" inerte.
//
// Agora: backend auto-promove pra `room` (reception) quando recebe
// `enabled=true` num template disabled. Frontend interpreta 422 com
// `code='destination_required'` abrindo modal de edição (fallback pra
// contas sem sala reception).
// UX-fix 2026-05-19: usa action `toggleEnabled` (não `update`) porque
// só ela propaga o erro original do axios — `update` converte pra
// `new Error(string)` via `throwErrorMessage` e perde o `.code`.
// Backend auto-promove `target_type='disabled'` pra `room` (reception)
// quando recebe `enabled=true` num template ainda sem destino. Se não
// houver sala reception, 422 com `code='destination_required'` faz
// abrir o modal de edição.
const toggleEnabled = async template => {
  const willActivate = !template.enabled;
  try {
    const updated = await store.dispatch('aiAgentInternalNotificationTemplates/toggleEnabled', {
      id: template.id,
      enabled: willActivate,
    });

    if (willActivate) {
      const promoted = template.target_type === 'disabled' && updated.target_type !== 'disabled';
      const key = promoted
        ? 'AI_AGENT.TEMPLATES.TOAST.ACTIVATED_AND_PROMOTED'
        : 'AI_AGENT.TEMPLATES.TOAST.ACTIVATED';
      useAlert(t(key, { target: updated.target_label }));
    } else {
      useAlert(t('AI_AGENT.TEMPLATES.TOAST.PAUSED'));
    }
  } catch (error) {
    if (error?.response?.data?.code === 'destination_required') {
      useAlert(t('AI_AGENT.TEMPLATES.TOAST.NEEDS_DESTINATION'));
      openEdit(template);
    } else {
      const msg = error?.response?.data?.errors?.[0]
                  || error?.message
                  || t('AI_AGENT.TEMPLATES.TOAST.GENERIC_ERROR');
      useAlert(msg);
    }
  }
};

// Disparado pelo callout "Configure destino" do TemplateCard.
const openConfigure = template => openEdit(template);

// FE-7: state do modal de confirmação de reset (substituindo window.confirm).
const confirmResetTemplate = ref(null);
const confirmResetOpen = computed({
  get: () => confirmResetTemplate.value !== null,
  set: val => { if (!val) confirmResetTemplate.value = null; },
});

const resetTemplate = template => {
  confirmResetTemplate.value = template;
};

const handleConfirmReset = async () => {
  const template = confirmResetTemplate.value;
  if (!template) return;
  try {
    await store.dispatch('aiAgentInternalNotificationTemplates/reset', template.id);
  } finally {
    confirmResetTemplate.value = null;
  }
};

const cardCount = computed(() => records.value.length);
const activeCount = computed(() => records.value.filter(r => r.enabled && r.target_type !== 'disabled').length);

// MT-19 — defesa em profundidade pra account-switch. Action é `resetStore`
// (não `reset`) porque `reset(id)` no store já é "restaurar template ao
// default via API" — outro caso de uso semântico.
watch(
  () => Number(route.params.accountId),
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      store.dispatch('aiAgentInternalNotificationTemplates/resetStore');
      store.dispatch('aiAgentInternalNotificationTemplates/fetch');
      store.dispatch('aiAgentInternalNotificationTemplates/fetchCatalog');
    }
  }
);

onMounted(() => {
  store.dispatch('aiAgentInternalNotificationTemplates/fetch');
  store.dispatch('aiAgentInternalNotificationTemplates/fetchCatalog');
});
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background overflow-hidden">
    <TemplatesHeader
      :active-count="activeCount"
      :card-count="cardCount"
    />

    <main class="flex-1 overflow-y-auto">
      <div class="px-8 py-8 w-full">
        <!-- Loading -->
        <div v-if="uiFlags.isFetching && records.length === 0" class="flex items-center justify-center py-20">
          <div class="flex items-center gap-3 text-sm text-n-slate-10">
            <svg class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round"/></svg>
            Carregando templates…
          </div>
        </div>

        <!-- Cards -->
        <div v-else class="grid gap-4 grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3">
          <TemplateCard
            v-for="t in records"
            :key="t.id"
            :template="t"
            @edit="openEdit"
            @toggle="toggleEnabled"
            @reset="resetTemplate"
            @configure="openConfigure"
          />
        </div>
      </div>
    </main>

    <TemplateFormModal
      v-model:show="showModal"
      :editing-template="editingTemplate"
      :form="form"
      :is-saving="uiFlags.isUpdating"
      :catalog="catalog"
      @save="save"
    />

    <!-- FE-7: confirmação de reset em modal styled (sem window.confirm). -->
    <ConfirmDangerModal
      v-model:show="confirmResetOpen"
      :title="$t('AI_AGENT.TEMPLATES.RESET_TITLE')"
      :message="confirmResetTemplate ? $t('AI_AGENT.TEMPLATES.RESET_MESSAGE', { label: confirmResetTemplate.event_label }) : ''"
      :confirm-label="$t('AI_AGENT.TEMPLATES.RESET_CONFIRM')"
      :loading="uiFlags.isResetting"
      @confirm="handleConfirmReset"
    />
  </div>
</template>
