<script setup>
// FE-4 (auditoria 2026-05-18): extraído do Index.vue (516 LOC).
// UX-fix 2026-05-19/20:
//   - Remove pill `target_label` quando target_type='disabled'
//   - 3 botões agora são BeclinicButton com variants distintas
//   - Contraste de card desativado: bg-n-alpha-1 + título mais cinza
//   - Callout "Configure destino" quando sem destino
//   - Padding/altura compactados (p-4, sem min-h-[3.9em])
//   - Status badge "Ativo/Desativado" agora se refere SÓ ao template
//     (config da clínica). Detector ganha texto distinto ("Pronto
//     pra disparar" / "Detector em breve") pra eliminar confusão
//     visual de 2 "Ativo" no mesmo card.
//   - Tooltip moderno (<Tooltip>) em TODOS os badges + botões
//     explicando o que cada um significa.
// FE-16/17 (i18n 2026-05-19): strings em `AI_AGENT.TEMPLATES.*`.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import Badge from '@plugins/beclinic_core/frontend/components/Badge.vue';

const props = defineProps({
  template: { type: Object, required: true },
});

defineEmits(['edit', 'toggle', 'reset', 'configure']);

const { t } = useI18n();

// Mapeia color string → cores hex (Tailwind JIT não pega classe dinâmica).
const COLOR_MAP = {
  sky:     { bg: '#e0f2fe', fg: '#0284c7' },
  amber:   { bg: '#fef3c7', fg: '#d97706' },
  rose:    { bg: '#ffe4e6', fg: '#e11d48' },
  red:     { bg: '#fee2e2', fg: '#dc2626' },
  orange:  { bg: '#ffedd5', fg: '#ea580c' },
  slate:   { bg: '#f1f5f9', fg: '#475569' },
  emerald: { bg: '#d1fae5', fg: '#059669' },
  cyan:    { bg: '#cffafe', fg: '#0891b2' },
  violet:  { bg: '#ede9fe', fg: '#7c3aed' },
};

const colorFor = name => COLOR_MAP[name] || COLOR_MAP.slate;

// Texto do detector intencionalmente diferente de "Ativo"/"Desativado"
// usado no status do template — evita 2 "Ativo" no mesmo card. Cada
// badge agora tem tooltip explicando o que significa.
const detectorBadge = status => {
  if (status === 'active' || status === ':active') {
    return {
      text: t('AI_AGENT.TEMPLATES.CARD.DETECTOR_READY'),
      tooltip: t('AI_AGENT.TEMPLATES.CARD.DETECTOR_READY_TOOLTIP'),
      intent: 'info', // azul sutil (faded) — "tecnologia pronta"
    };
  }
  return {
    text: t('AI_AGENT.TEMPLATES.CARD.DETECTOR_SOON'),
    tooltip: t('AI_AGENT.TEMPLATES.CARD.DETECTOR_SOON_TOOLTIP'),
    intent: 'warning', // amber sutil — "ainda não disponível"
  };
};

const colorTokens = computed(() => colorFor(props.template.color));
const badge = computed(() => detectorBadge(props.template.detector_status));
const isDisabled = computed(() => props.template.target_type === 'disabled');
const isActive = computed(() => props.template.enabled && !isDisabled.value);

const statusTooltip = computed(() =>
  isActive.value
    ? t('AI_AGENT.TEMPLATES.CARD.STATUS_ACTIVE_TOOLTIP')
    : t('AI_AGENT.TEMPLATES.CARD.STATUS_DISABLED_TOOLTIP')
);

const targetTooltip = computed(() =>
  t('AI_AGENT.TEMPLATES.CARD.TARGET_TOOLTIP', { target: props.template.target_label })
);
</script>

