<script setup>
// Revisão e aprovação: FAQs sugeridas (editáveis — o usuário remove as ruins
// antes de aprovar) no topo e a conversa parseada/transcrita abaixo. Ao
// aprovar, emite `publish` com as FAQs mantidas.
import { ref, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  training: { type: Object, default: null },
  isPublishing: { type: Boolean, default: false },
});

const emit = defineEmits(['update:show', 'publish']);

// Cópia local editável — cada FAQ ganha `selected` (marcada por padrão, exceto
// as duplicadas). Só as selecionadas são publicadas; a lixeira descarta de vez.
const localFaqs = ref([]);
const isPublished = computed(() => Boolean(props.training?.published_at));
const selectedCount = computed(
  () => localFaqs.value.filter(f => f.selected).length
);

watch(
  () => props.show,
  val => {
    document.body.style.overflow = val ? 'hidden' : '';
    if (val) {
      localFaqs.value = (props.training?.faqs || []).map(f => ({
        ...f,
        selected: !f.duplicate,
      }));
    }
  }
);

const toggleFaq = index => {
  localFaqs.value[index].selected = !localFaqs.value[index].selected;
};
const removeFaq = index => localFaqs.value.splice(index, 1);
const closeModal = () => emit('update:show', false);
const onPublish = () =>
  emit(
    'publish',
    localFaqs.value.filter(f => f.selected)
  );
</script>

