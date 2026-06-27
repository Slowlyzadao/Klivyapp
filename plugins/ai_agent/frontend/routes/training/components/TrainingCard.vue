<script setup>
// Card de uma conversa de treinamento. Mostra o status do pipeline
// (processando/concluído/falha) e, quando pronto, as estatísticas do parser.
// Constants de status duplicadas inline por design (cores via :style — o JIT
// do Tailwind não pega classe vinda de variável).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  training: { type: Object, required: true },
});

defineEmits(['view', 'delete', 'selectClinic']);

const { t } = useI18n();

const STATUS_META = {
  pending: { color: '#64748b', bgColor: '#f1f5f9', spin: true },
  extracting: { color: '#0284c7', bgColor: '#e0f2fe', spin: true },
  transcribing: { color: '#0284c7', bgColor: '#e0f2fe', spin: true },
  extracting_faq: { color: '#0284c7', bgColor: '#e0f2fe', spin: true },
  completed: { color: '#059669', bgColor: '#d1fae5', spin: false },
  failed: { color: '#dc2626', bgColor: '#fee2e2', spin: false },
  awaiting_clinic: { color: '#d97706', bgColor: '#fef3c7', spin: false },
};

// Labels com chaves i18n estáticas (evita key dinâmica no t()).
const STATUS_LABELS = computed(() => ({
  pending: t('AI_AGENT.TRAINING.STATUS.PENDING'),
  extracting: t('AI_AGENT.TRAINING.STATUS.EXTRACTING'),
  transcribing: t('AI_AGENT.TRAINING.STATUS.TRANSCRIBING'),
  extracting_faq: t('AI_AGENT.TRAINING.STATUS.EXTRACTING_FAQ'),
  completed: t('AI_AGENT.TRAINING.STATUS.COMPLETED'),
  failed: t('AI_AGENT.TRAINING.STATUS.FAILED'),
  awaiting_clinic: t('AI_AGENT.TRAINING.STATUS.AWAITING_CLINIC'),
}));

// Durante a transcrição mostra o progresso "X/Y áudios"; senão, hint genérico.
const processingHint = computed(() => {
  if (
    props.training.status === 'transcribing' &&
    props.training.audio_total > 0
  ) {
    return t('AI_AGENT.TRAINING.CARD.TRANSCRIBING_PROGRESS', {
      done: props.training.audio_transcribed,
      total: props.training.audio_total,
    });
  }
  return t('AI_AGENT.TRAINING.CARD.PROCESSING_HINT');
});

const meta = computed(
  () => STATUS_META[props.training.status] || STATUS_META.pending
);
const isCompleted = computed(() => props.training.status === 'completed');
const isFailed = computed(() => props.training.status === 'failed');
const isAwaitingClinic = computed(
  () => props.training.status === 'awaiting_clinic'
);
const statusLabel = computed(
  () => STATUS_LABELS.value[props.training.status] || ''
);
</script>

