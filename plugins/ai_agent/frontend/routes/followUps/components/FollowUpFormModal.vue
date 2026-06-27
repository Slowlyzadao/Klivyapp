<script setup>
// FE-3 (auditoria 2026-05-18): extraído do Index.vue (702 LOC).
// Modal de criação/edição de regra de follow-up. Recebe o objeto `form`
// (reactive do pai) — mutações se propagam via Vue 3 reactivity. Constants
// duplicadas inline por design (extração mecânica, sem novas abstrações).
// FE-16/17 (i18n 2026-05-19): strings migradas para `AI_AGENT.FOLLOW_UPS.*`.
import { ref, computed, watch, onUnmounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  editingId: { type: [Number, String], default: null },
  isSaving: { type: Boolean, default: false },
  // `form` é um objeto reactive() criado no pai. Vue 3 preserva a
  // reatividade através de props quando o objeto é reactive — mutar
  // `form.name = '...'` aqui dispara watchers no pai.
  form: { type: Object, required: true },
  // Fase 6: serviços do agenda pro picker de reativação (read-only).
  agendaServices: { type: Array, default: () => [] },
});

const emit = defineEmits(['update:show', 'save']);

const { t } = useI18n();

const TRIGGER_OPTIONS = computed(() => [
  {
    value: 'pre_appointment',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.PRE_APPOINTMENT_LABEL'),
    iconColor: '#0284c7',
    bgColor: '#e0f2fe',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.PRE_APPOINTMENT_HELPER'),
  },
  {
    value: 'post_appointment',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.POST_APPOINTMENT_LABEL'),
    iconColor: '#059669',
    bgColor: '#d1fae5',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.POST_APPOINTMENT_HELPER'),
  },
  {
    value: 'no_show',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.NO_SHOW_LABEL'),
    iconColor: '#d97706',
    bgColor: '#fef3c7',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.NO_SHOW_HELPER'),
  },
  {
    value: 'appointment_confirmed',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.APPOINTMENT_CONFIRMED_LABEL'),
    iconColor: '#0891b2',
    bgColor: '#cffafe',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.APPOINTMENT_CONFIRMED_HELPER'),
  },
  {
    value: 'no_response',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.NO_RESPONSE_LABEL'),
    iconColor: '#7c3aed',
    bgColor: '#ede9fe',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.NO_RESPONSE_HELPER'),
  },
  {
    value: 'service_recall',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.SERVICE_RECALL_LABEL'),
    iconColor: '#db2777',
    bgColor: '#fce7f3',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.SERVICE_RECALL_HELPER'),
  },
  {
    value: 'custom',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.CUSTOM_LABEL'),
    iconColor: '#64748b',
    bgColor: '#f1f5f9',
    helper: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.CUSTOM_HELPER'),
  },
]);

const triggerMeta = type =>
  TRIGGER_OPTIONS.value.find(o => o.value === type) || TRIGGER_OPTIONS.value[0];

const UNIT_OPTIONS = computed(() => [
  {
    value: 'seconds',
    label: t('AI_AGENT.FOLLOW_UPS.UNITS.SECONDS_LONG'),
    short: t('AI_AGENT.FOLLOW_UPS.UNITS.SECONDS_SHORT'),
  },
  {
    value: 'minutes',
    label: t('AI_AGENT.FOLLOW_UPS.UNITS.MINUTES_LONG'),
    short: t('AI_AGENT.FOLLOW_UPS.UNITS.MINUTES_SHORT'),
  },
  {
    value: 'hours',
    label: t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_LONG'),
    short: t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_SHORT'),
  },
]);

const UNIT_LIMITS = {
  seconds: { min: 1, max: 14400 },
  minutes: { min: 1, max: 2880 },
  hours: { min: 1, max: 720 },
};