<template>
  <Teleport to="body">
    <Transition name="modal">
      <div
        v-if="show && training"
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
              <h2
                class="text-lg font-semibold text-n-slate-12 leading-tight truncate"
              >
                {{ training.name }}
              </h2>
              <p class="text-xs text-n-slate-10 mt-1">
                {{
                  $t('AI_AGENT.TRAINING.DETAIL.SUBTITLE', {
                    count: training.message_count,
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
          <div class="flex-1 overflow-y-auto px-7 py-6 space-y-6">
            <!-- FAQs sugeridas (editáveis) -->
            <section>
              <h3 class="text-sm font-semibold text-n-slate-12 mb-1">
                {{
                  $t('AI_AGENT.TRAINING.DETAIL.FAQS_TITLE', {
                    count: localFaqs.length,
                  })
                }}
              </h3>
              <p class="text-xs text-n-slate-10 mb-3 leading-relaxed">
                {{
                  isPublished
                    ? $t('AI_AGENT.TRAINING.DETAIL.FAQS_HINT_PUBLISHED')
                    : $t('AI_AGENT.TRAINING.DETAIL.FAQS_HINT')
                }}
              </p>
              <p
                v-if="localFaqs.length === 0"
                class="text-sm text-n-slate-10 italic"
              >
                {{ $t('AI_AGENT.TRAINING.DETAIL.FAQS_EMPTY') }}
              </p>
              <div v-else class="space-y-2.5">
                <article
                  v-for="(faq, index) in localFaqs"
                  :key="index"
                  class="rounded-xl border p-3.5 transition-all"
                  :class="[
                    isPublished
                      ? 'border-n-weak bg-n-alpha-1'
                      : 'cursor-pointer',
                    !isPublished && faq.selected
                      ? 'border-woot-500 bg-woot-50'
                      : '',
                    !isPublished && !faq.selected
                      ? 'border-n-weak bg-n-alpha-1 opacity-55'
                      : '',
                  ]"
                  @click="!isPublished && toggleFaq(index)"
                >
                  <div class="flex items-start gap-3">
                    <!-- checkbox de seleção -->
                    <span
                      v-if="!isPublished"
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
                    <!-- conteúdo -->
                    <div class="min-w-0 flex-1">
                      <div class="flex items-center gap-1.5 mb-1.5 flex-wrap">
                        <span
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
                      </div>
                      <p class="text-sm font-semibold text-n-slate-12">
                        {{ faq.pergunta_paciente }}
                      </p>
                      <p class="text-sm text-n-slate-11 mt-1 leading-relaxed">
                        {{ faq.resposta_clinica }}
                      </p>
                      <details v-if="faq.fonte" class="mt-2" @click.stop>
                        <summary
                          class="text-[11px] text-n-slate-9 cursor-pointer select-none"
                        >
                          {{ $t('AI_AGENT.TRAINING.DETAIL.FAQ_SOURCE') }}
                        </summary>
                        <p
                          class="text-[11px] text-n-slate-10 mt-1 italic break-words"
                        >
                          {{ faq.fonte }}
                        </p>
                      </details>
                    </div>
                    <!-- descartar de vez -->
                    <button
                      v-if="!isPublished"
                      type="button"
                      :aria-label="$t('AI_AGENT.TRAINING.DETAIL.FAQ_REMOVE')"
                      class="shrink-0 flex items-center justify-center w-8 h-8 rounded-lg text-n-slate-10 hover:bg-ruby-100 hover:text-ruby-600 transition-colors"
                      @click.stop="removeFaq(index)"
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
                        <path
                          d="M3 6h18M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2m3 0v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"
                        />
                        <path d="M10 11v6M14 11v6" />
                      </svg>
                    </button>
                  </div>
                </article>
              </div>
            </section>

            <!-- Conversa parseada / transcrita -->
            <section>
              <h3 class="text-sm font-semibold text-n-slate-12 mb-3">
                {{ $t('AI_AGENT.TRAINING.DETAIL.CONVERSATION_TITLE') }}
              </h3>
              <div class="space-y-3">
                <div
                  v-for="msg in training.parsed_messages"
                  :key="msg.idx"
                  class="flex"
                  :class="
                    msg.role === 'CLINICA' ? 'justify-end' : 'justify-start'
                  "
                >
                  <div class="max-w-[78%] min-w-0">
                    <div
                      class="flex items-center gap-2 mb-1"
                      :class="msg.role === 'CLINICA' ? 'justify-end' : ''"
                    >
                      <span
                        class="inline-flex items-center px-2 py-0.5 text-[11px] font-semibold rounded-md"
                        :class="
                          msg.role === 'CLINICA'
                            ? 'bg-woot-100 text-woot-700'
                            : 'bg-n-alpha-2 text-n-slate-11'
                        "
                      >
                        {{
                          msg.role === 'CLINICA'
                            ? $t('AI_AGENT.TRAINING.DETAIL.ROLE_CLINIC')
                            : $t('AI_AGENT.TRAINING.DETAIL.ROLE_PATIENT')
                        }}
                      </span>
                      <span class="text-[11px] text-n-slate-9">
                        {{ msg.time }}
                      </span>
                    </div>
                    <div
                      class="px-3.5 py-2.5 rounded-2xl text-sm leading-relaxed"
                      :class="
                        msg.role === 'CLINICA'
                          ? 'bg-woot-500 text-white rounded-tr-sm'
                          : 'bg-n-alpha-2 text-n-slate-12 rounded-tl-sm'
                      "
                    >
                      <span
                        v-if="msg.type === 'audio'"
                        class="inline-flex items-start gap-1.5"
                      >
                        <svg
                          class="w-3.5 h-3.5 mt-0.5 shrink-0 opacity-70"
                          viewBox="0 0 24 24"
                          fill="none"
                          stroke="currentColor"
                          stroke-width="2"
                          stroke-linecap="round"
                          stroke-linejoin="round"
                        >
                          <path
                            d="M12 2a3 3 0 0 0-3 3v7a3 3 0 0 0 6 0V5a3 3 0 0 0-3-3z"
                          />
                          <path d="M19 10v2a7 7 0 0 1-14 0v-2" />
                        </svg>
                        <span class="break-words">{{ msg.text }}</span>
                      </span>
                      <span
                        v-else-if="msg.type === 'anexo_ignorado'"
                        class="italic opacity-75"
                      >
                        {{ $t('AI_AGENT.TRAINING.DETAIL.ATTACHMENT_IGNORED') }}
                      </span>
                      <span v-else class="whitespace-pre-wrap break-words">{{
                        msg.text
                      }}</span>
                    </div>
                  </div>
                </div>
              </div>
            </section>
          </div>

          <!-- Footer: nota de LGPD + aprovação -->
          <footer
            class="flex-shrink-0 px-7 py-3.5 border-t border-n-weak flex items-center justify-between gap-4 bg-n-alpha-1"
          >
            <span
              class="flex items-center gap-2 text-xs text-n-slate-10 min-w-0"
            >
              <svg
                class="w-3.5 h-3.5 shrink-0"
                viewBox="0 0 24 24"
                fill="none"
                stroke="currentColor"
                stroke-width="2"
                stroke-linecap="round"
                stroke-linejoin="round"
              >
                <rect x="3" y="11" width="18" height="11" rx="2" />
                <path d="M7 11V7a5 5 0 0 1 10 0v4" />
              </svg>
              <span class="truncate">
                {{ $t('AI_AGENT.TRAINING.DETAIL.PII_NOTE') }}
              </span>
            </span>
            <span
              v-if="isPublished"
              class="shrink-0 inline-flex items-center gap-1.5 text-xs font-medium text-emerald-600"
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
                <path d="M20 6 9 17l-5-5" />
              </svg>
              {{ $t('AI_AGENT.TRAINING.DETAIL.PUBLISHED') }}
            </span>
            <BeclinicButton
              v-else
              class="shrink-0"
              :label="
                $t('AI_AGENT.TRAINING.DETAIL.PUBLISH_BUTTON', {
                  count: selectedCount,
                })
              "
              icon="i-lucide-sparkles"
              :is-loading="isPublishing"
              :disabled="isPublishing || selectedCount === 0"
              @click="onPublish"
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