<template>
  <article
    class="group relative bg-n-solid-1 border border-n-weak rounded-2xl p-5 hover:border-n-strong hover:shadow-md transition-all flex flex-col"
  >
    <!-- Top: ícone + nome + status -->
    <div class="flex items-start justify-between gap-3 mb-3">
      <div class="flex items-start gap-3 min-w-0 flex-1">
        <div
          class="shrink-0 flex items-center justify-center w-10 h-10 rounded-xl"
          :style="{ backgroundColor: meta.bgColor }"
        >
          <svg
            class="w-5 h-5"
            :style="{ color: meta.color }"
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
        </div>
        <div class="min-w-0 flex-1">
          <h3
            class="text-base font-semibold text-n-slate-12 truncate leading-tight"
          >
            {{ training.name }}
          </h3>
          <p
            v-if="training.clinic_sender_name"
            class="text-xs text-n-slate-10 mt-0.5 truncate"
          >
            {{ $t('AI_AGENT.TRAINING.CARD.CLINIC_PREFIX') }}
            {{ training.clinic_sender_name }}
          </p>
        </div>
      </div>
      <span
        class="shrink-0 inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium rounded-md"
        :style="{ color: meta.color, backgroundColor: meta.bgColor }"
      >
        <svg
          v-if="meta.spin"
          class="w-3 h-3 animate-spin"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          stroke-width="2"
        >
          <path d="M21 12a9 9 0 1 1-6.219-8.56" stroke-linecap="round" />
        </svg>
        <span
          v-else
          class="w-1.5 h-1.5 rounded-full"
          :style="{ backgroundColor: meta.color }"
        />
        {{ statusLabel }}
      </span>
    </div>

    <!-- Erro -->
    <p
      v-if="isFailed"
      class="text-sm text-ruby-600 leading-relaxed line-clamp-2 mb-4 flex-1"
    >
      {{ training.error_message }}
    </p>

    <!-- Estatísticas do parser (quando concluído) -->
    <div
      v-else-if="isCompleted"
      class="flex flex-wrap items-center gap-2 mb-4 flex-1 content-start"
    >
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
          <path
            d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"
          />
        </svg>
        {{
          $t('AI_AGENT.TRAINING.CARD.MESSAGES', {
            count: training.message_count,
          })
        }}
      </span>
      <span
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-n-alpha-2 text-n-slate-11"
      >
        {{
          $t('AI_AGENT.TRAINING.CARD.CLINIC_PATIENT', {
            clinic: training.clinic_message_count,
            patient: training.patient_message_count,
          })
        }}
      </span>
      <span
        v-if="training.audio_total > 0"
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
          <path d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z" />
          <path d="M19 10v2a7 7 0 0 1-14 0v-2M12 19v3" />
        </svg>
        {{
          $t('AI_AGENT.TRAINING.CARD.AUDIOS', { count: training.audio_total })
        }}
      </span>
      <span
        v-if="training.faq_count > 0"
        class="inline-flex items-center gap-1.5 px-2.5 py-1 text-xs rounded-md bg-woot-50 text-woot-700 font-medium"
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
          <path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3" />
          <path d="M12 17h.01" />
        </svg>
        {{ $t('AI_AGENT.TRAINING.CARD.FAQS', { count: training.faq_count }) }}
      </span>
    </div>

    <!-- Seleção da clínica (participantes detectados) -->
    <div v-else-if="isAwaitingClinic" class="mb-4 flex-1">
      <p class="text-sm font-medium text-n-slate-12 mb-2">
        {{ $t('AI_AGENT.TRAINING.CARD.SELECT_CLINIC_TITLE') }}
      </p>
      <div class="flex flex-col gap-1.5">
        <button
          v-for="participant in training.participants"
          :key="participant.name"
          type="button"
          class="flex items-center justify-between gap-2 px-3 py-2 text-left text-sm rounded-lg border border-n-weak hover:border-woot-500 hover:bg-woot-50 transition-all"
          @click="$emit('selectClinic', participant.name)"
        >
          <span class="font-medium text-n-slate-12 truncate">
            {{ participant.name }}
          </span>
          <span class="shrink-0 text-xs text-n-slate-10">
            {{
              $t('AI_AGENT.TRAINING.CARD.PARTICIPANT_MSGS', {
                count: participant.count,
              })
            }}
          </span>
        </button>
      </div>
    </div>

    <!-- Processando -->
    <p v-else class="text-sm text-n-slate-10 leading-relaxed mb-4 flex-1">
      {{ processingHint }}
    </p>

    <!-- Ações -->
    <div
      class="flex items-center gap-1 -mx-1.5 -mb-1.5 pt-3 border-t border-n-weak mt-auto"
    >
      <button
        type="button"
        :disabled="!isCompleted"
        class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-n-slate-11 hover:bg-n-alpha-2 rounded-lg transition-colors disabled:opacity-40 disabled:cursor-not-allowed disabled:hover:bg-transparent"
        @click="$emit('view', training)"
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
          <path d="M2 12s3-7 10-7 10 7 10 7-3 7-10 7-10-7-10-7z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
        {{ $t('AI_AGENT.TRAINING.CARD.ACTION_VIEW') }}
      </button>
      <button
        type="button"
        class="flex-1 inline-flex items-center justify-center gap-1.5 px-3 py-2 text-xs font-medium text-ruby-600 hover:bg-ruby-100 rounded-lg transition-colors"
        @click="$emit('delete', training)"
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
        {{ $t('AI_AGENT.TRAINING.CARD.ACTION_DELETE') }}
      </button>
    </div>
  </article>
</template>
