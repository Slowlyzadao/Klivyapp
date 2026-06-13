<script setup>
// Revisão e aprovação EM MASSA das FAQs sugeridas de todas as conversas
// concluídas mas ainda não publicadas. Lista tudo de uma vez (com a origem de
// cada FAQ), já com as duplicatas desmarcadas, e publica as selecionadas no RAG
// da Bea num clique. Emite `approve` com os ids ("<conversa>-<índice>") mantidos.
import { ref, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Checkbox from '@plugins/beclinic_core/frontend/components/Checkbox.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  faqs: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
  isApproving: { type: Boolean, default: false },
});

const emit = defineEmits(['update:show', 'approve']);

// Cópia local — cada FAQ ganha `selected` (marcada por padrão, exceto duplicatas).
const localFaqs = ref([]);
const selectedCount = computed(
  () => localFaqs.value.filter(f => f.selected).length
);
const allSelected = computed(
  () => localFaqs.value.length > 0 && localFaqs.value.every(f => f.selected)
);

watch(
  () => props.show,
  val => {
    document.body.style.overflow = val ? 'hidden' : '';
    if (val) {
      localFaqs.value = props.faqs.map(f => ({ ...f, selected: !f.duplicate }));
    }
  }
);
// Quando a lista chega depois de abrir (fetch async), re-hidrata.
watch(
  () => props.faqs,
  list => {
    if (props.show) {
      localFaqs.value = list.map(f => ({ ...f, selected: !f.duplicate }));
    }
  }
);

const toggleFaq = index => {
  localFaqs.value[index].selected = !localFaqs.value[index].selected;
};
const toggleAll = () => {
  const next = !allSelected.value;
  localFaqs.value = localFaqs.value.map(f => ({ ...f, selected: next }));
};
const closeModal = () => emit('update:show', false);
const onApprove = () =>
  emit(
    'approve',
    localFaqs.value.filter(f => f.selected).map(f => f.id)
  );
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="show"
        class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/40 backdrop-blur-sm"
        @click.self="closeModal"
      >
        <div
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-3xl max-h-[92vh] flex flex-col overflow-hidden"
          @click.stop
        >
          <!-- Header -->
          <header
            class="flex-shrink-0 px-7 py-5 border-b border-n-weak flex items-start justify-between gap-4"
          >
            <div class="min-w-0">
              <h2 class="text-lg font-semibold text-n-slate-12 leading-tight">
                {{ $t('AI_AGENT.TRAINING.BULK_APPROVE.TITLE') }}
              </h2>
              <p class="text-xs text-n-slate-10 mt-1">
                {{
                  $t('AI_AGENT.TRAINING.BULK_APPROVE.SUBTITLE', {
                    count: localFaqs.length,
                  })
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
          <div class="flex-1 overflow-y-auto px-7 py-5">
            <!-- Loading -->
            <div
              v-if="isLoading"
              class="flex items-center justify-center py-16 text-sm text-n-slate-10 gap-3"
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
              {{ $t('AI_AGENT.TRAINING.LOADING') }}
            </div>

            <!-- Vazio -->
            <div
              v-else-if="localFaqs.length === 0"
              class="flex flex-col items-center justify-center py-16 text-center"
            >
              <p class="text-sm font-medium text-n-slate-12">
                {{ $t('AI_AGENT.TRAINING.BULK_APPROVE.EMPTY_TITLE') }}
              </p>
              <p class="text-sm text-n-slate-10 mt-1 max-w-md">
                {{ $t('AI_AGENT.TRAINING.BULK_APPROVE.EMPTY_HINT') }}
              </p>
            </div>

            <template v-else>
              <!-- Selecionar todas + dica -->
              <div class="flex items-center gap-3 mb-3">
                <Checkbox
                  :model-value="allSelected"
                  :label="$t('AI_AGENT.TRAINING.BULK_APPROVE.SELECT_ALL')"
                  @change="toggleAll"
                />
                <span class="text-xs text-n-slate-10 ml-auto">
                  {{
                    $t('AI_AGENT.TRAINING.BULK_APPROVE.SELECTED', {
                      count: selectedCount,
                      total: localFaqs.length,
                    })
                  }}
                </span>
              </div>
              <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">
                {{ $t('AI_AGENT.TRAINING.BULK_APPROVE.HINT') }}
              </p>

              <div class="space-y-2.5">
                <article
                  v-for="(faq, index) in localFaqs"
                  :key="faq.id"
                  class="rounded-xl border p-3.5 cursor-pointer transition-all"
                  :class="[
                    faq.selected
                      ? 'border-woot-500 bg-woot-50'
                      : 'border-n-weak bg-n-alpha-1 opacity-55',
                  ]"
                  @click="toggleFaq(index)"
                >
                  <div class="flex items-start gap-3">
                    <span
                      class="shrink-0 mt-0.5 flex items-center justify-center w-5 h-5 rounded-md border-2 transition-colors"
                      :class="
                        faq.selected
                          ? 'bg-woot-500 border-woot-500 text-white'
                          : 'border-n-strong text-transparent'
                      "
                    >
                      <svg
                        class="w-3 h-3"
                        viewBox="0 0 24 24"
                        fill="none"
                        stroke="currentColor"
                        stroke-width="3"
                        stroke-linecap="round"
                        stroke-linejoin="round"
                      >
                        <path d="M20 6 9 17l-5-5" />
                      </svg>
                    </span>
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-1.5 mb-1.5 flex-wrap">
                        <span
                          v-if="faq.categoria"
                          class="inline-flex items-center px-2 py-0.5 text-[11px] font-medium rounded-md bg-woot-50 text-woot-700"
                        >
                          {{ faq.categoria }}
                        </span>
                        <span
                          v-if="faq.duplicate"
                          class="inline-flex items-center px-2 py-0.5 text-[11px] font-medium rounded-md bg-amber-100 text-amber-700"
                          :title="
                            $t('AI_AGENT.TRAINING.DETAIL.FAQ_DUPLICATE_HINT')
                          "
                        >
                          {{ $t('AI_AGENT.TRAINING.DETAIL.FAQ_DUPLICATE') }}
                        </span>
                        <span class="text-[11px] text-n-slate-10">
                          {{
                            $t('AI_AGENT.TRAINING.FAQS_TAB.ORIGIN', {
                              name: faq.origem,
                            })
                          }}
                        </span>
                      </div>
                      <p class="text-sm font-semibold text-n-slate-12">
                        {{ faq.pergunta_paciente }}
                      </p>
                      <p class="text-sm text-n-slate-11 mt-1 leading-relaxed">
                        {{ faq.resposta_clinica }}
                      </p>
                    </div>
                  </div>
                </article>
              </div>
            </template>
          </div>

          <!-- Footer -->
          <footer
            class="flex-shrink-0 px-7 py-3.5 border-t border-n-weak flex items-center justify-end gap-3 bg-n-alpha-1"
          >
            <BeclinicButton
              :label="$t('AI_AGENT.TRAINING.FAQS_TAB.CANCEL')"
              variant="outline"
              color="slate"
              :disabled="isApproving"
              @click="closeModal"
            />
            <BeclinicButton
              :label="
                $t('AI_AGENT.TRAINING.BULK_APPROVE.APPROVE_BUTTON', {
                  count: selectedCount,
                })
              "
              icon="i-lucide-sparkles"
              :is-loading="isApproving"
              :disabled="isApproving || selectedCount === 0"
              @click="onApprove"
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
</style>
