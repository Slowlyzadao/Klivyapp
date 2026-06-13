<script setup>
import { ref, computed, onMounted, reactive, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
// FE-7 (auditoria 2026-05-18): substitui `window.confirm` por
// ConfirmDangerModal padrão do beclinic_core. Bloqueia o thread main,
// rompe o estilo visual do Klivy e não suporta dark mode.
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
// FE-3 (auditoria 2026-05-18): Index.vue decomposto em sub-componentes
// (Header, EmptyState, RuleCard, FormModal). State + handlers + dispatches
// continuam aqui — filhos só recebem props e emitem eventos.
import FollowUpsHeader from './components/FollowUpsHeader.vue';
import FollowUpsEmptyState from './components/FollowUpsEmptyState.vue';
import FollowUpRuleCard from './components/FollowUpRuleCard.vue';
import FollowUpFormModal from './components/FollowUpFormModal.vue';
// Fase 6: lista de serviços do agenda (SÓ LEITURA) pro picker de reativação.
import AgendaServicesAPI from '@plugins/agenda/frontend/api/agendaServices';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

// Serviços do agenda pro picker de service_recall. Leitura via API do
// próprio agenda (sem store próprio aqui) — não escrevemos nada lá.
const agendaServices = ref([]);
const loadAgendaServices = async () => {
  try {
    const { data } = await AgendaServicesAPI.get();
    agendaServices.value = Array.isArray(data) ? data : data?.services || [];
  } catch (e) {
    agendaServices.value = [];
  }
};

const records = computed(
  () => store.getters['aiAgentFollowUpRules/getRecords']
);
const uiFlags = computed(
  () => store.getters['aiAgentFollowUpRules/getUIFlags']
);

const showModal = ref(false);
const editingId = ref(null);

const emptyForm = () => ({
  name: '',
  trigger_type: 'pre_appointment',
  offset_hours: 24,
  offset_unit: 'hours',
  applies_to: 'both',
  // Modo de ação (Fase 2): 'generative' (Bea escreve) | 'static' (mensagem fixa)
  action_type: 'generative',
  context_brief: '',
  static_body: '',
  // Persona/tom por tipo (Fase 5) — só usado no modo generativo.
  persona_override: '',
  // Reativação por serviço (Fase 6) — só no trigger service_recall.
  agenda_service_id: null,
  recall_interval_value: 6,
  recall_interval_unit: 'months',
  // Condições de saída (Fase 3) — ligadas por padrão em regras novas.
  stop_on_reply: true,
  stop_on_booking: true,
  // Fallback de template (Fase 4) — envio fora da janela de 24h no WhatsApp oficial.
  cloud_template_name: '',
  cloud_template_lang: 'pt_BR',
  cloud_template_params: [],
  max_per_target: 1,
  // Cooldown anti-spam por regra (min). 0 = sem cooldown. Default 10.
  cooldown_minutes: 10,
  enabled: true,
  // Passos ADICIONAIS da cadência (2..N). O passo 1 são os campos acima.
  // Cada item: { offset_hours, offset_unit, context_brief, static_body }.
  steps: [],
});

// Cadência só faz sentido nos gatilhos cron (os event-driven/custom não
// iteram passos). Mantém em sincronia com o CandidateFinder.
const CADENCE_TRIGGERS = [
  'pre_appointment',
  'post_appointment',
  'no_show',
  'no_response',
];

// `stop_on_booking` só faz sentido onde (re)agendar é o objetivo — não em
// pre_appointment (o paciente já tem a consulta que está sendo lembrada).
const BOOKING_STOP_TRIGGERS = ['post_appointment', 'no_show', 'no_response'];

// Onde o fallback de template faz sentido (pode cair fora das 24h): cadência
// + reativação por serviço (que é SEMPRE fora da janela). Tem que casar com
// a visibilidade da seção de template no modal (showCadence || isServiceRecall).
const TEMPLATE_TRIGGERS = [...CADENCE_TRIGGERS, 'service_recall'];

// Triggers que de fato usam o filtro applies_to (origem do AgendaEvent).
const AGENDA_TRIGGERS = [
  'pre_appointment',
  'post_appointment',
  'no_show',
  'appointment_confirmed',
];

const form = reactive(emptyForm());

const activeCount = computed(() => records.value.filter(r => r.enabled).length);
const totalCount = computed(() => records.value.length);

const openCreate = () => {
  Object.assign(form, emptyForm());
  editingId.value = null;
  showModal.value = true;
};

const openEdit = rule => {
  Object.assign(form, {
    name: rule.name,
    trigger_type: rule.trigger_type,
    offset_hours: rule.offset_hours,
    offset_unit: rule.offset_unit || 'hours',
    applies_to: rule.applies_to || 'both',
    action_type: rule.action_type || 'generative',
    context_brief: rule.context_brief || '',
    static_body: rule.static_body || '',
    persona_override: rule.persona_override || '',
    agenda_service_id: rule.agenda_service_id ?? null,
    recall_interval_value: rule.recall_interval_value ?? 6,
    recall_interval_unit: rule.recall_interval_unit || 'months',
    stop_on_reply: rule.stop_on_reply ?? true,
    stop_on_booking: rule.stop_on_booking ?? true,
    cloud_template_name: rule.cloud_template_name || '',
    cloud_template_lang: rule.cloud_template_lang || 'pt_BR',
    cloud_template_params: [...(rule.cloud_template_params || [])],
    max_per_target: rule.max_per_target,
    cooldown_minutes: rule.cooldown_minutes ?? 10,
    enabled: rule.enabled,
    steps: (rule.steps || []).map(s => ({
      offset_hours: s.offset_hours,
      offset_unit: s.offset_unit || 'hours',
      context_brief: s.context_brief || '',
      static_body: s.static_body || '',
    })),
  });
  editingId.value = rule.id;
  showModal.value = true;
};

const closeModal = () => {
  showModal.value = false;
  editingId.value = null;
};

const save = async () => {
  // Cadência só vale pros gatilhos cron; nos demais, zera os passos
  // extras pra não persistir lixo que o dispatcher nunca usaria.
  const steps = CADENCE_TRIGGERS.includes(form.trigger_type)
    ? form.steps.map(s => ({
        offset_hours: Number(s.offset_hours),
        offset_unit: s.offset_unit,
        context_brief: s.context_brief,
        static_body: s.static_body,
      }))
    : [];
  const payload = {
    ...form,
    offset_hours: Number(form.offset_hours),
    max_per_target: Number(form.max_per_target),
    cooldown_minutes: Number(form.cooldown_minutes),
    // applies_to só vale pros triggers de agenda; normaliza pra 'both' nos
    // demais (senão fica um valor obsoleto persistido + badge enganoso).
    applies_to: AGENDA_TRIGGERS.includes(form.trigger_type)
      ? form.applies_to
      : 'both',
    // Gates: condições de saída só valem onde fazem sentido.
    stop_on_reply: CADENCE_TRIGGERS.includes(form.trigger_type)
      ? form.stop_on_reply
      : false,
    stop_on_booking: BOOKING_STOP_TRIGGERS.includes(form.trigger_type)
      ? form.stop_on_booking
      : false,
    // Template vale na cadência E na reativação por serviço (sempre fora
    // das 24h). Limpa só nos triggers que nem mostram a seção. Os params
    // exigem nome presente — sem nome a seção fica oculta e mandar o
    // array antigo persistiria lixo órfão pra sempre.
    cloud_template_name: TEMPLATE_TRIGGERS.includes(form.trigger_type)
      ? form.cloud_template_name
      : '',
    cloud_template_params:
      TEMPLATE_TRIGGERS.includes(form.trigger_type) && form.cloud_template_name
        ? form.cloud_template_params
        : [],
    // Reativação por serviço: só envia serviço/intervalo nesse trigger.
    agenda_service_id:
      form.trigger_type === 'service_recall' ? form.agenda_service_id : null,
    recall_interval_value:
      form.trigger_type === 'service_recall'
        ? Number(form.recall_interval_value)
        : null,
    recall_interval_unit: form.recall_interval_unit || 'months',
    steps,
  };
  try {
    if (editingId.value) {
      await store.dispatch('aiAgentFollowUpRules/update', {
        id: editingId.value,
        ...payload,
      });
    } else {
      await store.dispatch('aiAgentFollowUpRules/create', payload);
    }
    closeModal();
  } catch (e) {
    // throwErrorMessage do store só re-lança o erro com a mensagem do
    // backend já extraída (errors[0]) — o toast é responsabilidade daqui.
    useAlert(e?.message || t('AI_AGENT.FOLLOW_UPS.SAVE_ERROR'));
  }
};

const toggleEnabled = async rule => {
  try {
    await store.dispatch('aiAgentFollowUpRules/update', {
      id: rule.id,
      enabled: !rule.enabled,
    });
  } catch (e) {
    useAlert(e?.message || t('AI_AGENT.FOLLOW_UPS.TOGGLE_ERROR'));
  }
};

// FE-7: state do modal de confirmação substituindo window.confirm.
const confirmDeleteRule = ref(null);
const confirmDeleteOpen = computed({
  get: () => confirmDeleteRule.value !== null,
  set: val => {
    if (!val) confirmDeleteRule.value = null;
  },
});

const removeRule = rule => {
  confirmDeleteRule.value = rule;
};

const handleConfirmDelete = async () => {
  const rule = confirmDeleteRule.value;
  if (!rule) return;
  try {
    await store.dispatch('aiAgentFollowUpRules/delete', rule.id);
  } catch (e) {
    useAlert(e?.message || t('AI_AGENT.FOLLOW_UPS.DELETE_ERROR'));
  } finally {
    confirmDeleteRule.value = null;
  }
};

const isSaving = computed(
  () => uiFlags.value.isCreating || uiFlags.value.isUpdating
);

// MT-19 — defesa em profundidade pra account-switch. Hoje o
// SidebarAccountSwitcher faz full reload (zera tudo via browser), mas se
// um dia migrar pra SPA navigation, esse watcher garante que regras de
// uma clínica não vazem visualmente pra outra.
watch(
  () => Number(route.params.accountId),
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      store.dispatch('aiAgentFollowUpRules/reset');
      store.dispatch('aiAgentFollowUpRules/fetch');
      // O picker de serviços também é por conta — sem isso, o modal de
      // reativação listaria os serviços da clínica anterior.
      loadAgendaServices();
    }
  }
);

