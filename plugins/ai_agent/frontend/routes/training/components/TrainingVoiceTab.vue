<script setup>
// Aba "Tom de voz" da Bea. Gera o perfil de estilo a partir das conversas do
// Treinamento (rascunho), deixa revisar/editar (onde nomes residuais são
// limpos) e aprovar — aí vira o perfil ATIVO e a Bea passa a falar no tom.
import { ref, computed, watch, onMounted, onUnmounted } from 'vue';
import { useStore } from 'vuex';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import { DRAFT_PROCESSING_STATUS } from '@plugins/ai_agent/frontend/store/aiAgentStyleProfile';

const store = useStore();

const active = computed(
  () => store.getters['aiAgentStyleProfile/getActive'] || {}
);
const draft = computed(
  () => store.getters['aiAgentStyleProfile/getDraft'] || {}
);
const uiFlags = computed(() => store.getters['aiAgentStyleProfile/getUIFlags']);

const draftStatus = computed(() => draft.value.status);
const isGenerating = computed(
  () =>
    draftStatus.value === DRAFT_PROCESSING_STATUS || uiFlags.value.isGenerating
);
const isReady = computed(() => draftStatus.value === 'ready');
const isFailed = computed(() => draftStatus.value === 'failed');

const hasActive = computed(
  () =>
    ['summary', 'greeting', 'closing'].some(k => active.value[k]) ||
    (active.value.emojis || []).length > 0 ||
    (active.value.examples || []).length > 0
);
const activeEnabled = computed(() => active.value.enabled === true);

// --- Rascunho editável ---
const blankForm = () => ({
  summary: '',
  greeting: '',
  closing: '',
  emojis: [],
  expressions: [],
  examples: [],
});
const form = ref(blankForm());

const loadForm = () => {
  const d = draft.value || {};
  form.value = {
    summary: d.summary || '',
    greeting: d.greeting || '',
    closing: d.closing || '',
    emojis: [...(d.emojis || [])],
    expressions: [...(d.expressions || [])],
    examples: (d.examples || []).map(e => ({
      paciente: e.paciente || '',
      clinica: e.clinica || '',
    })),
  };
};

const removeEmoji = i => form.value.emojis.splice(i, 1);
const removeExpression = i => form.value.expressions.splice(i, 1);
const removeExample = i => form.value.examples.splice(i, 1);

// Glyph do botão de remover chip (variável, não string crua no template).
const removeGlyph = '✕';

