<script setup>
import { ref, computed, onMounted, reactive, watch } from 'vue';
import { useStore } from 'vuex';

const store = useStore();

const records = computed(() => store.getters['aiAgentFollowUpRules/getRecords']);
const uiFlags = computed(() => store.getters['aiAgentFollowUpRules/getUIFlags']);

const showModal = ref(false);
const editingId = ref(null);

// SVG inline + cores INLINE STYLE — o JIT do Tailwind não pega classes
// vindas de `:class="opt.bg"` (string dinâmica), por isso `bg-sky-100`,
// `bg-emerald-100`, etc somem em build. Cores hex literais resolvem
// sem precisar de safelist no tailwind.config.
const TRIGGER_OPTIONS = [
  {
    value: 'pre_appointment',
    label: 'Antes da consulta',
    iconColor: '#0284c7', // sky-600
    bgColor: '#e0f2fe',   // sky-100
    helper: 'Dispara N horas antes do horário marcado. Ex: 24h antes pra confirmar; 2h antes como lembrete final.',
  },
  {
    value: 'post_appointment',
    label: 'Depois da consulta',
    iconColor: '#059669', // emerald-600
    bgColor: '#d1fae5',   // emerald-100
    helper: 'Dispara N horas após o horário marcado. Ex: 24h depois pra check-in pós-procedimento.',
  },
  {
    value: 'no_show',
    label: 'Paciente faltou',
    iconColor: '#d97706', // amber-600
    bgColor: '#fef3c7',   // amber-100
    helper: 'Dispara N horas após uma consulta marcada como falta. Útil pra oferecer reagendamento.',
  },
  {
    value: 'appointment_confirmed',
    label: 'Agendamento confirmado',
    iconColor: '#0891b2', // cyan-600
    bgColor: '#cffafe',   // cyan-100
    helper: 'Dispara assim que a clínica confirma uma reserva (status muda de "Aguardando confirmação" para "Agendado"). O offset não se aplica — envia na hora.',
  },
  {
    value: 'no_response',
    label: 'Sem resposta',
    iconColor: '#7c3aed', // violet-600
    bgColor: '#ede9fe',   // violet-100
    helper: 'Dispara quando o paciente parou de responder há N horas (última msg dele sem retorno).',
  },
  {
    value: 'custom',
    label: 'Customizado (manual)',
    iconColor: '#64748b', // slate-500
    bgColor: '#f1f5f9',   // slate-100
    helper: 'Não dispara por cron — só via API. Use pra integrações externas.',
  },
];

const triggerMeta = type =>
  TRIGGER_OPTIONS.find(o => o.value === type) || TRIGGER_OPTIONS[0];

const UNIT_OPTIONS = [
  { value: 'seconds', label: 'segundos', short: 's' },
  { value: 'minutes', label: 'minutos', short: 'min' },
  { value: 'hours', label: 'horas', short: 'h' },
];

const UNIT_LIMITS = {
  seconds: { min: 1, max: 14400 },
  minutes: { min: 1, max: 2880 },
  hours: { min: 1, max: 720 },
};

const APPLIES_TO_OPTIONS = [
  {
    value: 'both',
    label: 'Em qualquer agendamento',
    helper: 'Dispara independente de quem criou — recepção ou Bea.',
  },
  {
    value: 'ai_agent',
    label: 'Apenas se a Bea agendou',
    helper: 'Útil pra confirmar reservas que ainda dependem de validação humana.',
  },
  {
    value: 'manual',
    label: 'Apenas se um humano agendou',
    helper: 'Útil pra evitar conflito com automações já configuradas no agendamento manual da clínica.',
  },
];

const emptyForm = () => ({
  name: '',
  trigger_type: 'pre_appointment',
  offset_hours: 24,
  offset_unit: 'hours',
  applies_to: 'both',
  context_brief: '',
  max_per_target: 1,
  enabled: true,
});

const form = reactive(emptyForm());

const triggerHelper = computed(() => triggerMeta(form.trigger_type).helper);