onMounted(() => {
  store.dispatch('aiAgentFollowUpRules/fetch');
  loadAgendaServices();
});
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background overflow-hidden">
    <FollowUpsHeader
      :active-count="activeCount"
      :total-count="totalCount"
      @create="openCreate"
    />

    <!-- Conteúdo: full width, sem max-w-7xl. Padding generoso. -->
    <main class="flex-1 overflow-y-auto">
      <div class="px-8 py-8 w-full">
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
            {{ $t('AI_AGENT.FOLLOW_UPS.LOADING') }}
          </div>
        </div>

        <!-- Empty state -->
        <FollowUpsEmptyState
          v-else-if="records.length === 0"
          @create="openCreate"
        />

        <!-- Grid de cards: 1 col mobile, 2 col >= lg, 3 col >= 2xl. Full width. -->
        <div
          v-else
          class="grid gap-4 grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3"
        >
          <FollowUpRuleCard
            v-for="rule in records"
            :key="rule.id"
            :rule="rule"
            @edit="openEdit"
            @toggle="toggleEnabled"
            @delete="removeRule"
          />
        </div>
      </div>
    </main>

    <FollowUpFormModal
      v-model:show="showModal"
      :editing-id="editingId"
      :is-saving="isSaving"
      :form="form"
      :agenda-services="agendaServices"
      @save="save"
    />

    <!-- FE-7: confirmação de delete em modal styled (sem window.confirm). -->
    <ConfirmDangerModal
      v-model:show="confirmDeleteOpen"
      :title="$t('AI_AGENT.FOLLOW_UPS.DELETE_TITLE')"
      :message="
        confirmDeleteRule
          ? $t('AI_AGENT.FOLLOW_UPS.DELETE_MESSAGE', {
              name: confirmDeleteRule.name,
            })
          : ''
      "
      :confirm-label="$t('AI_AGENT.FOLLOW_UPS.DELETE_CONFIRM')"
      :loading="uiFlags.isDeleting"
      @confirm="handleConfirmDelete"
    />
  </div>
</template>
