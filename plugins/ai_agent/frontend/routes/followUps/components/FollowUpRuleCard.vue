<script setup>
// FE-3 (auditoria 2026-05-18): extraído do Index.vue (702 LOC).
// Card individual de uma regra de follow-up no grid principal.
// Constants são duplicadas (não importadas) por design — extração mecânica
// sem novas abstrações, conforme directive do FE-3/4.
// FE-16/17 (i18n 2026-05-19): strings migradas para `AI_AGENT.FOLLOW_UPS.*`.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  rule: { type: Object, required: true },
});

defineEmits(['edit', 'toggle', 'delete']);

const { t } = useI18n();

// SVG inline + cores INLINE STYLE — o JIT do Tailwind não pega classes
// vindas de `:class="opt.bg"` (string dinâmica).
// Labels lidos via i18n (helper `triggerMeta` resolve por value).
const TRIGGER_OPTIONS = computed(() => [
  {
    value: 'pre_appointment',
    iconColor: '#0284c7',
    bgColor: '#e0f2fe',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.PRE_APPOINTMENT_LABEL'),
  },
  {
    value: 'post_appointment',
    iconColor: '#059669',
    bgColor: '#d1fae5',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.POST_APPOINTMENT_LABEL'),
  },
  {
    value: 'no_show',
    iconColor: '#d97706',
    bgColor: '#fef3c7',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.NO_SHOW_LABEL'),
  },
  {
    value: 'appointment_confirmed',
    iconColor: '#0891b2',
    bgColor: '#cffafe',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.APPOINTMENT_CONFIRMED_LABEL'),
  },
  {
    value: 'no_response',
    iconColor: '#7c3aed',
    bgColor: '#ede9fe',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.NO_RESPONSE_LABEL'),
  },
  {
    value: 'service_recall',
    iconColor: '#db2777',
    bgColor: '#fce7f3',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.SERVICE_RECALL_LABEL'),
  },
  {
    value: 'custom',
    iconColor: '#64748b',
    bgColor: '#f1f5f9',
    label: t('AI_AGENT.FOLLOW_UPS.TRIGGERS.CUSTOM_LABEL'),
  },
]);