// --- Polling do status da geração ---
let pollTimer = null;
let pollCount = 0;
const POLL_INTERVAL = 3000;
// Teto de ~6min: se o status não sair de 'generating' (ex.: worker morto antes
// do status terminal), para o polling e mostra o estado "travou" com retry, em
// vez de spinner infinito. O backend trata o 'generating' órfão como stale.
const MAX_POLLS = 120;
const stalled = ref(false);
const stopPolling = () => {
  if (pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
};
const startPolling = () => {
  if (pollTimer) return;
  pollCount = 0;
  stalled.value = false;
  pollTimer = setInterval(() => {
    if (draftStatus.value !== DRAFT_PROCESSING_STATUS) {
      stopPolling();
      return;
    }
    pollCount += 1;
    if (pollCount >= MAX_POLLS) {
      stopPolling();
      stalled.value = true;
      return;
    }
    store.dispatch('aiAgentStyleProfile/refresh').catch(() => {});
  }, POLL_INTERVAL);
};

watch(draftStatus, status => {
  if (status === DRAFT_PROCESSING_STATUS) startPolling();
  else stopPolling();
  if (status === 'ready') loadForm();
  // Store zerada (account-switch / reset) → limpa o form local pra não reter
  // edição não-aprovada de outra conta.
  else if (!status) form.value = blankForm();
});

// --- Ações ---
const generate = async () => {
  stalled.value = false;
  try {
    await store.dispatch('aiAgentStyleProfile/generate');
    startPolling();
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

const approve = async () => {
  try {
    // approve:true → promove o rascunho pro ativo e o consome.
    await store.dispatch('aiAgentStyleProfile/save', {
      profile: { ...form.value, enabled: true },
      approve: true,
    });
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

const toggleEnabled = async () => {
  try {
    // Sem approve → só liga/desliga o ativo; NÃO consome um rascunho pendente.
    await store.dispatch('aiAgentStyleProfile/save', {
      profile: {
        summary: active.value.summary || '',
        greeting: active.value.greeting || '',
        closing: active.value.closing || '',
        emojis: active.value.emojis || [],
        expressions: active.value.expressions || [],
        examples: active.value.examples || [],
        enabled: !activeEnabled.value,
      },
    });
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

onMounted(async () => {
  await store.dispatch('aiAgentStyleProfile/fetch');
  if (draftStatus.value === DRAFT_PROCESSING_STATUS) startPolling();
  if (draftStatus.value === 'ready') loadForm();
});

onUnmounted(stopPolling);
</script>

<template>
  <div class="max-w-3xl">
    <p class="text-sm text-n-slate-11 mb-6 leading-relaxed">
      {{ $t('AI_AGENT.TRAINING.VOICE.DESCRIPTION') }}
    </p>

    <!-- Tom ativo -->
    <div class="rounded-xl border border-n-weak bg-n-alpha-1 p-5 mb-6">
      <div class="flex items-start justify-between gap-4">
        <div class="min-w-0">
          <h3 class="text-sm font-semibold text-n-slate-12 mb-1">
            {{ $t('AI_AGENT.TRAINING.VOICE.ACTIVE_TITLE') }}
          </h3>
          <p v-if="!hasActive" class="text-sm text-n-slate-10">
            {{ $t('AI_AGENT.TRAINING.VOICE.ACTIVE_EMPTY') }}
          </p>
          <template v-else>
            <p
              class="text-sm font-medium"
              :class="activeEnabled ? 'text-emerald-600' : 'text-n-slate-10'"
            >
              {{
                activeEnabled
                  ? $t('AI_AGENT.TRAINING.VOICE.ACTIVE_ON')
                  : $t('AI_AGENT.TRAINING.VOICE.ACTIVE_OFF')
              }}
            </p>
            <p
              v-if="active.greeting"
              class="text-sm text-n-slate-11 mt-1.5 italic"
            >
              {{ active.greeting }}
            </p>
            <div v-if="(active.emojis || []).length" class="mt-1.5 text-lg">
              {{ (active.emojis || []).join(' ') }}
            </div>
          </template>
        </div>
        <BeclinicButton
          v-if="hasActive"
          :label="
            activeEnabled
              ? $t('AI_AGENT.TRAINING.VOICE.DISABLE')
              : $t('AI_AGENT.TRAINING.VOICE.ENABLE')
          "
          :variant="activeEnabled ? 'outline' : 'solid'"
          :color="activeEnabled ? 'slate' : 'teal'"
          size="sm"
          :is-loading="uiFlags.isSaving"
          @click="toggleEnabled"
        />
      </div>
    </div>

    <!-- Gerar / estados -->
    <div
      v-if="isGenerating && !stalled"
      class="flex items-center gap-3 text-sm text-n-slate-11 py-8"
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
      {{ $t('AI_AGENT.TRAINING.VOICE.GENERATING') }}
    </div>

    <div v-else-if="isFailed || stalled" class="py-6">
      <p class="text-sm text-ruby-600 mb-3">
        {{
          stalled
            ? $t('AI_AGENT.TRAINING.VOICE.STALLED')
            : draft.error || $t('AI_AGENT.TRAINING.VOICE.FAILED')
        }}
      </p>
      <BeclinicButton
        :label="$t('AI_AGENT.TRAINING.VOICE.RETRY')"
        icon="i-lucide-sparkles"
        variant="solid"
        color="teal"
        size="sm"
        @click="generate"
      />
    </div>

    <!-- Rascunho pronto: revisar + editar -->
    <div v-else-if="isReady">
      <div class="flex items-center justify-between gap-3 mb-1">
        <h3 class="text-sm font-semibold text-n-slate-12">
          {{ $t('AI_AGENT.TRAINING.VOICE.DRAFT_TITLE') }}
        </h3>
        <span v-if="draft.sample_count" class="text-xs text-n-slate-9 shrink-0">
          {{
            $t('AI_AGENT.TRAINING.VOICE.META', {
              messages: draft.sample_count,
              conversations: draft.source_conversation_count,
            })
          }}
        </span>
      </div>
      <p class="text-xs text-n-slate-10 mb-5 leading-relaxed">
        {{ $t('AI_AGENT.TRAINING.VOICE.DRAFT_HINT') }}
      </p>

      <div class="space-y-5">
        <label class="block">
          <span class="text-xs font-medium text-n-slate-11">{{
            $t('AI_AGENT.TRAINING.VOICE.FIELD_SUMMARY')
          }}</span>
          <textarea
            v-model="form.summary"
            rows="2"
            class="mt-1 w-full text-sm rounded-lg border border-n-weak bg-n-background px-3 py-2 resize-y focus:border-woot-500 focus:outline-none"
          />
        </label>

        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <label class="block">
            <span class="text-xs font-medium text-n-slate-11">{{
              $t('AI_AGENT.TRAINING.VOICE.FIELD_GREETING')
            }}</span>
            <input
              v-model="form.greeting"
              type="text"
              class="mt-1 w-full text-sm rounded-lg border border-n-weak bg-n-background px-3 py-2 focus:border-woot-500 focus:outline-none"
            />
          </label>
          <label class="block">
            <span class="text-xs font-medium text-n-slate-11">{{
              $t('AI_AGENT.TRAINING.VOICE.FIELD_CLOSING')
            }}</span>
            <input
              v-model="form.closing"
              type="text"
              class="mt-1 w-full text-sm rounded-lg border border-n-weak bg-n-background px-3 py-2 focus:border-woot-500 focus:outline-none"
            />
          </label>
        </div>

        <!-- Emojis -->
        <div v-if="form.emojis.length">
          <span class="text-xs font-medium text-n-slate-11">{{
            $t('AI_AGENT.TRAINING.VOICE.FIELD_EMOJIS')
          }}</span>
          <div class="mt-1.5 flex flex-wrap gap-2">
            <span
              v-for="(emoji, i) in form.emojis"
              :key="`emoji-${i}`"
              class="inline-flex items-center gap-1 rounded-full bg-n-alpha-2 px-2.5 py-1 text-base"
            >
              {{ emoji }}
              <button
                type="button"
                class="text-n-slate-9 hover:text-ruby-600 text-xs"
                :aria-label="$t('AI_AGENT.TRAINING.VOICE.REMOVE')"
                @click="removeEmoji(i)"
              >
                {{ removeGlyph }}
              </button>
            </span>
          </div>
        </div>

        <!-- Expressões -->
        <div v-if="form.expressions.length">
          <span class="text-xs font-medium text-n-slate-11">{{
            $t('AI_AGENT.TRAINING.VOICE.FIELD_EXPRESSIONS')
          }}</span>
          <div class="mt-1.5 flex flex-wrap gap-2">
            <span
              v-for="(expr, i) in form.expressions"
              :key="`expr-${i}`"
              class="inline-flex items-center gap-1.5 rounded-full bg-n-alpha-2 px-3 py-1 text-xs text-n-slate-11"
            >
              {{ expr }}
              <button
                type="button"
                class="text-n-slate-9 hover:text-ruby-600"
                :aria-label="$t('AI_AGENT.TRAINING.VOICE.REMOVE')"
                @click="removeExpression(i)"
              >
                {{ removeGlyph }}
              </button>
            </span>
          </div>
        </div>

        <!-- Exemplos -->
        <div>
          <span class="text-xs font-medium text-n-slate-11">{{
            $t('AI_AGENT.TRAINING.VOICE.FIELD_EXAMPLES')
          }}</span>
          <p v-if="!form.examples.length" class="mt-1 text-xs text-n-slate-9">
            {{ $t('AI_AGENT.TRAINING.VOICE.EMPTY_EXAMPLES') }}
          </p>
          <div class="mt-1.5 space-y-2">
            <div
              v-for="(ex, i) in form.examples"
              :key="`ex-${i}`"
              class="rounded-lg border border-n-weak p-3"
            >
              <div class="flex items-start justify-between gap-2">
                <p class="text-xs text-n-slate-10">
                  <span class="font-medium">{{
                    $t('AI_AGENT.TRAINING.VOICE.EXAMPLE_PATIENT')
                  }}</span>
                  {{ ex.paciente }}
                </p>
                <button
                  type="button"
                  class="text-xs text-n-slate-9 hover:text-ruby-600 shrink-0"
                  @click="removeExample(i)"
                >
                  {{ $t('AI_AGENT.TRAINING.VOICE.REMOVE') }}
                </button>
              </div>
              <textarea
                v-model="ex.clinica"
                rows="2"
                class="mt-2 w-full text-sm rounded-md border border-n-weak bg-n-background px-2.5 py-1.5 resize-y focus:border-woot-500 focus:outline-none"
              />
            </div>
          </div>
        </div>
      </div>

      <div class="flex items-center gap-2 mt-6">
        <BeclinicButton
          :label="$t('AI_AGENT.TRAINING.VOICE.APPROVE')"
          icon="i-lucide-check"
          variant="solid"
          color="teal"
          :is-loading="uiFlags.isSaving"
          @click="approve"
        />
        <BeclinicButton
          :label="$t('AI_AGENT.TRAINING.VOICE.REGENERATE')"
          icon="i-lucide-refresh-cw"
          variant="outline"
          color="slate"
          :is-loading="uiFlags.isGenerating"
          @click="generate"
        />
      </div>
    </div>

    <!-- Sem rascunho: CTA de gerar -->
    <div v-else class="py-6">
      <BeclinicButton
        :label="$t('AI_AGENT.TRAINING.VOICE.GENERATE')"
        icon="i-lucide-sparkles"
        variant="solid"
        color="teal"
        :is-loading="uiFlags.isGenerating"
        @click="generate"
      />
    </div>
  </div>
</template>