const unitShort = computed(() => {
  return UNIT_OPTIONS.find(u => u.value === form.offset_unit)?.short || 'h';
});

const unitShortFor = unit =>
  UNIT_OPTIONS.find(u => u.value === unit)?.short || 'h';

// `applies_to` só faz sentido pra triggers que envolvem AgendaEvent.
// Em `no_response` e `custom` o filtro é ignorado pelo CandidateFinder,
// então escondemos o campo na UI pra evitar confusão.
const showAppliesTo = computed(() =>
  ['pre_appointment', 'post_appointment', 'no_show', 'appointment_confirmed'].includes(form.trigger_type)
);

// `appointment_confirmed` é event-driven (dispara no callback do
// AgendaEvent quando vira scheduled/confirmed). Não usa offset, então
// escondemos o campo "Quando disparar" pra esse trigger.
const showOffset = computed(() => form.trigger_type !== 'appointment_confirmed');

const appliesToLabelFor = value =>
  APPLIES_TO_OPTIONS.find(o => o.value === value)?.label || 'Em qualquer agendamento';

const appliesToBadgeFor = (rule) => {
  const v = rule.applies_to || 'both';
  if (v === 'ai_agent') return { text: 'Bea', color: '#7c3aed', bg: '#ede9fe' };
  if (v === 'manual')   return { text: 'Humano', color: '#0284c7', bg: '#e0f2fe' };
  return null; // 'both' não mostra badge — é o default
};

const unitLong = computed(() => {
  return UNIT_OPTIONS.find(u => u.value === form.offset_unit)?.label || 'horas';
});

// Avança a unidade em ciclo: segundos → minutos → horas → segundos.
// Quando troca de unidade, reposiciona o offset_hours dentro do range
// válido da nova unidade (clamp), pra não submeter inválido.
const cycleUnit = () => {
  const idx = UNIT_OPTIONS.findIndex(u => u.value === form.offset_unit);
  const next = UNIT_OPTIONS[(idx + 1) % UNIT_OPTIONS.length];
  form.offset_unit = next.value;
  const limits = UNIT_LIMITS[next.value];
  if (form.offset_hours < limits.min) form.offset_hours = limits.min;
  if (form.offset_hours > limits.max) form.offset_hours = limits.max;
};

const offsetLabel = computed(() => {
  const v = form.offset_hours;
  const u = unitShort.value;
  switch (form.trigger_type) {
    case 'pre_appointment':
      return `${v}${u} antes do horário marcado`;
    case 'post_appointment':
    case 'no_show':
      return `${v}${u} depois do evento`;
    case 'no_response':
      return `paciente parado há ${v}${u}`;
    case 'custom':
    default:
      return `${v}${u} (referência)`;
  }
});

// Cron roda a cada 1min, janela ±1min. Sem aviso de granularidade —
// qualquer offset >= 1s funciona razoavelmente bem.
const granularityWarning = computed(() => null);

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
    context_brief: rule.context_brief,
    max_per_target: rule.max_per_target,
    enabled: rule.enabled,
  });
  editingId.value = rule.id;
  showModal.value = true;
};

const closeModal = () => {
  showModal.value = false;
  editingId.value = null;
};

const save = async () => {
  const payload = {
    ...form,
    offset_hours: Number(form.offset_hours),
    max_per_target: Number(form.max_per_target),
  };
  try {
    if (editingId.value) {
      await store.dispatch('aiAgentFollowUpRules/update', { id: editingId.value, ...payload });
    } else {
      await store.dispatch('aiAgentFollowUpRules/create', payload);
    }
    closeModal();
  } catch (e) {
    /* throwErrorMessage já dispara toast */
  }
};

const toggleEnabled = async rule => {
  await store.dispatch('aiAgentFollowUpRules/update', { id: rule.id, enabled: !rule.enabled });
};

const removeRule = async rule => {
  if (!window.confirm(`Excluir o follow-up "${rule.name}"? Essa ação não pode ser desfeita.`)) return;
  await store.dispatch('aiAgentFollowUpRules/delete', rule.id);
};