const UNIT_OPTIONS = computed(() => [
  { value: 'seconds', short: t('AI_AGENT.FOLLOW_UPS.UNITS.SECONDS_SHORT') },
  { value: 'minutes', short: t('AI_AGENT.FOLLOW_UPS.UNITS.MINUTES_SHORT') },
  { value: 'hours', short: t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_SHORT') },
]);

const triggerMeta = type =>
  TRIGGER_OPTIONS.value.find(o => o.value === type) || TRIGGER_OPTIONS.value[0];

const unitShortFor = unit =>
  UNIT_OPTIONS.value.find(u => u.value === unit)?.short ||
  t('AI_AGENT.FOLLOW_UPS.UNITS.HOURS_SHORT');

// applies_to só tem efeito nos triggers de agenda — não exibe o badge
// "Apenas IA/Apenas humano" em no_response/custom/service_recall.
const AGENDA_TRIGGERS = [
  'pre_appointment',
  'post_appointment',
  'no_show',
  'appointment_confirmed',
];

const appliesToBadgeFor = rule => {
  if (!AGENDA_TRIGGERS.includes(rule.trigger_type)) return null;
  const v = rule.applies_to || 'both';
  if (v === 'ai_agent')
    return {
      text: t('AI_AGENT.FOLLOW_UPS.CARD.BADGE_AI_AGENT'),
      color: '#7c3aed',
      bg: '#ede9fe',
    };
  if (v === 'manual')
    return {
      text: t('AI_AGENT.FOLLOW_UPS.CARD.BADGE_HUMAN'),
      color: '#0284c7',
      bg: '#e0f2fe',
    };
  return null; // 'both' não mostra badge — é o default
};

const meta = computed(() => triggerMeta(props.rule.trigger_type));
const appliesBadge = computed(() => appliesToBadgeFor(props.rule));
</script>

<template>
  <article
    class="group relative bg-n-solid-1 border border-n-weak rounded-2xl p-5 hover:border-n-strong hover:shadow-md transition-all flex flex-col"
    :class="{ 'opacity-70': !rule.enabled }"
  >
    <!-- Top: ícone + título + status -->
    <div class="flex items-start justify-between gap-3 mb-3">
      <div class="flex items-start gap-3 min-w-0 flex-1">
        <div
          class="shrink-0 flex items-center justify-center w-10 h-10 rounded-xl"
          :style="{ backgroundColor: meta.bgColor }"
        >
          <!-- ícones SVG inline com cor inline (Tailwind JIT não pega classe vinda de variável) -->
          <svg
            v-if="rule.trigger_type === 'pre_appointment'"
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
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
            v-else-if="rule.trigger_type === 'post_appointment'"
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
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
            v-else-if="rule.trigger_type === 'no_show'"
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
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
            v-else-if="rule.trigger_type === 'no_response'"
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
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
            v-else-if="rule.trigger_type === 'appointment_confirmed'"
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
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
            v-else-if="rule.trigger_type === 'service_recall'"
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
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
            class="w-5 h-5"
            :style="{ color: meta.iconColor }"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="2"
            stroke-linecap="round"
            stroke-linejoin="round"
          >
            <polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2" />
          </svg>
        </div>
        <div class="min-w-0 flex-1">
          <h3
            class="text-base font-semibold text-n-slate-12 truncate leading-tight"
          >
            {{ rule.name }}
          </h3>
          <p
            class="text-xs text-n-slate-10 mt-0.5 font-medium uppercase tracking-wide"
          >
            {{ meta.label }}
          </p>
        </div>
      </div>
      <span
        class="shrink-0 inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium rounded-md"
        :class="
          rule.enabled
            ? 'bg-emerald-100 text-emerald-700'
            : 'bg-n-alpha-2 text-n-slate-10'
        "
      >
        <span
          class="w-1.5 h-1.5 rounded-full"
          :class="rule.enabled ? 'bg-emerald-500' : 'bg-n-slate-9'"
        />
        {{
          rule.enabled
            ? $t('AI_AGENT.FOLLOW_UPS.CARD.STATUS_ACTIVE')
            : $t('AI_AGENT.FOLLOW_UPS.CARD.STATUS_PAUSED')
        }}
      </span>
    </div>

    <!-- Context preview: cenário (generativo) ou mensagem fixa (estático) -->
    <p
      class="text-sm text-n-slate-11 leading-relaxed line-clamp-2 mb-4 min-h-[2.6em] flex-1"
    >
      {{
        rule.action_type === 'static' ? rule.static_body : rule.context_brief
      }}
    </p>

    <!-- Stats pills -->
    <div class="flex flex-wrap items-center gap-2 mb-4">
      <!-- Modo: Bea (generativo) ou mensagem fixa (estático) -->
      <span
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md font-medium"
        :style="
          rule.action_type === 'static'
            ? { color: '#475569', backgroundColor: '#f1f5f9' }
            : { color: '#7c3aed', backgroundColor: '#ede9fe' }
        "
      >
        <svg
          v-if="rule.action_type === 'static'"
          class="w-3.5 h-3.5"
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
        <svg
          v-else
          class="w-3.5 h-3.5"
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
        </svg>
        {{
          rule.action_type === 'static'
            ? $t('AI_AGENT.FOLLOW_UPS.CARD.MODE_STATIC')
            : $t('AI_AGENT.FOLLOW_UPS.CARD.MODE_GENERATIVE')
        }}
      </span>
      <span
        v-if="rule.trigger_type === 'appointment_confirmed'"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
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
          <path d="M13 2 3 14h9l-1 8 10-12h-9l1-8z" />
        </svg>
        {{ $t('AI_AGENT.FOLLOW_UPS.CARD.IMMEDIATE') }}
      </span>
      <span
        v-else-if="rule.trigger_type === 'service_recall'"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
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
          <path d="M3 2v6h6" />
          <path d="M3 13a9 9 0 1 0 3-7.7L3 8" />
        </svg>
        {{
          $t('AI_AGENT.FOLLOW_UPS.CARD.RECALL_EVERY', {
            value: rule.recall_interval_value,
            unit: $t(
              `AI_AGENT.FOLLOW_UPS.SERVICE.UNIT_${(
                rule.recall_interval_unit || 'months'
              ).toUpperCase()}`
            ),
          })
        }}
      </span>
      <span
        v-else
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
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
          <circle cx="12" cy="12" r="10" />
          <path d="M12 6v6l4 2" />
        </svg>
        {{ rule.offset_hours }}{{ unitShortFor(rule.offset_unit) }}
      </span>
      <span
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
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
          <path d="m17 2 4 4-4 4" />
          <path d="M3 11v-1a4 4 0 0 1 4-4h14" />
          <path d="m7 22-4-4 4-4" />
          <path d="M21 13v1a4 4 0 0 1-4 4H3" />
        </svg>
        {{
          rule.max_per_target === 0
            ? $t('AI_AGENT.FOLLOW_UPS.CARD.MAX_UNLIMITED')
            : $t('AI_AGENT.FOLLOW_UPS.CARD.MAX_PER_TARGET', {
                count: rule.max_per_target,
              })
        }}
      </span>
      <!-- Cadência: passos adicionais além do passo 1 -->
      <span
        v-if="rule.steps && rule.steps.length"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md font-medium"
        :style="{ color: '#7c3aed', backgroundColor: '#ede9fe' }"
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
          <path d="M4 6h16M4 12h16M4 18h10" />
        </svg>
        {{
          $t('AI_AGENT.FOLLOW_UPS.CARD.CADENCE_BADGE', {
            count: rule.steps.length + 1,
          })
        }}
      </span>
      <!-- Auto-parada: respondeu / (re)agendou -->
      <span
        v-if="rule.stop_on_reply || rule.stop_on_booking"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
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
          <rect x="3" y="3" width="18" height="18" rx="2" />
          <path d="M9 9h6v6H9z" />
        </svg>
        {{ $t('AI_AGENT.FOLLOW_UPS.CARD.AUTO_STOP') }}
      </span>
      <!-- Template aprovado configurado (fallback fora da janela de 24h) -->
      <span
        v-if="rule.cloud_template_name"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
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
            d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
          />
        </svg>
        {{ $t('AI_AGENT.FOLLOW_UPS.CARD.HAS_TEMPLATE') }}
      </span>
      <span
        v-if="appliesBadge"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md font-medium"
        :style="{ color: appliesBadge.color, backgroundColor: appliesBadge.bg }"
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
          <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
          <circle cx="9" cy="7" r="4" />
          <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
          <path d="M16 3.13a4 4 0 0 1 0 7.75" />
        </svg>
        {{ $t('AI_AGENT.FOLLOW_UPS.CARD.ONLY_BADGE_PREFIX') }}
        {{ appliesBadge.text }}
      </span>
    </div>

    <!-- Actions -->
    <div
      class="flex items-center gap-1 -mx-1.5 -mb-1.5 pt-3 border-t border-n-weak mt-auto"
    >
      <button
        type="button"
        class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
        @click="$emit('toggle', rule)"
      >
        <svg
          v-if="rule.enabled"
          class="w-3.5 h-3.5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <rect x="6" y="4" width="4" height="16" rx="1" />
          <rect x="14" y="4" width="4" height="16" rx="1" />
        </svg>
        <svg
          v-else
          class="w-3.5 h-3.5"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
          stroke-linecap="round"
          stroke-linejoin="round"
        >
          <polygon points="6 3 20 12 6 21 6 3" />
        </svg>
        {{
          rule.enabled
            ? $t('AI_AGENT.FOLLOW_UPS.CARD.ACTION_PAUSE')
            : $t('AI_AGENT.FOLLOW_UPS.CARD.ACTION_RESUME')
        }}
      </button>
      <button
        type="button"
        class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors"
        @click="$emit('edit', rule)"
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
            d="M21.174 6.812a1 1 0 0 0-3.986-3.987L3.842 16.174a2 2 0 0 0-.5.83l-1.321 4.352a.5.5 0 0 0 .623.622l4.353-1.32a2 2 0 0 0 .83-.497z"
          />
        </svg>
        {{ $t('AI_AGENT.FOLLOW_UPS.CARD.ACTION_EDIT') }}
      </button>
      <button
        type="button"
        class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-ruby-600 hover:bg-ruby-100 rounded-lg transition-colors"
        @click="$emit('delete', rule)"
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
        {{ $t('AI_AGENT.FOLLOW_UPS.CARD.ACTION_DELETE') }}
      </button>
    </div>
  </article>
</template>
