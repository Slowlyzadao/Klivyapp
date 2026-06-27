<script setup>
// Exclusão de conversa(s) de treinamento com DUAS opções: arquivar (só a
// conversa some da lista — FAQs preservadas no RAG) ou remover tudo (conversa
// + FAQs do RAG). Emite `confirm` com o modo escolhido ('conversation' | 'all').
// Serve tanto para 1 conversa (passa `name`) quanto em massa (passa `count` > 0).
import { computed } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  name: { type: String, default: '' },
  count: { type: Number, default: 0 },
  loading: { type: Boolean, default: false },
});

const emit = defineEmits(['update:show', 'confirm']);

const isBulk = computed(() => props.count > 0);

const close = () => emit('update:show', false);
const confirm = mode => emit('confirm', mode);
</script>

<template>
  <Teleport to="body">
    <Transition name="fade">
      <div
        v-if="show"
        class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
        @click.self="close"
      >
        <div
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-md overflow-hidden"
          @click.stop
        >
          <div class="px-6 pt-6 pb-1">
            <h2 class="text-lg font-semibold text-n-slate-12">
              {{
                isBulk
                  ? $t('AI_AGENT.TRAINING.BULK_DELETE_TITLE')
                  : $t('AI_AGENT.TRAINING.DELETE_TITLE')
              }}
            </h2>
            <p class="text-sm text-n-slate-10 mt-1">
              {{
                isBulk
                  ? $t('AI_AGENT.TRAINING.BULK_DELETE_CHOICE', { count })
                  : $t('AI_AGENT.TRAINING.DELETE_CHOICE', { name })
              }}
            </p>
          </div>

          <div class="px-6 py-4 space-y-2.5">
            <!-- Só a(s) conversa(s) (arquiva) -->
            <button
              type="button"
              :disabled="loading"
              class="w-full text-left px-4 py-3 rounded-xl border border-n-weak hover:border-woot-500 hover:bg-woot-50 transition-all disabled:opacity-50"
              @click="confirm('conversation')"
            >
              <span class="block text-sm font-medium text-n-slate-12">
                {{
                  isBulk
                    ? $t('AI_AGENT.TRAINING.BULK_DELETE_ONLY_CONVERSATION')
                    : $t('AI_AGENT.TRAINING.DELETE_ONLY_CONVERSATION')
                }}
              </span>
              <span class="block text-xs text-n-slate-10 mt-0.5">
                {{
                  isBulk
                    ? $t('AI_AGENT.TRAINING.BULK_DELETE_ONLY_CONVERSATION_HINT')
                    : $t('AI_AGENT.TRAINING.DELETE_ONLY_CONVERSATION_HINT')
                }}
              </span>
            </button>

            <!-- Conversa(s) + FAQs (remove do RAG) -->
            <button
              type="button"
              :disabled="loading"
              class="w-full text-left px-4 py-3 rounded-xl border border-n-weak hover:bg-ruby-100 transition-all disabled:opacity-50"
              @click="confirm('all')"
            >
              <span class="block text-sm font-medium text-ruby-600">
                {{
                  isBulk
                    ? $t('AI_AGENT.TRAINING.BULK_DELETE_WITH_FAQS')
                    : $t('AI_AGENT.TRAINING.DELETE_WITH_FAQS')
                }}
              </span>
              <span class="block text-xs text-n-slate-10 mt-0.5">
                {{
                  isBulk
                    ? $t('AI_AGENT.TRAINING.BULK_DELETE_WITH_FAQS_HINT')
                    : $t('AI_AGENT.TRAINING.DELETE_WITH_FAQS_HINT')
                }}
              </span>
            </button>
          </div>

          <div class="px-6 py-4 border-t border-n-weak flex justify-end">
            <BeclinicButton
              :label="$t('AI_AGENT.TRAINING.FAQS_TAB.CANCEL')"
              variant="outline"
              color="slate"
              :disabled="loading"
              @click="close"
            />
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>

<style scoped>
.fade-enter-active,
.fade-leave-active {
  transition: opacity 0.2s ease;
}
.fade-enter-from,
.fade-leave-to {
  opacity: 0;
}
</style>
