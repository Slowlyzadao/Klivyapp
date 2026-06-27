<script setup>
// Aba "System Message" da Bea. O system message é POR CONTA: cada clínica
// edita o seu (congelado). Vazio = herda o default global do super admin (a Bea
// nunca roda sem prompt). "Restaurar padrão" recarrega o default no editor (só
// persiste ao Salvar — reversível até lá). Backend gateia por captain.manage_settings.
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const uiFlags = computed(() => store.getters['aiAgentSystemPrompt/getUIFlags']);
const savedContent = computed(
  () => store.getters['aiAgentSystemPrompt/getContent']
);
const defaultPrompt = computed(
  () => store.getters['aiAgentSystemPrompt/getDefault']
);
const usingDefault = computed(
  () => store.getters['aiAgentSystemPrompt/getUsingDefault']
);

// Rascunho local do textarea. Quando a conta ainda usa o default, pré-preenche
// com o default (o que a Bea de fato segue) pra a pessoa ver/editar a partir dele.
const draft = ref('');

const syncDraftFromStore = () => {
  draft.value = savedContent.value || defaultPrompt.value || '';
};

const isDirty = computed(
  () => draft.value !== (savedContent.value || defaultPrompt.value || '')
);
const charCount = computed(() => draft.value.length);

const load = async () => {
  await store.dispatch('aiAgentSystemPrompt/fetch');
  syncDraftFromStore();
};

const handleSave = async () => {
  try {
    await store.dispatch('aiAgentSystemPrompt/save', draft.value);
    syncDraftFromStore();
    useAlert(t('AI_AGENT.SYSTEM_PROMPT.SAVED'));
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

// Recarrega o default no editor (não salva — revisar e clicar em Salvar).
const handleRestoreDefault = () => {
  draft.value = defaultPrompt.value || '';
  useAlert(t('AI_AGENT.SYSTEM_PROMPT.RESTORED_INTO_EDITOR'));
};

const handleDiscard = () => syncDraftFromStore();

// MT-19 — account-switch: zera e recarrega pra não vazar prompt entre contas.
watch(
  () => Number(route.params.accountId),
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      store.dispatch('aiAgentSystemPrompt/reset');
      load();
    }
  }
);

onMounted(load);
</script>

<template>
  <div class="flex flex-col h-full w-full bg-n-background overflow-hidden">
    <header class="px-8 pt-8 pb-4 shrink-0">
      <h1 class="text-xl font-semibold text-n-slate-12">
        {{ $t('AI_AGENT.SYSTEM_PROMPT.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11 max-w-3xl">
        {{ $t('AI_AGENT.SYSTEM_PROMPT.DESCRIPTION') }}
      </p>
    </header>

    <main class="flex-1 overflow-y-auto">
      <div class="px-8 pb-8 w-full max-w-4xl">
        <!-- Loading -->
        <div
          v-if="uiFlags.isFetching && !draft"
          class="flex items-center gap-3 py-20 text-sm text-n-slate-10"
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
          {{ $t('AI_AGENT.SYSTEM_PROMPT.LOADING') }}
        </div>

        <template v-else>
          <!-- Origem atual: padrão herdado x próprio da conta -->
          <div
            class="mb-3 flex items-center gap-2 rounded-lg px-3 py-2 text-xs"
            :class="
              usingDefault
                ? 'bg-amber-50 text-amber-800 dark:bg-amber-900/20 dark:text-amber-300'
                : 'bg-teal-50 text-teal-800 dark:bg-teal-900/20 dark:text-teal-300'
            "
          >
            <span
              class="size-4 shrink-0"
              :class="usingDefault ? 'i-lucide-info' : 'i-lucide-check-circle'"
            />
            {{
              usingDefault
                ? $t('AI_AGENT.SYSTEM_PROMPT.USING_DEFAULT')
                : $t('AI_AGENT.SYSTEM_PROMPT.HAS_OWN')
            }}
          </div>

          <textarea
            v-model="draft"
            rows="22"
            spellcheck="false"
            class="w-full resize-y rounded-xl border border-n-weak bg-n-solid-1 p-4 font-mono text-[13px] leading-relaxed text-n-slate-12 outline-none focus:border-woot-500"
            :placeholder="$t('AI_AGENT.SYSTEM_PROMPT.PLACEHOLDER')"
          />

          <div class="mt-2 flex items-center justify-between">
            <span class="text-xs text-n-slate-10">
              {{ $t('AI_AGENT.SYSTEM_PROMPT.CHARS', { count: charCount }) }}
            </span>
          </div>

          <div class="mt-4 flex flex-wrap items-center gap-3">
            <BeclinicButton
              :label="$t('AI_AGENT.SYSTEM_PROMPT.SAVE')"
              icon="i-lucide-save"
              variant="solid"
              color="blue"
              size="sm"
              :is-loading="uiFlags.isSaving"
              :disabled="!isDirty || !draft.trim()"
              @click="handleSave"
            />
            <BeclinicButton
              v-if="isDirty"
              :label="$t('AI_AGENT.SYSTEM_PROMPT.DISCARD')"
              variant="outline"
              color="slate"
              size="sm"
              @click="handleDiscard"
            />
            <BeclinicButton
              class="ml-auto"
              :label="$t('AI_AGENT.SYSTEM_PROMPT.RESTORE')"
              icon="i-lucide-rotate-ccw"
              variant="outline"
              color="slate"
              size="sm"
              @click="handleRestoreDefault"
            />
          </div>
        </template>
      </div>
    </main>
  </div>
</template>