<template>
  <article
    class="group relative rounded-2xl border p-4 flex flex-col transition-all"
    :class="
      isActive
        ? 'bg-n-solid-1 border-n-weak hover:border-n-strong hover:shadow-md'
        : 'bg-n-alpha-1 border-n-weak hover:border-n-slate-7'
    "
  >
    <!-- Top: ícone + título + status -->
    <div class="flex items-start justify-between gap-3 mb-3">
      <div class="flex items-start gap-3 min-w-0 flex-1">
        <div
          class="shrink-0 flex items-center justify-center w-10 h-10 rounded-xl"
          :style="{ backgroundColor: colorTokens.bg }"
        >
          <svg class="w-5 h-5" :style="{ color: colorTokens.fg }" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M12 2v4M12 18v4M4.93 4.93l2.83 2.83M16.24 16.24l2.83 2.83M2 12h4M18 12h4M4.93 19.07l2.83-2.83M16.24 7.76l2.83-2.83"/>
          </svg>
        </div>
        <div class="min-w-0 flex-1">
          <h3
            class="text-base font-semibold truncate leading-tight"
            :class="isActive ? 'text-n-slate-12' : 'text-n-slate-11'"
          >
            {{ template.event_label }}
          </h3>
          <p class="text-xs text-n-slate-10 mt-0.5 line-clamp-2 leading-relaxed">
            {{ template.event_description }}
          </p>
        </div>
      </div>
      <!-- Status do TEMPLATE (config da clínica). Badge sutil
           (variant=faded default) — verde quando ativo, neutro quando
           pausado. Componente reutilizável do beclinic_core resolve
           bug de Tailwind JIT purgar `emerald` (CSS é hard-coded). -->
      <Tooltip :label="statusTooltip" multiline>
        <span class="cursor-help shrink-0">
          <Badge
            v-if="isActive"
            :label="$t('AI_AGENT.TEMPLATES.CARD.STATUS_ACTIVE')"
            intent="success"
            icon="i-lucide-check-circle-2"
          />
          <Badge
            v-else
            :label="$t('AI_AGENT.TEMPLATES.CARD.STATUS_DISABLED')"
            intent="neutral"
          />
        </span>
      </Tooltip>
    </div>

    <!-- Pills com tooltip explicativo:
         - target_label SÓ renderiza quando tem destino real
         - detector badge: info (azul sutil) ou warning (amber sutil) -->
    <div class="flex flex-wrap items-center gap-2 mb-3">
      <Tooltip v-if="!isDisabled" :label="targetTooltip" multiline>
        <span class="cursor-help">
          <Badge
            :label="template.target_label"
            intent="neutral"
            icon="i-lucide-message-square"
          />
        </span>
      </Tooltip>
      <Tooltip :label="badge.tooltip" multiline>
        <span class="cursor-help">
          <Badge :label="badge.text" :intent="badge.intent" />
        </span>
      </Tooltip>
    </div>

    <!-- Callout "Configure destino" quando template ainda não tem destino.
         Substitui o body preview pra deixar claro o próximo passo. -->
    <div
      v-if="isDisabled"
      class="flex items-start gap-3 p-3 mb-3 rounded-lg border border-dashed border-n-slate-7 bg-n-alpha-1"
    >
      <svg class="w-4 h-4 mt-0.5 shrink-0 text-n-slate-10" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <circle cx="12" cy="12" r="10"/>
        <line x1="12" y1="8" x2="12" y2="12"/>
        <line x1="12" y1="16" x2="12.01" y2="16"/>
      </svg>
      <div class="flex-1 min-w-0">
        <p class="text-xs text-n-slate-11 leading-relaxed mb-2">
          {{ $t('AI_AGENT.TEMPLATES.CARD.NO_DESTINATION_HINT') }}
        </p>
        <BeclinicButton
          :label="$t('AI_AGENT.TEMPLATES.CARD.CONFIGURE_DESTINATION')"
          variant="solid"
          color="blue"
          size="xs"
          @click="$emit('configure', template)"
        />
      </div>
    </div>

    <!-- Body preview (apenas quando tem destino configurado) -->
    <p
      v-else
      class="text-sm text-n-slate-11 leading-relaxed line-clamp-3 mb-3 flex-1 whitespace-pre-line"
    >
      {{ template.body }}
    </p>

    <!-- Actions: hierarquia visual clara + tooltip em cada ação
         explicando o efeito (`Ativar` ≠ óbvio fora de contexto). -->
    <div class="flex items-center gap-2 pt-3 border-t border-n-weak mt-auto">
      <Tooltip
        v-if="!isDisabled"
        :label="template.enabled ? $t('AI_AGENT.TEMPLATES.CARD.ACTION_PAUSE_TOOLTIP') : $t('AI_AGENT.TEMPLATES.CARD.ACTION_RESUME_TOOLTIP')"
        multiline
        class="flex-1"
      >
        <BeclinicButton
          :label="template.enabled ? $t('AI_AGENT.TEMPLATES.CARD.ACTION_PAUSE') : $t('AI_AGENT.TEMPLATES.CARD.ACTION_RESUME')"
          :icon="template.enabled ? 'i-lucide-pause' : 'i-lucide-play'"
          :variant="template.enabled ? 'outline' : 'solid'"
          :color="template.enabled ? 'amber' : 'teal'"
          size="xs"
          class="w-full"
          @click="$emit('toggle', template)"
        />
      </Tooltip>
      <Tooltip :label="$t('AI_AGENT.TEMPLATES.CARD.ACTION_EDIT_TOOLTIP')" multiline class="flex-1">
        <BeclinicButton
          :label="$t('AI_AGENT.TEMPLATES.CARD.ACTION_EDIT')"
          icon="i-lucide-pencil"
          variant="outline"
          color="slate"
          size="xs"
          class="w-full"
          @click="$emit('edit', template)"
        />
      </Tooltip>
      <Tooltip :label="$t('AI_AGENT.TEMPLATES.CARD.ACTION_RESET_TITLE')" multiline>
        <BeclinicButton
          icon="i-lucide-rotate-ccw"
          variant="ghost"
          color="slate"
          size="xs"
          @click="$emit('reset', template)"
        />
      </Tooltip>
    </div>
  </article>
</template>