const isSaving = computed(() => uiFlags.value.isCreating || uiFlags.value.isUpdating);

watch(showModal, val => {
  document.body.style.overflow = val ? 'hidden' : '';
});

onMounted(() => {
  store.dispatch('aiAgentFollowUpRules/fetch');
});
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background overflow-hidden">
    <!-- Header full-width REAL: sem max-w, sem mx-auto -->
    <header class="flex-shrink-0 px-8 py-6 border-b border-n-weak bg-n-solid-1">
      <div class="flex items-start justify-between gap-6">
        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-3 flex-wrap">
            <h1 class="text-2xl font-semibold text-n-slate-12 tracking-tight">
              Follow-ups
            </h1>
            <span
              v-if="totalCount > 0"
              class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium rounded-full bg-n-alpha-2 text-n-slate-11"
            >
              <span class="w-1.5 h-1.5 rounded-full bg-emerald-500" />
              {{ activeCount }} {{ activeCount === 1 ? 'ativa' : 'ativas' }}
              <span class="text-n-slate-9">·</span>
              {{ totalCount }} no total
            </span>
          </div>
          <p class="text-sm text-n-slate-11 mt-1.5 max-w-3xl leading-relaxed">
            Configure mensagens proativas que a Bea envia automaticamente —
            lembretes antes da consulta, check-in após o procedimento,
            reagendamento de quem faltou, ou retomada quando o paciente para
            de responder.
          </p>
        </div>
        <button
          type="button"
          class="shrink-0 inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-lg bg-woot-500 text-white hover:bg-woot-600 active:bg-woot-700 transition-colors shadow-sm"
          @click="openCreate"
        >
          <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>
          Novo follow-up
        </button>
      </div>
    </header>

    <!-- Conteúdo: full width, sem max-w-7xl. Padding generoso. -->
    <main class="flex-1 overflow-y-auto">
      <div class="px-8 py-8 w-full">
        <!-- Loading -->
        <div v-if="uiFlags.isFetching && records.length === 0" class="flex items-center justify-center py-20">
          <div class="flex items-center gap-3 text-sm text-n-slate-10">
            <svg class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round"/></svg>
            Carregando follow-ups…
          </div>
        </div>

        <!-- Empty state -->
        <div v-else-if="records.length === 0" class="flex flex-col items-center justify-center py-24 text-center">
          <div class="flex items-center justify-center w-20 h-20 rounded-2xl bg-n-alpha-2 text-n-slate-10 mb-5">
            <svg class="w-9 h-9" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="m3 11 18-5v12L3 14v-3z"/><path d="M11.6 16.8a3 3 0 1 1-5.8-1.6"/></svg>
          </div>
          <h3 class="text-lg font-semibold text-n-slate-12">Nenhum follow-up configurado</h3>
          <p class="text-sm text-n-slate-10 mt-1.5 mb-6 max-w-md">
            Crie sua primeira regra pra que a Bea acompanhe seus pacientes —
            confirme presença, ofereça reagendamento de faltas, retome conversas paradas.
          </p>
          <button
            type="button"
            class="inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-lg bg-woot-500 text-white hover:bg-woot-600 transition-colors shadow-sm"
            @click="openCreate"
          >
            <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>
            Criar primeiro follow-up
          </button>
        </div>

        <!-- Grid de cards: 1 col mobile, 2 col >= lg, 3 col >= 2xl. Full width. -->
        <div v-else class="grid gap-4 grid-cols-1 lg:grid-cols-2 2xl:grid-cols-3">
          <article
            v-for="rule in records"
            :key="rule.id"
            class="group relative bg-n-solid-1 border border-n-weak rounded-2xl p-5 hover:border-n-strong hover:shadow-md transition-all flex flex-col"
            :class="{ 'opacity-70': !rule.enabled }"
          >
            <!-- Top: ícone + título + status -->
            <div class="flex items-start justify-between gap-3 mb-3">
              <div class="flex items-start gap-3 min-w-0 flex-1">
                <div
                  class="shrink-0 flex items-center justify-center w-10 h-10 rounded-xl"
                  :style="{ backgroundColor: triggerMeta(rule.trigger_type).bgColor }"
                >
                  <!-- ícones SVG inline com cor inline (Tailwind JIT não pega classe vinda de variável) -->
                  <svg v-if="rule.trigger_type === 'pre_appointment'" class="w-5 h-5" :style="{ color: triggerMeta(rule.trigger_type).iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><circle cx="16" cy="16" r="3"/><path d="M16 14.5V16l1 1"/></svg>
                  <svg v-else-if="rule.trigger_type === 'post_appointment'" class="w-5 h-5" :style="{ color: triggerMeta(rule.trigger_type).iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="m9 16 2 2 4-4"/></svg>
                  <svg v-else-if="rule.trigger_type === 'no_show'" class="w-5 h-5" :style="{ color: triggerMeta(rule.trigger_type).iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="m14 14-4 4M10 14l4 4"/></svg>
                  <svg v-else-if="rule.trigger_type === 'no_response'" class="w-5 h-5" :style="{ color: triggerMeta(rule.trigger_type).iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12c0 4.97-4.03 9-9 9-1.5 0-2.91-.37-4.15-1.02L3 21l1.02-4.85A8.96 8.96 0 0 1 3 12c0-4.97 4.03-9 9-9s9 4.03 9 9z"/><path d="M2 2l20 20"/></svg>
                  <svg v-else-if="rule.trigger_type === 'appointment_confirmed'" class="w-5 h-5" :style="{ color: triggerMeta(rule.trigger_type).iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                  <svg v-else class="w-5 h-5" :style="{ color: triggerMeta(rule.trigger_type).iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
                </div>
                <div class="min-w-0 flex-1">
                  <h3 class="text-base font-semibold text-n-slate-12 truncate leading-tight">{{ rule.name }}</h3>
                  <p class="text-xs text-n-slate-10 mt-0.5 font-medium uppercase tracking-wide">{{ triggerMeta(rule.trigger_type).label }}</p>
                </div>
              </div>
              <span
                class="shrink-0 inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium rounded-md"
                :class="rule.enabled ? 'bg-emerald-100 text-emerald-700' : 'bg-n-alpha-2 text-n-slate-10'"
              >
                <span class="w-1.5 h-1.5 rounded-full" :class="rule.enabled ? 'bg-emerald-500' : 'bg-n-slate-9'" />
                {{ rule.enabled ? 'Ativo' : 'Pausado' }}
              </span>
            </div>

            <!-- Context preview -->
            <p class="text-sm text-n-slate-11 leading-relaxed line-clamp-2 mb-4 min-h-[2.6em] flex-1">
              {{ rule.context_brief }}
            </p>

            <!-- Stats pills -->
            <div class="flex flex-wrap items-center gap-2 mb-4">
              <span
                v-if="rule.trigger_type === 'appointment_confirmed'"
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z"/></svg>
                Imediato
              </span>
              <span
                v-else
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 6v6l4 2"/></svg>
                {{ rule.offset_hours }}{{ unitShortFor(rule.offset_unit) }}
              </span>
              <span class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11">
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="m17 2 4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/><path d="m7 22-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/></svg>
                máx {{ rule.max_per_target === 0 ? 'ilimitado' : rule.max_per_target }} por alvo
              </span>
              <span
                v-if="appliesToBadgeFor(rule)"
                class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md font-medium"
                :style="{ color: appliesToBadgeFor(rule).color, backgroundColor: appliesToBadgeFor(rule).bg }"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
                Só {{ appliesToBadgeFor(rule).text }}
              </span>
            </div>

            <!-- Actions -->
            <div class="flex items-center gap-1 -mx-1.5 -mb-1.5 pt-3 border-t border-n-weak mt-auto">
              <button
                type="button"
                class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                @click="toggleEnabled(rule)"
              >
                <svg v-if="rule.enabled" class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="6" y="4" width="4" height="16" rx="1"/><rect x="14" y="4" width="4" height="16" rx="1"/></svg>
                <svg v-else class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="6 3 20 12 6 21 6 3"/></svg>
                {{ rule.enabled ? 'Pausar' : 'Ativar' }}
              </button>
              <button
                type="button"
                class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                @click="openEdit(rule)"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"/></svg>
                Editar
              </button>
              <button
                type="button"
                class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-ruby-600 hover:bg-ruby-100 rounded-lg transition-colors"
                @click="removeRule(rule)"
              >
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
                Excluir
              </button>
            </div>
          </article>
        </div>
      </div>
    </main>

    <!-- Modal create/edit -->
    <Teleport to="body">
      <Transition name="modal">
        <div
          v-if="showModal"
          class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
          @click.self="closeModal"
        >
          <div
            class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-3xl max-h-[92vh] flex flex-col overflow-hidden"
            @click.stop
          >
            <!-- Header -->
            <header class="flex-shrink-0 px-7 py-5 border-b border-n-weak flex items-start justify-between gap-4">
              <div class="min-w-0">
                <h2 class="text-lg font-semibold text-n-slate-12 leading-tight">
                  {{ editingId ? 'Editar follow-up' : 'Novo follow-up' }}
                </h2>
                <p class="text-xs text-n-slate-10 mt-1">
                  {{ editingId ? 'Ajuste os parâmetros e salve.' : 'Defina quando e como a Bea entra em contato.' }}
                </p>
              </div>
              <button
                type="button"
                class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
                @click="closeModal"
              >
                <svg class="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M18 6 6 18M6 6l12 12"/></svg>
              </button>
            </header>

            <!-- Body -->
            <form class="flex-1 overflow-y-auto px-7 py-6 space-y-6" @submit.prevent="save">
              <!-- Nome -->
              <div>
                <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">Nome</label>
                <input
                  v-model="form.name"
                  type="text"
                  required
                  maxlength="120"
                  placeholder="Ex: Lembrete 24h antes da consulta"
                  class="w-full h-11 px-3.5 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                >
              </div>

              <!-- Trigger type: grid 2 colunas, cards uniformes -->
              <div>
                <label class="block text-sm font-semibold text-n-slate-12 mb-2">Tipo de gatilho</label>
                <div class="grid grid-cols-2 gap-2.5">
                  <button
                    v-for="opt in TRIGGER_OPTIONS"
                    :key="opt.value"
                    type="button"
                    class="relative flex items-center gap-3 px-3.5 py-3 text-left rounded-lg border-2 transition-all"
                    :class="form.trigger_type === opt.value
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'"
                    @click="form.trigger_type = opt.value"
                  >
                    <div
                      class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg"
                      :style="{ backgroundColor: opt.bgColor }"
                    >
                      <svg v-if="opt.value === 'pre_appointment'" class="w-[18px] h-[18px]" :style="{ color: opt.iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><circle cx="16" cy="16" r="3"/><path d="M16 14.5V16l1 1"/></svg>
                      <svg v-else-if="opt.value === 'post_appointment'" class="w-[18px] h-[18px]" :style="{ color: opt.iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="m9 16 2 2 4-4"/></svg>
                      <svg v-else-if="opt.value === 'no_show'" class="w-[18px] h-[18px]" :style="{ color: opt.iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/><path d="m14 14-4 4M10 14l4 4"/></svg>
                      <svg v-else-if="opt.value === 'no_response'" class="w-[18px] h-[18px]" :style="{ color: opt.iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12c0 4.97-4.03 9-9 9-1.5 0-2.91-.37-4.15-1.02L3 21l1.02-4.85A8.96 8.96 0 0 1 3 12c0-4.97 4.03-9 9-9s9 4.03 9 9z"/><path d="M2 2l20 20"/></svg>
                      <svg v-else-if="opt.value === 'appointment_confirmed'" class="w-[18px] h-[18px]" :style="{ color: opt.iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><path d="m9 11 3 3L22 4"/></svg>
                      <svg v-else class="w-[18px] h-[18px]" :style="{ color: opt.iconColor }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
                    </div>
                    <span class="text-sm font-medium text-n-slate-12 leading-tight flex-1 min-w-0">{{ opt.label }}</span>
                    <svg
                      v-if="form.trigger_type === opt.value"
                      class="shrink-0 w-4 h-4 text-woot-500"
                      viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"
                    >
                      <path d="M20 6 9 17l-5-5"/>
                    </svg>
                  </button>
                </div>
                <p class="text-xs text-n-slate-10 mt-2.5 leading-relaxed">{{ triggerHelper }}</p>
              </div>

              <!-- Aplicar quando — só pra triggers de agenda. Filtra por origem
                   do AgendaEvent (Bea / humano / ambos). -->
              <div v-if="showAppliesTo">
                <label class="block text-sm font-semibold text-n-slate-12 mb-2">Aplicar quando</label>
                <div class="space-y-2">
                  <label
                    v-for="opt in APPLIES_TO_OPTIONS"
                    :key="opt.value"
                    class="flex items-start gap-3 p-3 rounded-lg border-2 cursor-pointer transition-all"
                    :class="form.applies_to === opt.value
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'"
                  >
                    <input
                      v-model="form.applies_to"
                      type="radio"
                      :value="opt.value"
                      class="mt-0.5 shrink-0"
                    >
                    <div class="min-w-0">
                      <div class="text-sm font-medium text-n-slate-12 leading-tight">{{ opt.label }}</div>
                      <div class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">{{ opt.helper }}</div>
                    </div>
                  </label>
                </div>
              </div>

              <!-- Quando disparar: mesmo padrão do "Limite por paciente" — input
                   com sufixo de unidade clicável que cicla entre segundos/minutos/horas.
                   Escondido pra `appointment_confirmed` (event-driven, dispara na hora). -->
              <div v-if="showOffset">
                <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">Quando disparar</label>
                <div class="relative w-40">
                  <input
                    v-model.number="form.offset_hours"
                    type="number"
                    :min="UNIT_LIMITS[form.offset_unit].min"
                    :max="UNIT_LIMITS[form.offset_unit].max"
                    required
                    class="w-full h-11 pl-3.5 pr-20 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                  >
                  <button
                    type="button"
                    class="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 hover:text-n-slate-12 cursor-pointer select-none border-0 bg-transparent p-0 transition-colors"
                    :title="`Trocar unidade — ${unitLong}, clique pra avançar`"
                    @click="cycleUnit"
                  >
                    {{ unitLong }}
                  </button>
                </div>
                <p class="text-xs text-n-slate-10 mt-2 leading-relaxed">
                  <span class="font-medium text-n-slate-11">{{ offsetLabel }}</span>
                  <span class="text-n-slate-9"> · clique em "{{ unitLong }}" pra trocar a unidade</span>
                </p>
                <p
                  v-if="granularityWarning"
                  class="text-xs mt-1.5 flex items-start gap-1.5 leading-relaxed"
                  style="color: #b45309"
                >
                  <svg class="w-3.5 h-3.5 mt-0.5 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4M12 17h.01"/><path d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/></svg>
                  {{ granularityWarning }}
                </p>
              </div>

              <!-- Cenário -->
              <div>
                <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">Cenário (instrução pra Bea)</label>
                <textarea
                  v-model="form.context_brief"
                  required
                  rows="8"
                  maxlength="4000"
                  placeholder="Ex: Lembrar o paciente da consulta amanhã, perguntar se ainda confirma a presença e oferecer remarcar se não puder vir."
                  class="w-full min-h-[180px] px-3.5 py-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed"
                />
                <p class="text-xs text-n-slate-10 mt-1.5 leading-relaxed flex items-start gap-1.5">
                  <svg class="w-3.5 h-3.5 mt-0.5 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><path d="M12 16v-4M12 8h.01"/></svg>
                  A Bea usa esse texto como contexto pra escrever a mensagem em PT-BR. Quanto mais claro o objetivo, melhor a saída.
                </p>
              </div>

              <!-- Limite -->
              <div>
                <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">Limite por paciente/consulta</label>
                <div class="relative w-40">
                  <input
                    v-model.number="form.max_per_target"
                    type="number"
                    min="0"
                    max="100"
                    class="w-full h-11 pl-3.5 pr-20 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                  >
                  <span class="absolute right-3.5 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 pointer-events-none select-none">
                    {{ form.max_per_target === 1 ? 'envio' : 'envios' }}
                  </span>
                </div>
                <p class="text-xs text-n-slate-10 mt-2 leading-relaxed">
                  <template v-if="form.max_per_target === 0">
                    <span class="font-medium" style="color: #b45309">Sem limite</span> — cuidado com flood. A Bea pode mandar várias mensagens pra mesma consulta.
                  </template>
                  <template v-else-if="form.max_per_target === 1">
                    A Bea manda no máximo <span class="font-medium text-n-slate-11">1 mensagem</span> por consulta/paciente.
                  </template>
                  <template v-else>
                    A Bea manda no máximo <span class="font-medium text-n-slate-11">{{ form.max_per_target }} mensagens</span> por consulta/paciente.
                  </template>
                </p>
              </div>

              <!-- Toggle ativo: container alinhado, switch dentro do contêiner -->
              <div class="flex items-center justify-between gap-4 px-4 py-3.5 rounded-lg bg-n-alpha-1 border border-n-weak">
                <div class="min-w-0 pr-2">
                  <div class="text-sm font-semibold text-n-slate-12 leading-tight">Regra ativa</div>
                  <div class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                    Quando desativada, a Bea não dispara essa regra mas o histórico fica preservado.
                  </div>
                </div>
                <button
                  type="button"
                  role="switch"
                  :aria-checked="form.enabled"
                  class="relative shrink-0 inline-flex h-6 w-11 flex-none items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-woot-500/30 focus:ring-offset-2 focus:ring-offset-n-solid-1 p-0 border-0"
                  :class="form.enabled ? 'bg-woot-500' : 'bg-n-slate-6'"
                  @click="form.enabled = !form.enabled"
                >
                  <span
                    class="absolute left-0.5 inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform"
                    :class="form.enabled ? 'translate-x-5' : 'translate-x-0'"
                  />
                </button>
              </div>
            </form>

            <!-- Footer -->
            <footer class="flex-shrink-0 px-7 py-4 border-t border-n-weak flex items-center justify-end gap-3 bg-n-alpha-1">
              <button
                type="button"
                class="px-4 py-2.5 text-sm font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
                @click="closeModal"
              >
                Cancelar
              </button>
              <button
                type="button"
                :disabled="isSaving || !form.name || !form.context_brief"
                class="inline-flex items-center gap-2 px-4 py-2.5 text-sm font-medium rounded-lg bg-woot-500 text-white hover:bg-woot-600 disabled:opacity-50 disabled:cursor-not-allowed transition-colors shadow-sm"
                @click="save"
              >
                <svg v-if="isSaving" class="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round"/></svg>
                {{ editingId ? 'Salvar alterações' : 'Criar follow-up' }}
              </button>
            </footer>
          </div>
        </div>
      </Transition>
    </Teleport>
  </div>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.2s ease;
}
.modal-enter-active > div,
.modal-leave-active > div {
  transition: transform 0.24s cubic-bezier(0.16, 1, 0.3, 1), opacity 0.2s ease;
}
.modal-enter-from,
.modal-leave-to {
  opacity: 0;
}
.modal-enter-from > div,
.modal-leave-to > div {
  opacity: 0;
  transform: translateY(8px) scale(0.98);
}

/* Esconde spin buttons dos number inputs (estilo + consistência) */
input[type='number']::-webkit-outer-spin-button,
input[type='number']::-webkit-inner-spin-button {
  -webkit-appearance: none;
  margin: 0;
}
input[type='number'] {
  -moz-appearance: textfield;
}

</style>
