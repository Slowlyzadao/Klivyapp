<script setup>
// Aba "Vouchers" (lançamento) da Bea. Modo voucher: a Bea SÓ responde quem
// chegou por um voucher — a FOTO do voucher (sempre ativa) OU um dos
// textos-gatilho do QR (lista abaixo, o usuário adiciona quantos quiser).
// Quem chega de outro jeito fica sem resposta. Backend gateia por captain.
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const store = useStore();
const route = useRoute();
const { t } = useI18n();

const uiFlags = computed(
  () => store.getters['aiAgentVoucherConfig/getUIFlags']
);
const savedEnabled = computed(
  () => store.getters['aiAgentVoucherConfig/getEnabled']
);
const savedTriggers = computed(
  () => store.getters['aiAgentVoucherConfig/getTriggers']
);

// Rascunho local
const localEnabled = ref(false);
const localTriggers = ref(['']);

const syncFromStore = () => {
  localEnabled.value = savedEnabled.value;
  // sempre deixa pelo menos uma caixa pra digitar
  const list = [...savedTriggers.value];
  localTriggers.value = list.length ? list : [''];
};

const cleanedTriggers = () =>
  localTriggers.value.map(s => s.trim()).filter(Boolean);

const isDirty = computed(() => {
  if (localEnabled.value !== savedEnabled.value) return true;
  return (
    JSON.stringify(cleanedTriggers()) !== JSON.stringify(savedTriggers.value)
  );
});

const addTrigger = () => localTriggers.value.push('');
const removeTrigger = index => {
  localTriggers.value.splice(index, 1);
  if (!localTriggers.value.length) localTriggers.value = [''];
};

const load = async () => {
  await store.dispatch('aiAgentVoucherConfig/fetch');
  syncFromStore();
};

const handleSave = async () => {
  try {
    await store.dispatch('aiAgentVoucherConfig/save', {
      enabled: localEnabled.value,
      triggers: cleanedTriggers(),
    });
    syncFromStore();
    useAlert(t('AI_AGENT.VOUCHERS.SAVED'));
  } catch (e) {
    /* throwErrorMessage já dispara o toast */
  }
};

const handleDiscard = () => syncFromStore();

watch(
  () => Number(route.params.accountId),
  (newId, oldId) => {
    if (oldId && newId !== oldId) {
      store.dispatch('aiAgentVoucherConfig/reset');
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
        {{ $t('AI_AGENT.VOUCHERS.TITLE') }}
      </h1>
      <p class="mt-1 text-sm text-n-slate-11 max-w-3xl">
        {{ $t('AI_AGENT.VOUCHERS.DESCRIPTION') }}
      </p>
    </header>

    <main class="flex-1 overflow-y-auto">
      <div class="px-8 pb-8 w-full max-w-3xl">
        <div v-if="uiFlags.isFetching" class="py-20 text-sm text-n-slate-10">
          {{ $t('AI_AGENT.VOUCHERS.LOADING') }}
        </div>

        <template v-else>
          <!-- Toggle modo voucher -->
          <label
            class="flex items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-4 cursor-pointer"
          >
            <input
              v-model="localEnabled"
              type="checkbox"
              class="mt-0.5 size-4 accent-n-brand"
            />
            <span class="flex flex-col">
              <span class="text-sm font-medium text-n-slate-12">
                {{ $t('AI_AGENT.VOUCHERS.TOGGLE_LABEL') }}
              </span>
              <span class="text-xs text-n-slate-11 mt-0.5">
                {{ $t('AI_AGENT.VOUCHERS.TOGGLE_HINT') }}
              </span>
            </span>
          </label>

          <!-- Como funciona -->
          <div
            class="mt-4 rounded-lg bg-n-slate-2 px-3 py-2.5 text-xs text-n-slate-11 leading-relaxed"
          >
            {{ $t('AI_AGENT.VOUCHERS.HOW_IT_WORKS') }}
          </div>

          <!-- Lista de textos-gatilho -->
          <div class="mt-6">
            <h2 class="text-sm font-semibold text-n-slate-12">
              {{ $t('AI_AGENT.VOUCHERS.TRIGGERS_TITLE') }}
            </h2>
            <p class="text-xs text-n-slate-11 mt-0.5 mb-3">
              {{ $t('AI_AGENT.VOUCHERS.TRIGGERS_HINT') }}
            </p>

            <div class="flex flex-col gap-2">
              <div
                v-for="(trigger, index) in localTriggers"
                :key="index"
                class="flex items-center gap-2"
              >
                <input
                  v-model="localTriggers[index]"
                  type="text"
                  :placeholder="$t('AI_AGENT.VOUCHERS.TRIGGER_PLACEHOLDER')"
                  class="flex-1 rounded-lg border border-n-weak bg-n-solid-1 px-3 py-2 text-sm text-n-slate-12 placeholder:text-n-slate-9 focus:border-n-brand focus:outline-none"
                />
                <button
                  type="button"
                  class="shrink-0 size-8 rounded-lg text-n-slate-10 hover:bg-n-slate-3 hover:text-n-ruby-9 flex items-center justify-center"
                  :title="$t('AI_AGENT.VOUCHERS.REMOVE')"
                  @click="removeTrigger(index)"
                >
                  <span class="i-lucide-trash-2 size-4" />
                </button>
              </div>
            </div>

            <button
              type="button"
              class="mt-3 inline-flex items-center gap-1.5 text-sm font-medium text-n-brand hover:underline"
              @click="addTrigger"
            >
              <span class="i-lucide-plus size-4" />
              {{ $t('AI_AGENT.VOUCHERS.ADD_TRIGGER') }}
            </button>
          </div>

          <!-- Ações -->
          <div class="mt-8 flex items-center gap-3">
            <BeclinicButton
              :label="$t('AI_AGENT.VOUCHERS.SAVE')"
              icon="i-lucide-save"
              variant="solid"
              color="blue"
              size="sm"
              :is-loading="uiFlags.isSaving"
              :disabled="!isDirty || uiFlags.isSaving"
              @click="handleSave"
            />
            <BeclinicButton
              v-if="isDirty"
              :label="$t('AI_AGENT.VOUCHERS.DISCARD')"
              variant="outline"
              color="slate"
              size="sm"
              :disabled="uiFlags.isSaving"
              @click="handleDiscard"
            />
          </div>
        </template>
      </div>
    </main>
  </div>
</template>