// Reativação por serviço: unidades do intervalo, tetos espelhando
// RECALL_INTERVAL_LIMITS do model. minutes/hours servem sobretudo pra
// testar a reativação sem esperar dias (o cron roda a cada 1 min).
const RECALL_UNIT_LIMITS = {
  minutes: { min: 1, max: 43200 },
  hours: { min: 1, max: 8760 },
  days: { min: 1, max: 365 },
  weeks: { min: 1, max: 52 },
  months: { min: 1, max: 36 },
  years: { min: 1, max: 10 },
};
const RECALL_UNIT_OPTIONS = computed(() => [
  { value: 'minutes', label: t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_MINUTES') },
  { value: 'hours', label: t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_HOURS') },
  { value: 'days', label: t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_DAYS') },
  { value: 'weeks', label: t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_WEEKS') },
  { value: 'months', label: t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_MONTHS') },
  { value: 'years', label: t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_YEARS') },
]);

const APPLIES_TO_OPTIONS = computed(() => [
  {
    value: 'both',
    label: t('AI_AGENT.FOLLOW_UPS.APPLIES_TO.BOTH_LABEL'),
    helper: t('AI_AGENT.FOLLOW_UPS.APPLIES_TO.BOTH_HELPER'),
  },
  {
    value: 'ai_agent',
    label: t('AI_AGENT.FOLLOW_UPS.APPLIES_TO.AI_AGENT_LABEL'),
    helper: t('AI_AGENT.FOLLOW_UPS.APPLIES_TO.AI_AGENT_HELPER'),
  },
  {
    value: 'manual',
    label: t('AI_AGENT.FOLLOW_UPS.APPLIES_TO.MANUAL_LABEL'),
    helper: t('AI_AGENT.FOLLOW_UPS.APPLIES_TO.MANUAL_HELPER'),
  },
]);

// Cadência só faz sentido nos gatilhos cron — os event-driven
// (appointment_confirmed) e custom não iteram passos no CandidateFinder.
const CADENCE_TRIGGERS = [
  'pre_appointment',
  'post_appointment',
  'no_show',
  'no_response',
];
const showCadence = computed(() =>
  CADENCE_TRIGGERS.includes(props.form.trigger_type)
);

// Reativação por serviço (Fase 6): single-shot, baseada no intervalo do
// serviço — esconde offset/cadência e mostra o picker de serviço.
const isServiceRecall = computed(
  () => props.form.trigger_type === 'service_recall'
);

// Cenário PRÉ-PREENCHIDO por gatilho: o campo nasce com um cenário pronto
// e o usuário só ajusta (ou apaga e escreve o dele). Ao trocar de gatilho,
// substituímos apenas se o texto atual está vazio ou ainda é um dos
// defaults (intocado) — texto editado pelo usuário NUNCA é sobrescrito.
const DEFAULT_BRIEFS = computed(() => ({
  pre_appointment: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.PRE_APPOINTMENT'),
  post_appointment: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.POST_APPOINTMENT'),
  no_show: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.NO_SHOW'),
  appointment_confirmed: t(
    'AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.APPOINTMENT_CONFIRMED'
  ),
  no_response: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.NO_RESPONSE'),
  service_recall: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.SERVICE_RECALL'),
  custom: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.CUSTOM'),
}));

const briefUntouched = () => {
  const v = (props.form.context_brief || '').trim();
  return v === '' || Object.values(DEFAULT_BRIEFS.value).includes(v);
};

watch(
  () => [props.show, props.form.trigger_type],
  ([shown]) => {
    if (!shown) return;
    if (briefUntouched()) {
      props.form.context_brief =
        DEFAULT_BRIEFS.value[props.form.trigger_type] || '';
    }
  }
);

// Unidade do intervalo de reativação: mesmo padrão do offset (sufixo
// clicável que cicla dias → semanas → meses, com clamp no teto da unidade).
const recallUnitLong = computed(
  () =>
    RECALL_UNIT_OPTIONS.value.find(
      u => u.value === props.form.recall_interval_unit
    )?.label || t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_MONTHS')
);
const cycleRecallUnit = () => {
  const opts = RECALL_UNIT_OPTIONS.value;
  const idx = opts.findIndex(u => u.value === props.form.recall_interval_unit);
  const next = opts[(idx + 1) % opts.length];
  props.form.recall_interval_unit = next.value;
  const limits = RECALL_UNIT_LIMITS[next.value];
  if (props.form.recall_interval_value < limits.min)
    props.form.recall_interval_value = limits.min;
  if (props.form.recall_interval_value > limits.max)
    props.form.recall_interval_value = limits.max;
};

// Opções do FormSelect de serviço — hint mostra a duração quando existir.
const serviceOptions = computed(() =>
  (props.agendaServices || []).map(s => ({
    value: s.id,
    label: s.name,
    hint: s.duration_minutes
      ? t('AI_AGENT.FOLLOW_UPS.SERVICE.DURATION_HINT', {
          minutes: s.duration_minutes,
        })
      : undefined,
  }))
);

// `stop_on_booking` só aparece onde (re)agendar é o objetivo (não em
// pre_appointment, que já lembra de uma consulta existente).
const showStopBooking = computed(() =>
  ['post_appointment', 'no_show', 'no_response'].includes(
    props.form.trigger_type
  )
);
// `stop_on_reply` vale pra qualquer cadência. A seção aparece se ao menos
// uma das condições for aplicável ao gatilho.
const showStopConditions = computed(
  () => showCadence.value || showStopBooking.value
);

// Passos ADICIONAIS (2..N). O passo 1 são os campos "Quando disparar" +
// "Cenário" acima. Cada item extra: { offset_hours, offset_unit, context_brief }.
const steps = computed(() =>
  Array.isArray(props.form.steps) ? props.form.steps : []
);

// Offset efetivo em segundos — mesma régua do backend (que rejeita
// offsets efetivos duplicados na sequência via distinct_step_offsets).
const SECONDS_PER_UNIT = { seconds: 1, minutes: 60, hours: 3600 };
const effectiveSeconds = (hours, unit) =>
  Number(hours || 0) * (SECONDS_PER_UNIT[unit] || 3600);

const addStep = () => {
  if (!Array.isArray(props.form.steps)) props.form.steps = [];
  // Passo novo nasce com o DOBRO do maior offset da sequência (base +
  // passos) — um default fixo de 24h colidia com o base default (24h) e
  // garantia 422 no caminho feliz da cadência.
  const used = [
    effectiveSeconds(props.form.offset_hours, props.form.offset_unit),
    ...props.form.steps.map(s =>
      effectiveSeconds(s.offset_hours, s.offset_unit)
    ),
  ];
  let next = Math.max(1, Math.ceil((Math.max(...used) * 2) / 3600));
  while (used.includes(next * 3600) && next < 720) next += 1;
  props.form.steps.push({
    offset_hours: Math.min(720, next),
    offset_unit: 'hours',
    // Passo novo já nasce com um cenário de reforço pronto (o usuário ajusta).
    context_brief: t('AI_AGENT.FOLLOW_UPS.DEFAULT_BRIEFS.STEP'),
    static_body: '',
  });
};
const removeStep = idx => props.form.steps.splice(idx, 1);

// Modo de ação: 'generative' (Bea escreve) | 'static' (mensagem fixa).
const isStatic = computed(() => props.form.action_type === 'static');

// Variáveis disponíveis pra mensagem estática. Chips clicáveis inserem
// o token no fim do campo correspondente (passo 1 ou um passo extra).
const STATIC_VARIABLES = ['nome', 'data', 'hora', 'profissional', 'clinica'];

// Anexa `{{key}}` ao `static_body` do alvo (a regra ou um passo).
const insertVar = (target, key) => {
  target.static_body = `${target.static_body || ''}{{${key}}}`;
};

// Rótulo do chip. Computado em JS porque escrever `{{ '{{'+key+'}}' }}`
// direto no template quebra o parser do Vue (o `}}` literal fecha o
// mustache). Aqui o retorno é renderizado como texto, sem reparse.
const varToken = key => `{{${key}}}`;

// Fallback de template (Fase 4). Variáveis ordenadas que preenchem
// {{1}}, {{2}}... do template aprovado, na ordem da lista.
const templateParams = computed(() =>
  Array.isArray(props.form.cloud_template_params)
    ? props.form.cloud_template_params
    : []
);
const addTemplateParam = () => {
  if (!Array.isArray(props.form.cloud_template_params)) {
    props.form.cloud_template_params = [];
  }
  props.form.cloud_template_params.push('nome');
};
const removeTemplateParam = idx =>
  props.form.cloud_template_params.splice(idx, 1);

const stepUnitLong = step =>
  UNIT_OPTIONS.value.find(u => u.value === step.offset_unit)?.label ||
  t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_LONG');

// Mesmo ciclo de unidade do offset principal, aplicado a um passo.
const cycleStepUnit = step => {
  const opts = UNIT_OPTIONS.value;
  const idx = opts.findIndex(u => u.value === step.offset_unit);
  const next = opts[(idx + 1) % opts.length];
  step.offset_unit = next.value;
  const limits = UNIT_LIMITS[next.value];
  if (step.offset_hours < limits.min) step.offset_hours = limits.min;
  if (step.offset_hours > limits.max) step.offset_hours = limits.max;
};

const triggerHelper = computed(
  () => triggerMeta(props.form.trigger_type).helper
);

const unitShort = computed(() => {
  return (
    UNIT_OPTIONS.value.find(u => u.value === props.form.offset_unit)?.short ||
    t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_SHORT')
  );
});

// `applies_to` só faz sentido pra triggers que envolvem AgendaEvent.
// Em `no_response` e `custom` o filtro é ignorado pelo CandidateFinder,
// então escondemos o campo na UI pra evitar confusão.
const showAppliesTo = computed(() =>
  [
    'pre_appointment',
    'post_appointment',
    'no_show',
    'appointment_confirmed',
  ].includes(props.form.trigger_type)
);

// `appointment_confirmed` é event-driven (dispara no callback do
// AgendaEvent quando vira scheduled/confirmed). Não usa offset, então
// escondemos o campo "Quando disparar" pra esse trigger.
const showOffset = computed(
  () =>
    !['appointment_confirmed', 'service_recall'].includes(
      props.form.trigger_type
    )
);

const unitLong = computed(() => {
  return (
    UNIT_OPTIONS.value.find(u => u.value === props.form.offset_unit)?.label ||
    t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_LONG')
  );
});

// Avança a unidade em ciclo: segundos → minutos → horas → segundos.
// Quando troca de unidade, reposiciona o offset_hours dentro do range
// válido da nova unidade (clamp), pra não submeter inválido.
const cycleUnit = () => {
  const opts = UNIT_OPTIONS.value;
  const idx = opts.findIndex(u => u.value === props.form.offset_unit);
  const next = opts[(idx + 1) % opts.length];
  props.form.offset_unit = next.value;
  const limits = UNIT_LIMITS[next.value];
  if (props.form.offset_hours < limits.min)
    props.form.offset_hours = limits.min;
  if (props.form.offset_hours > limits.max)
    props.form.offset_hours = limits.max;
};

const offsetLabel = computed(() => {
  const v = props.form.offset_hours;
  const u = unitShort.value;
  switch (props.form.trigger_type) {
    case 'pre_appointment':
      return t('AI_AGENT.FOLLOW_UPS.FORM.OFFSET_PRE', { value: v, unit: u });
    case 'post_appointment':
    case 'no_show':
      return t('AI_AGENT.FOLLOW_UPS.FORM.OFFSET_POST', { value: v, unit: u });
    case 'no_response':
      return t('AI_AGENT.FOLLOW_UPS.FORM.OFFSET_NO_RESPONSE', {
        value: v,
        unit: u,
      });
    case 'custom':
    default:
      return t('AI_AGENT.FOLLOW_UPS.FORM.OFFSET_CUSTOM', { value: v, unit: u });
  }
});

// Cron roda a cada 1min, janela ±1min. Sem aviso de granularidade —
// qualquer offset >= 1s funciona razoavelmente bem.
const granularityWarning = computed(() => null);

// Corpo obrigatório do passo conforme o modo: estático exige a mensagem
// fixa, generativo exige o cenário.
const stepBodyMissing = s =>
  isStatic.value ? !s.static_body : !s.context_brief;

// Bloqueia salvar enquanto algum passo extra estiver incompleto
// (corpo vazio ou offset zerado) — espelha as validações do model.
const hasInvalidStep = computed(
  () =>
    showCadence.value &&
    steps.value.some(s => stepBodyMissing(s) || !Number(s.offset_hours))
);

// Corpo do passo 1 (a própria regra) obrigatório conforme o modo.
const primaryBodyMissing = computed(() =>
  isStatic.value ? !props.form.static_body : !props.form.context_brief
);

// O que ainda falta pra salvar — na ordem em que aparece no formulário.
// Mostrado em TOAST só quando o usuário clica em salvar com pendência
// (decisão do Leandro: nada de aviso permanente no rodapé). O botão não
// desabilita por campo faltando: desabilitado-sem-explicação deixava o
// usuário travado sem saber o que preencher.
const missingMessage = computed(() => {
  const K = 'AI_AGENT.FOLLOW_UPS.FORM';
  if (!props.form.name) return t(`${K}.MISSING_NAME`);
  if (showOffset.value && !Number(props.form.offset_hours))
    return t(`${K}.MISSING_OFFSET`);
  if (isServiceRecall.value && !props.form.agenda_service_id)
    return t(`${K}.MISSING_SERVICE`);
  if (isServiceRecall.value && !Number(props.form.recall_interval_value))
    return t(`${K}.MISSING_INTERVAL`);
  if (primaryBodyMissing.value)
    return t(isStatic.value ? `${K}.MISSING_STATIC` : `${K}.MISSING_BRIEF`);
  if (hasInvalidStep.value) return t(`${K}.MISSING_STEP`);
  return null;
});

const closeModal = () => emit('update:show', false);

// Só fecha ao clicar no FUNDO quando o gesto INTEIRO (pressionar + soltar)
// aconteceu no overlay. Sem isso, selecionar texto arrastando o mouse de
// dentro do modal pra fora disparava um `click` no overlay e fechava sem
// querer (o `click` nasce no ancestral comum do mousedown+mouseup).
const pressedOnOverlay = ref(false);
const onOverlayMousedown = e => {
  pressedOnOverlay.value = e.target === e.currentTarget;
};
const onOverlayMouseup = e => {
  if (pressedOnOverlay.value && e.target === e.currentTarget) closeModal();
  pressedOnOverlay.value = false;
};
const onSave = () => {
  if (props.isSaving) return;
  if (missingMessage.value) {
    useAlert(missingMessage.value);
    return;
  }
  emit('save');
};

// Lock do scroll do body quando modal abre — preserva comportamento original.
watch(
  () => props.show,
  val => {
    document.body.style.overflow = val ? 'hidden' : '';
  }
);

// Se o componente desmontar com o modal aberto (navegação/back), o lock
// ficaria pra sempre e o app inteiro pararia de rolar até um reload.
onUnmounted(() => {
  document.body.style.overflow = '';
});
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="show"
        class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
        @mousedown="onOverlayMousedown"
        @mouseup="onOverlayMouseup"
      >
        <div
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-3xl max-h-[92vh] flex flex-col overflow-hidden"
        >
          <!-- Header -->
          <header
            class="flex-shrink-0 px-7 py-5 border-b border-n-weak flex items-start justify-between gap-4"
          >
            <div class="min-w-0">
              <h2 class="text-lg font-semibold text-n-slate-12 leading-tight">
                {{
                  editingId
                    ? $t('AI_AGENT.FOLLOW_UPS.FORM.TITLE_EDIT')
                    : $t('AI_AGENT.FOLLOW_UPS.FORM.TITLE_NEW')
                }}
              </h2>
              <p class="text-xs text-n-slate-10 mt-1">
                {{
                  editingId
                    ? $t('AI_AGENT.FOLLOW_UPS.FORM.SUBTITLE_EDIT')
                    : $t('AI_AGENT.FOLLOW_UPS.FORM.SUBTITLE_NEW')
                }}
              </p>
            </div>
            <button
              type="button"
              class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12 transition-colors"
              @click="closeModal"
            >
              <svg
                class="w-5 h-5"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <path d="M18 6 6 18M6 6l12 12" />
              </svg>
            </button>
          </header>

          <!-- Body -->
          <form
            class="flex-1 overflow-y-auto px-7 py-6 space-y-6"
            @submit.prevent="onSave"
          >
            <!-- Nome -->
            <div>
              <label
                class="block text-sm font-semibold text-n-slate-12 mb-1.5"
                >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.NAME_LABEL') }}</label>
              <input
                v-model="form.name"
                type="text"
                required
                maxlength="120"
                :placeholder="$t('AI_AGENT.FOLLOW_UPS.FORM.NAME_PLACEHOLDER')"
                class="w-full h-11 px-3.5 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
              />
            </div>

            <!-- Trigger type: grid 2 colunas, cards uniformes -->
            <div>
              <label class="block text-sm font-semibold text-n-slate-12 mb-2">{{
                $t('AI_AGENT.FOLLOW_UPS.FORM.TRIGGER_LABEL')
              }}</label>
              <div class="grid grid-cols-2 gap-2.5">
                <button
                  v-for="opt in TRIGGER_OPTIONS"
                  :key="opt.value"
                  type="button"
                  class="relative flex items-center gap-3 px-3.5 py-3 text-left rounded-lg border-2 transition-all"
                  :class="
                    form.trigger_type === opt.value
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'
                  "
                  @click="form.trigger_type = opt.value"
                >
                  <div
                    class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg"
                    :style="{ backgroundColor: opt.bgColor }"
                  >
                    <svg
                      v-if="opt.value === 'pre_appointment'"
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <rect x="3" y="4" width="18" height="18" rx="2" />
                      <path d="M16 2v4M8 2v4M3 10h18" />
                      <circle cx="16" cy="16" r="3" />
                      <path d="M16 14.5V16l1 1" />
                    </svg>
                    <svg
                      v-else-if="opt.value === 'post_appointment'"
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <rect x="3" y="4" width="18" height="18" rx="2" />
                      <path d="M16 2v4M8 2v4M3 10h18" />
                      <path d="m9 16 2 2 4-4" />
                    </svg>
                    <svg
                      v-else-if="opt.value === 'no_show'"
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <rect x="3" y="4" width="18" height="18" rx="2" />
                      <path d="M16 2v4M8 2v4M3 10h18" />
                      <path d="m14 14-4 4M10 14l4 4" />
                    </svg>
                    <svg
                      v-else-if="opt.value === 'no_response'"
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path
                        d="M21 12c0 4.97-4.03 9-9 9-1.5 0-2.91-.37-4.15-1.02L3 21l1.02-4.85A8.96 8.96 0 0 1 3 12c0-4.97 4.03-9 9-9s9 4.03 9 9z"
                      />
                      <path d="M2 2l20 20" />
                    </svg>
                    <svg
                      v-else-if="opt.value === 'appointment_confirmed'"
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path d="M22 11.08V12a10 10 0 1 1-5.93-9.14" />
                      <path d="m9 11 3 3L22 4" />
                    </svg>
                    <svg
                      v-else-if="opt.value === 'service_recall'"
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path d="M3 2v6h6" />
                      <path d="M3 13a9 9 0 1 0 3-7.7L3 8" />
                    </svg>
                    <svg
                      v-else
                      class="w-[18px] h-[18px]"
                      :style="{ color: opt.iconColor }"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <polygon
                        points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"
                      />
                    </svg>
                  </div>
                  <span
                    class="text-sm font-medium text-n-slate-12 leading-tight flex-1 min-w-0"
                    >{{ opt.label }}</span>
                  <svg
                    v-if="form.trigger_type === opt.value"
                    class="shrink-0 w-4 h-4 text-woot-500"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="3"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M20 6 9 17l-5-5" />
                  </svg>
                </button>
              </div>
              <p class="text-xs text-n-slate-10 mt-2.5 leading-relaxed">
                {{ triggerHelper }}
              </p>
            </div>

            <!-- Aplicar quando — só pra triggers de agenda. Filtra por origem
                 do AgendaEvent (Bea / humano / ambos). -->
            <div v-if="showAppliesTo">
              <label class="block text-sm font-semibold text-n-slate-12 mb-2">{{
                $t('AI_AGENT.FOLLOW_UPS.FORM.APPLIES_TO_LABEL')
              }}</label>
              <div class="space-y-2">
                <label
                  v-for="opt in APPLIES_TO_OPTIONS"
                  :key="opt.value"
                  class="flex items-start gap-3 p-3 rounded-lg border-2 cursor-pointer transition-all"
                  :class="
                    form.applies_to === opt.value
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'
                  "
                >
                  <input
                    v-model="form.applies_to"
                    type="radio"
                    :value="opt.value"
                    class="mt-0.5 shrink-0"
                  />
                  <div class="min-w-0">
                    <div
                      class="text-sm font-medium text-n-slate-12 leading-tight"
                    >
                      {{ opt.label }}
                    </div>
                    <div class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">
                      {{ opt.helper }}
                    </div>
                  </div>
                </label>
              </div>
            </div>

            <!-- Quando disparar: mesmo padrão do "Limite por paciente" — input
                 com sufixo de unidade clicável que cicla entre segundos/minutos/horas.
                 Escondido pra `appointment_confirmed` (event-driven, dispara na hora). -->
            <div v-if="showOffset">
              <label
                class="block text-sm font-semibold text-n-slate-12 mb-1.5"
                >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.WHEN_LABEL') }}</label>
              <div class="relative w-40">
                <input
                  v-model.number="form.offset_hours"
                  type="number"
                  :min="UNIT_LIMITS[form.offset_unit].min"
                  :max="UNIT_LIMITS[form.offset_unit].max"
                  required
                  class="w-full h-11 pl-3.5 pr-20 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                />
                <button
                  type="button"
                  class="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 hover:text-n-slate-12 cursor-pointer select-none border-0 bg-transparent p-0 transition-colors"
                  :title="
                    $t('AI_AGENT.FOLLOW_UPS.FORM.UNIT_TOGGLE_TITLE', {
                      unit: unitLong,
                    })
                  "
                  @click="cycleUnit"
                >
                  {{ unitLong }}
                </button>
              </div>
              <p class="text-xs text-n-slate-10 mt-2 leading-relaxed">
                <span class="font-medium text-n-slate-11">{{
                  offsetLabel
                }}</span>
                <span class="text-n-slate-9">{{
                  $t('AI_AGENT.FOLLOW_UPS.FORM.UNIT_HELP_HINT', {
                    unit: unitLong,
                  })
                }}</span>
              </p>
              <p
                v-if="granularityWarning"
                class="text-xs mt-1.5 flex items-start gap-1.5 leading-relaxed"
                style="color: #b45309"
              >
                <svg
                  class="w-3.5 h-3.5 mt-0.5 shrink-0"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M12 9v4M12 17h.01" />
                  <path
                    d="M10.29 3.86 1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"
                  />
                </svg>
                {{ granularityWarning }}
              </p>
            </div>

            <!-- Reativação por serviço (Fase 6): serviço-alvo + intervalo
                 (valor + unidade ciclável dias/semanas/meses). Dispara esse
                 tempo após a última sessão assinada do serviço. -->
            <div
              v-if="isServiceRecall"
              class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 space-y-4"
            >
              <div class="flex items-start gap-3">
                <div
                  class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg"
                  style="background-color: #fce7f3"
                >
                  <svg
                    class="w-[18px] h-[18px]"
                    style="color: #db2777"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M3 2v6h6" />
                    <path d="M3 13a9 9 0 1 0 3-7.7L3 8" />
                  </svg>
                </div>
                <div class="min-w-0">
                  <h3 class="text-sm font-semibold text-n-slate-12 leading-tight">
                    {{ $t('AI_AGENT.FOLLOW_UPS.SERVICE.TITLE') }}
                  </h3>
                  <p class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                    {{ $t('AI_AGENT.FOLLOW_UPS.SERVICE.SUBTITLE') }}
                  </p>
                </div>
              </div>

              <div>
                <label class="block text-xs font-medium text-n-slate-11 mb-1">{{
                  $t('AI_AGENT.FOLLOW_UPS.SERVICE.SERVICE_LABEL')
                }}</label>
                <FormSelect
                  v-model="form.agenda_service_id"
                  :options="serviceOptions"
                  :placeholder="
                    $t('AI_AGENT.FOLLOW_UPS.SERVICE.SERVICE_PLACEHOLDER')
                  "
                  :search-placeholder="
                    $t('AI_AGENT.FOLLOW_UPS.SERVICE.SERVICE_SEARCH')
                  "
                  auto-searchable
                />
                <p
                  v-if="!agendaServices.length"
                  class="text-xs text-n-slate-10 mt-1.5 leading-relaxed"
                >
                  {{ $t('AI_AGENT.FOLLOW_UPS.SERVICE.NO_SERVICES') }}
                </p>
              </div>

              <div>
                <label class="block text-xs font-medium text-n-slate-11 mb-1">{{
                  $t('AI_AGENT.FOLLOW_UPS.SERVICE.INTERVAL_LABEL')
                }}</label>
                <div class="relative w-44">
                  <input
                    v-model.number="form.recall_interval_value"
                    type="number"
                    :min="RECALL_UNIT_LIMITS[form.recall_interval_unit]?.min || 1"
                    :max="RECALL_UNIT_LIMITS[form.recall_interval_unit]?.max || 36"
                    class="w-full h-11 pl-3.5 pr-24 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                  />
                  <button
                    type="button"
                    class="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 hover:text-n-slate-12 cursor-pointer select-none border-0 bg-transparent p-0 transition-colors"
                    :title="
                      $t('AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_TOGGLE_TITLE', {
                        unit: recallUnitLong,
                      })
                    "
                    @click="cycleRecallUnit"
                  >
                    {{ recallUnitLong }}
                  </button>
                </div>
                <p class="text-xs text-n-slate-10 mt-2 leading-relaxed">
                  {{ $t('AI_AGENT.FOLLOW_UPS.SERVICE.INTERVAL_HELP') }}
                </p>
              </div>
            </div>

            <!-- Modo de ação: a Bea escreve (generativo) ou mensagem fixa (estático) -->
            <div>
              <label class="block text-sm font-semibold text-n-slate-12 mb-2">{{
                $t('AI_AGENT.FOLLOW_UPS.FORM.ACTION_LABEL')
              }}</label>
              <div class="grid grid-cols-2 gap-2.5">
                <button
                  type="button"
                  class="flex items-start gap-3 px-3.5 py-3 text-left rounded-lg border-2 transition-all"
                  :class="
                    !isStatic
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'
                  "
                  @click="form.action_type = 'generative'"
                >
                  <svg
                    class="shrink-0 w-[18px] h-[18px] mt-0.5 text-woot-500"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path
                      d="M12 3c.5 2.5 2 4 4.5 4.5C14 8 12.5 9.5 12 12c-.5-2.5-2-4-4.5-4.5C10 7 11.5 5.5 12 3z"
                    />
                    <path
                      d="M19 12c.3 1.5 1.2 2.4 2.7 2.7-1.5.3-2.4 1.2-2.7 2.7-.3-1.5-1.2-2.4-2.7-2.7 1.5-.3 2.4-1.2 2.7-2.7z"
                    />
                  </svg>
                  <div class="min-w-0">
                    <div
                      class="text-sm font-medium text-n-slate-12 leading-tight"
                    >
                      {{
                        $t('AI_AGENT.FOLLOW_UPS.FORM.ACTION_GENERATIVE_LABEL')
                      }}
                    </div>
                    <div class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">
                      {{
                        $t('AI_AGENT.FOLLOW_UPS.FORM.ACTION_GENERATIVE_HELPER')
                      }}
                    </div>
                  </div>
                </button>
                <button
                  type="button"
                  class="flex items-start gap-3 px-3.5 py-3 text-left rounded-lg border-2 transition-all"
                  :class="
                    isStatic
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak hover:border-n-slate-7 bg-n-solid-1'
                  "
                  @click="form.action_type = 'static'"
                >
                  <svg
                    class="shrink-0 w-[18px] h-[18px] mt-0.5 text-n-slate-11"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path
                      d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"
                    />
                    <path d="M14 2v6h6M8 13h8M8 17h5" />
                  </svg>
                  <div class="min-w-0">
                    <div
                      class="text-sm font-medium text-n-slate-12 leading-tight"
                    >
                      {{ $t('AI_AGENT.FOLLOW_UPS.FORM.ACTION_STATIC_LABEL') }}
                    </div>
                    <div class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">
                      {{ $t('AI_AGENT.FOLLOW_UPS.FORM.ACTION_STATIC_HELPER') }}
                    </div>
                  </div>
                </button>
              </div>
            </div>

            <!-- Cenário (modo generativo) -->
            <div v-if="!isStatic">
              <label
                class="block text-sm font-semibold text-n-slate-12 mb-1.5"
                >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.CONTEXT_LABEL') }}</label>
              <textarea
                v-model="form.context_brief"
                rows="8"
                maxlength="4000"
                :placeholder="
                  $t('AI_AGENT.FOLLOW_UPS.FORM.CONTEXT_PLACEHOLDER')
                "
                class="w-full min-h-[180px] px-3.5 py-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed"
              />
              <p
                class="text-xs text-n-slate-10 mt-1.5 leading-relaxed flex items-start gap-1.5"
              >
                <svg
                  class="w-3.5 h-3.5 mt-0.5 shrink-0"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <circle cx="12" cy="12" r="10" />
                  <path d="M12 16v-4M12 8h.01" />
                </svg>
                {{ $t('AI_AGENT.FOLLOW_UPS.FORM.CONTEXT_HELP') }}
              </p>
            </div>

            <!-- Persona/tom por tipo (Fase 5) — opcional, só no modo generativo -->
            <div v-if="!isStatic">
              <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">
                {{ $t('AI_AGENT.FOLLOW_UPS.FORM.PERSONA_LABEL') }}
                <span class="text-xs text-n-slate-9 font-normal">{{
                  $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.OPTIONAL')
                }}</span>
              </label>
              <textarea
                v-model="form.persona_override"
                rows="3"
                maxlength="2000"
                :placeholder="
                  $t('AI_AGENT.FOLLOW_UPS.FORM.PERSONA_PLACEHOLDER')
                "
                class="w-full min-h-[72px] px-3.5 py-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed"
              />
              <p class="text-xs text-n-slate-10 mt-1.5 leading-relaxed">
                {{ $t('AI_AGENT.FOLLOW_UPS.FORM.PERSONA_HELP') }}
              </p>
            </div>

            <!-- Mensagem fixa (modo estático) -->
            <div v-else>
              <label
                class="block text-sm font-semibold text-n-slate-12 mb-1.5"
                >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.STATIC_LABEL') }}</label>
              <textarea
                v-model="form.static_body"
                rows="6"
                maxlength="4000"
                :placeholder="$t('AI_AGENT.FOLLOW_UPS.FORM.STATIC_PLACEHOLDER')"
                class="w-full min-h-[140px] px-3.5 py-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed"
              />
              <div class="flex flex-wrap items-center gap-1.5 mt-2">
                <span class="text-xs text-n-slate-10 mr-1">{{
                  $t('AI_AGENT.FOLLOW_UPS.FORM.STATIC_VARS_HINT')
                }}</span>
                <button
                  v-for="key in STATIC_VARIABLES"
                  :key="key"
                  type="button"
                  class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11 hover:bg-woot-50 hover:text-woot-600 transition-colors border-0 cursor-pointer"
                  @click="insertVar(form, key)"
                >
                  {{ varToken(key) }}
                </button>
              </div>
            </div>

            <!-- Cadência: passos adicionais (2..N). Só pra gatilhos cron.
                 O passo 1 são os campos "Quando disparar" + "Cenário" acima. -->
            <div
              v-if="showCadence"
              class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 space-y-4"
            >
              <div class="flex items-start justify-between gap-4">
                <div class="min-w-0">
                  <div class="flex items-center gap-2">
                    <svg
                      class="w-4 h-4 text-woot-500 shrink-0"
                      viewBox="0 0 24 24"
                      fill="none"
                      stroke="currentColor"
                      stroke-width="2"
                      stroke-linecap="round"
                      stroke-linejoin="round"
                    >
                      <path d="M4 6h16M4 12h16M4 18h10" />
                    </svg>
                    <h3
                      class="text-sm font-semibold text-n-slate-12 leading-tight"
                    >
                      {{ $t('AI_AGENT.FOLLOW_UPS.STEPS.TITLE') }}
                    </h3>
                  </div>
                  <p class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                    {{ $t('AI_AGENT.FOLLOW_UPS.STEPS.HELP') }}
                  </p>
                </div>
              </div>

              <!-- Passo 1 (a própria regra) — só leitura, contextualiza a sequência -->
              <div
                class="flex items-center gap-2.5 px-3 py-2 rounded-lg bg-n-solid-1 border border-n-weak"
              >
                <span
                  class="shrink-0 inline-flex items-center justify-center w-6 h-6 rounded-full bg-woot-50 text-woot-600 text-xs font-semibold"
                  >1</span>
                <span class="text-xs text-n-slate-10 leading-snug">{{
                  $t('AI_AGENT.FOLLOW_UPS.STEPS.STEP_ONE_HINT')
                }}</span>
              </div>

              <!-- Passos 2..N -->
              <div
                v-for="(step, idx) in steps"
                :key="idx"
                class="rounded-lg bg-n-solid-1 border border-n-weak p-3.5 space-y-3"
              >
                <div class="flex items-center justify-between gap-3">
                  <span
                    class="inline-flex items-center gap-2 text-sm font-semibold text-n-slate-12"
                  >
                    <span
                      class="inline-flex items-center justify-center w-6 h-6 rounded-full bg-woot-50 text-woot-600 text-xs font-semibold"
                      >{{ idx + 2 }}</span>
                    {{
                      $t('AI_AGENT.FOLLOW_UPS.STEPS.STEP_LABEL', { n: idx + 2 })
                    }}
                  </span>
                  <button
                    type="button"
                    class="flex items-center gap-1 text-xs text-n-ruby-9 hover:text-n-ruby-11 transition-colors border-0 bg-transparent p-1 cursor-pointer"
                    @click="removeStep(idx)"
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
                        d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"
                      />
                    </svg>
                    {{ $t('AI_AGENT.FOLLOW_UPS.STEPS.REMOVE') }}
                  </button>
                </div>

                <div>
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1"
                    >{{ $t('AI_AGENT.FOLLOW_UPS.STEPS.WHEN_LABEL') }}</label>
                  <div class="relative w-40">
                    <input
                      v-model.number="step.offset_hours"
                      type="number"
                      :min="UNIT_LIMITS[step.offset_unit].min"
                      :max="UNIT_LIMITS[step.offset_unit].max"
                      class="w-full h-10 pl-3 pr-20 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                    />
                    <button
                      type="button"
                      class="absolute right-3 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 hover:text-n-slate-12 cursor-pointer select-none border-0 bg-transparent p-0 transition-colors"
                      @click="cycleStepUnit(step)"
                    >
                      {{ stepUnitLong(step) }}
                    </button>
                  </div>
                </div>

                <!-- Cenário (generativo) ou mensagem fixa (estático) do passo -->
                <div v-if="!isStatic">
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1"
                    >{{ $t('AI_AGENT.FOLLOW_UPS.STEPS.CONTEXT_LABEL') }}</label>
                  <textarea
                    v-model="step.context_brief"
                    rows="3"
                    maxlength="4000"
                    :placeholder="
                      $t('AI_AGENT.FOLLOW_UPS.STEPS.CONTEXT_PLACEHOLDER')
                    "
                    class="w-full min-h-[72px] px-3 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed"
                  />
                </div>
                <div v-else>
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1"
                    >{{ $t('AI_AGENT.FOLLOW_UPS.STEPS.STATIC_LABEL') }}</label>
                  <textarea
                    v-model="step.static_body"
                    rows="3"
                    maxlength="4000"
                    :placeholder="
                      $t('AI_AGENT.FOLLOW_UPS.STEPS.STATIC_PLACEHOLDER')
                    "
                    class="w-full min-h-[72px] px-3 py-2 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 resize-y transition-shadow leading-relaxed"
                  />
                  <div class="flex flex-wrap items-center gap-1.5 mt-1.5">
                    <button
                      v-for="key in STATIC_VARIABLES"
                      :key="key"
                      type="button"
                      class="inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-md bg-n-alpha-2 text-n-slate-11 hover:bg-woot-50 hover:text-woot-600 transition-colors border-0 cursor-pointer"
                      @click="insertVar(step, key)"
                    >
                      {{ varToken(key) }}
                    </button>
                  </div>
                </div>
              </div>

              <button
                type="button"
                class="w-full flex items-center justify-center gap-2 h-10 rounded-lg border-2 border-dashed border-n-weak text-sm font-medium text-n-slate-11 hover:border-woot-400 hover:text-woot-600 hover:bg-woot-50/50 transition-all cursor-pointer bg-transparent"
                @click="addStep"
              >
                <svg
                  class="w-4 h-4"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <path d="M12 5v14M5 12h14" />
                </svg>
                {{ $t('AI_AGENT.FOLLOW_UPS.STEPS.ADD') }}
              </button>
            </div>

            <!-- Condições de saída (Fase 3): para a sequência quando o
                 paciente já se engajou (respondeu / (re)agendou). -->
            <div
              v-if="showStopConditions"
              class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 space-y-3"
            >
              <div class="flex items-center gap-2">
                <svg
                  class="w-4 h-4 text-woot-500 shrink-0"
                  viewBox="0 0 24 24"
                  fill="none"
                  stroke="currentColor"
                  stroke-width="2"
                  stroke-linecap="round"
                  stroke-linejoin="round"
                >
                  <circle cx="12" cy="12" r="10" />
                  <path d="M9 9h6v6H9z" />
                </svg>
                <h3 class="text-sm font-semibold text-n-slate-12 leading-tight">
                  {{ $t('AI_AGENT.FOLLOW_UPS.STOP.TITLE') }}
                </h3>
              </div>

              <label
                v-if="showCadence"
                class="flex items-start justify-between gap-4 cursor-pointer"
              >
                <div class="min-w-0">
                  <div
                    class="text-sm font-medium text-n-slate-12 leading-tight"
                  >
                    {{ $t('AI_AGENT.FOLLOW_UPS.STOP.ON_REPLY_LABEL') }}
                  </div>
                  <div class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">
                    {{ $t('AI_AGENT.FOLLOW_UPS.STOP.ON_REPLY_HELP') }}
                  </div>
                </div>
                <button
                  type="button"
                  role="switch"
                  :aria-checked="form.stop_on_reply"
                  class="relative shrink-0 inline-flex h-6 w-11 flex-none items-center rounded-full transition-colors focus:outline-none p-0 border-0"
                  :class="form.stop_on_reply ? 'bg-woot-500' : 'bg-n-slate-6'"
                  @click="form.stop_on_reply = !form.stop_on_reply"
                >
                  <span
                    class="absolute left-0.5 inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform"
                    :class="
                      form.stop_on_reply ? 'translate-x-5' : 'translate-x-0'
                    "
                  />
                </button>
              </label>

              <label
                v-if="showStopBooking"
                class="flex items-start justify-between gap-4 cursor-pointer"
              >
                <div class="min-w-0">
                  <div
                    class="text-sm font-medium text-n-slate-12 leading-tight"
                  >
                    {{ $t('AI_AGENT.FOLLOW_UPS.STOP.ON_BOOKING_LABEL') }}
                  </div>
                  <div class="text-xs text-n-slate-10 mt-0.5 leading-relaxed">
                    {{ $t('AI_AGENT.FOLLOW_UPS.STOP.ON_BOOKING_HELP') }}
                  </div>
                </div>
                <button
                  type="button"
                  role="switch"
                  :aria-checked="form.stop_on_booking"
                  class="relative shrink-0 inline-flex h-6 w-11 flex-none items-center rounded-full transition-colors focus:outline-none p-0 border-0"
                  :class="form.stop_on_booking ? 'bg-woot-500' : 'bg-n-slate-6'"
                  @click="form.stop_on_booking = !form.stop_on_booking"
                >
                  <span
                    class="absolute left-0.5 inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform"
                    :class="
                      form.stop_on_booking ? 'translate-x-5' : 'translate-x-0'
                    "
                  />
                </button>
              </label>
            </div>

            <!-- Fallback de template (Fase 4): envio fora da janela de 24h
                 no WhatsApp oficial. Opcional — só usado por contas Cloud API.
                 Aparece também na reativação por serviço (sempre fora de 24h). -->
            <div
              v-if="showCadence || isServiceRecall"
              class="rounded-xl border border-n-weak bg-n-alpha-1 p-4 space-y-4"
            >
              <div>
                <div class="flex items-center gap-2">
                  <svg
                    class="w-4 h-4 text-woot-500 shrink-0"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="2"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path
                      d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
                    />
                  </svg>
                  <h3
                    class="text-sm font-semibold text-n-slate-12 leading-tight"
                  >
                    {{ $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.TITLE') }}
                  </h3>
                  <span class="text-xs text-n-slate-9 font-normal">{{
                    $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.OPTIONAL')
                  }}</span>
                </div>
                <p class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                  {{ $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.HELP') }}
                </p>
              </div>

              <div class="grid grid-cols-2 gap-3">
                <div>
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1"
                    >{{ $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.NAME_LABEL') }}</label>
                  <input
                    v-model="form.cloud_template_name"
                    type="text"
                    :placeholder="
                      $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.NAME_PLACEHOLDER')
                    "
                    class="w-full h-10 px-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                  />
                </div>
                <div>
                  <label
                    class="block text-xs font-medium text-n-slate-11 mb-1"
                    >{{ $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.LANG_LABEL') }}</label>
                  <input
                    v-model="form.cloud_template_lang"
                    type="text"
                    placeholder="pt_BR"
                    class="w-full h-10 px-3 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 placeholder:text-n-slate-9 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                  />
                </div>
              </div>

              <!-- Variáveis posicionais {{1}}, {{2}}... -->
              <div v-if="form.cloud_template_name">
                <label
                  class="block text-xs font-medium text-n-slate-11 mb-1.5"
                  >{{ $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.PARAMS_LABEL') }}</label>
                <div
                  v-for="(param, idx) in templateParams"
                  :key="idx"
                  class="flex items-center gap-2 mb-2"
                >
                  <span
                    class="shrink-0 inline-flex items-center justify-center min-w-7 h-9 px-2 rounded-lg bg-n-alpha-2 text-xs font-semibold text-n-slate-11"
                    >{{ varToken(String(idx + 1)) }}</span>
                  <select
                    v-model="templateParams[idx]"
                    class="flex-1 h-9 px-2 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow"
                  >
                    <option v-for="v in STATIC_VARIABLES" :key="v" :value="v">
                      {{ varToken(v) }}
                    </option>
                  </select>
                  <button
                    type="button"
                    class="shrink-0 flex items-center justify-center w-9 h-9 rounded-lg text-n-ruby-9 hover:bg-n-alpha-2 transition-colors border-0 bg-transparent cursor-pointer"
                    @click="removeTemplateParam(idx)"
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
                      <path d="M18 6 6 18M6 6l12 12" />
                    </svg>
                  </button>
                </div>
                <button
                  type="button"
                  class="inline-flex items-center gap-1.5 text-xs font-medium text-woot-600 hover:text-woot-700 transition-colors border-0 bg-transparent cursor-pointer p-0"
                  @click="addTemplateParam"
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
                    <path d="M12 5v14M5 12h14" />
                  </svg>
                  {{ $t('AI_AGENT.FOLLOW_UPS.TEMPLATE.ADD_PARAM') }}
                </button>
              </div>
            </div>

            <!-- Limite -->
            <div>
              <label
                class="block text-sm font-semibold text-n-slate-12 mb-1.5"
                >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_LABEL') }}</label>
              <div class="relative w-40">
                <input
                  v-model.number="form.max_per_target"
                  type="number"
                  min="0"
                  max="100"
                  class="w-full h-11 pl-3.5 pr-20 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                />
                <span
                  class="absolute right-3.5 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 pointer-events-none select-none"
                >
                  {{
                    form.max_per_target === 1
                      ? $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_SUFFIX_ONE')
                      : $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_SUFFIX_MANY')
                  }}
                </span>
              </div>
              <p class="text-xs text-n-slate-10 mt-2 leading-relaxed">
                <template v-if="form.max_per_target === 0">
                  <span class="font-medium" style="color: #b45309">{{
                    $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_ZERO_HIGHLIGHT')
                  }}</span>{{ $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_ZERO_REST') }}
                </template>
                <template v-else-if="form.max_per_target === 1">
                  {{ $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_ONE_PREFIX')
                  }}<span class="font-medium text-n-slate-11">{{
                    $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_ONE_HIGHLIGHT')
                  }}</span>{{ $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_ONE_SUFFIX') }}
                </template>
                <template v-else>
                  {{ $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_MANY_PREFIX')
                  }}<span class="font-medium text-n-slate-11">{{
                    $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_MANY_HIGHLIGHT', {
                      count: form.max_per_target,
                    })
                  }}</span>{{ $t('AI_AGENT.FOLLOW_UPS.FORM.MAX_HELP_MANY_SUFFIX') }}
                </template>
              </p>
            </div>

            <!-- Cooldown anti-spam por regra: intervalo mínimo desde o último
                 follow-up de OUTRA regra pro mesmo paciente. 0 = sem trava. -->
            <div>
              <label
                class="block text-sm font-semibold text-n-slate-12 mb-1.5"
                >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_LABEL') }}</label>
              <div class="relative w-40">
                <input
                  v-model.number="form.cooldown_minutes"
                  type="number"
                  min="0"
                  max="10080"
                  class="w-full h-11 pl-3.5 pr-20 text-sm border border-n-weak rounded-lg bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-woot-500 focus:ring-2 focus:ring-woot-500/20 transition-shadow font-medium"
                />
                <span
                  class="absolute right-3.5 top-1/2 -translate-y-1/2 text-sm text-n-slate-10 pointer-events-none select-none"
                >
                  {{ $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_SUFFIX') }}
                </span>
              </div>
              <p class="text-xs text-n-slate-10 mt-2 leading-relaxed">
                <template v-if="Number(form.cooldown_minutes) === 0">
                  <span class="font-medium" style="color: #b45309">{{
                    $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_HELP_ZERO_HIGHLIGHT')
                  }}</span
                  >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_HELP_ZERO_REST') }}
                </template>
                <template v-else>
                  {{ $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_HELP_PREFIX')
                  }}<span class="font-medium text-n-slate-11">{{
                    $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_HELP_HIGHLIGHT', {
                      count: form.cooldown_minutes,
                    })
                  }}</span
                  >{{ $t('AI_AGENT.FOLLOW_UPS.FORM.COOLDOWN_HELP_SUFFIX') }}
                </template>
              </p>
            </div>

            <!-- Toggle ativo: container alinhado, switch dentro do contêiner -->
            <div
              class="flex items-center justify-between gap-4 px-4 py-3.5 rounded-lg bg-n-alpha-1 border border-n-weak"
            >
              <div class="min-w-0 pr-2">
                <div
                  class="text-sm font-semibold text-n-slate-12 leading-tight"
                >
                  {{ $t('AI_AGENT.FOLLOW_UPS.FORM.ENABLED_TITLE') }}
                </div>
                <div class="text-xs text-n-slate-10 mt-1 leading-relaxed">
                  {{ $t('AI_AGENT.FOLLOW_UPS.FORM.ENABLED_HELP') }}
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

          <!-- Footer: botão sempre clicável — clicar com campo faltando
               mostra um toast dizendo exatamente o que falta (onSave). -->
          <footer
            class="flex-shrink-0 px-7 py-4 border-t border-n-weak flex items-center justify-end gap-3 bg-n-alpha-1"
          >
            <BeclinicButton
              :label="$t('AI_AGENT.FOLLOW_UPS.FORM.CANCEL')"
              variant="outline"
              color="slate"
              @click="closeModal"
            />
            <BeclinicButton
              :label="
                editingId
                  ? $t('AI_AGENT.FOLLOW_UPS.FORM.SAVE_EDIT')
                  : $t('AI_AGENT.FOLLOW_UPS.FORM.SAVE_NEW')
              "
              :is-loading="isSaving"
              :disabled="isSaving"
              @click="onSave"
            />
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.modal-enter-active,
.modal-leave-active {
  transition: opacity 0.2s ease;
}
.modal-enter-active > div,
.modal-leave-active > div {
  transition:
    transform 0.24s cubic-bezier(0.16, 1, 0.3, 1),
    opacity 0.2s ease;
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
