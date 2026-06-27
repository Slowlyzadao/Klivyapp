<script setup>
// Modal de envio de conversas de WhatsApp. Aceita VÁRIOS .zip de uma vez —
// cada arquivo vira uma conversa de treinamento separada. Gerencia o próprio
// estado e emite a lista no `save` (sem mutar props).
import { ref, computed, watch } from 'vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
  show: { type: Boolean, required: true },
  isSaving: { type: Boolean, default: false },
});

const emit = defineEmits(['update:show', 'save']);

const fileInput = ref(null);
const fileError = ref('');
const zipFiles = ref([]);

// 200 MB — espelha AiAgent::TrainingConversation::MAX_ZIP_SIZE
const MAX_SIZE = 200 * 1024 * 1024;

const fileSizeLabel = file => {
  const mb = file.size / (1024 * 1024);
  return mb < 1 ? `${Math.round(file.size / 1024)} KB` : `${mb.toFixed(1)} MB`;
};

const canSubmit = computed(() => !props.isSaving && zipFiles.value.length > 0);

const pickFile = () => fileInput.value?.click();

// Aceita vários .zip (e acumula entre cliques); ignora duplicados por nome+tamanho.
const onFileChange = event => {
  fileError.value = '';
  Array.from(event.target.files || []).forEach(file => {
    if (!/\.zip$/i.test(file.name)) {
      fileError.value = 'invalid_type';
      return;
    }
    if (file.size > MAX_SIZE) {
      fileError.value = 'too_large';
      return;
    }
    const dup = zipFiles.value.some(
      f => f.name === file.name && f.size === file.size
    );
    if (!dup) zipFiles.value.push(file);
  });
  if (fileInput.value) fileInput.value.value = '';
};

const removeFile = index => zipFiles.value.splice(index, 1);

const closeModal = () => emit('update:show', false);
const onSave = () => {
  if (canSubmit.value) emit('save', { zipFiles: [...zipFiles.value] });
};

// Zera o formulário sempre que o modal abre.
watch(
  () => props.show,
  val => {
    document.body.style.overflow = val ? 'hidden' : '';
    if (val) {
      zipFiles.value = [];
      fileError.value = '';
      if (fileInput.value) fileInput.value.value = '';
    }
  }
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
          class="bg-n-solid-1 rounded-2xl shadow-2xl w-full max-w-xl max-h-[92vh] flex flex-col overflow-hidden"
          @click.stop
        >
          <!-- Header -->
          <header
            class="flex-shrink-0 px-7 py-5 border-b border-n-weak flex items-start justify-between gap-4"
          >
            <div class="min-w-0">
              <h2 class="text-lg font-semibold text-n-slate-12 leading-tight">
                {{ $t('AI_AGENT.TRAINING.FORM.TITLE') }}
              </h2>
              <p class="text-xs text-n-slate-10 mt-1">
                {{ $t('AI_AGENT.TRAINING.FORM.SUBTITLE') }}
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
            class="flex-1 overflow-y-auto px-7 py-6 space-y-4"
            @submit.prevent="onSave"
          >
            <div>
              <label class="block text-sm font-semibold text-n-slate-12 mb-1.5">
                {{ $t('AI_AGENT.TRAINING.FORM.FILE_LABEL') }}
              </label>
              <input
                ref="fileInput"
                type="file"
                accept=".zip"
                multiple
                class="hidden"
                @change="onFileChange"
              />
              <button
                type="button"
                class="w-full flex items-center gap-3 px-4 py-3.5 rounded-lg border-2 border-dashed border-n-weak hover:border-woot-500 hover:bg-woot-50 transition-all text-left"
                @click="pickFile"
              >
                <div
                  class="shrink-0 flex items-center justify-center w-10 h-10 rounded-lg bg-n-alpha-2 text-n-slate-11"
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
                    <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4" />
                    <path d="M17 8l-5-5-5 5M12 3v12" />
                  </svg>
                </div>
                <div class="min-w-0 flex-1">
                  <div class="text-sm font-medium text-n-slate-11">
                    {{ $t('AI_AGENT.TRAINING.FORM.FILE_CTA') }}
                  </div>
                  <div class="text-xs text-n-slate-10 mt-0.5">
                    {{ $t('AI_AGENT.TRAINING.FORM.FILE_HINT') }}
                  </div>
                </div>
              </button>
              <p
                v-if="fileError === 'invalid_type'"
                class="text-xs text-ruby-600 mt-1.5"
              >
                {{ $t('AI_AGENT.TRAINING.FORM.FILE_INVALID') }}
              </p>
              <p
                v-else-if="fileError === 'too_large'"
                class="text-xs text-ruby-600 mt-1.5"
              >
                {{ $t('AI_AGENT.TRAINING.FORM.FILE_TOO_LARGE') }}
              </p>
            </div>

            <!-- Lista de arquivos selecionados -->
            <ul v-if="zipFiles.length" class="space-y-1.5">
              <li
                v-for="(file, index) in zipFiles"
                :key="`${file.name}-${file.size}`"
                class="flex items-center gap-2.5 px-3 py-2 rounded-lg bg-n-alpha-1 border border-n-weak"
              >
                <svg
                  class="shrink-0 w-4 h-4 text-n-slate-10"
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
                  <path d="M14 2v6h6" />
                </svg>
                <span class="flex-1 min-w-0 truncate text-sm text-n-slate-12">
                  {{ file.name }}
                </span>
                <span class="shrink-0 text-xs text-n-slate-10">
                  {{ fileSizeLabel(file) }}
                </span>
                <button
                  type="button"
                  class="shrink-0 flex items-center justify-center w-7 h-7 rounded-md text-n-slate-10 hover:bg-ruby-100 hover:text-ruby-600 transition-colors"
                  @click="removeFile(index)"
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
                    <path d="M18 6 6 18M6 6l12 12" />
                  </svg>
                </button>
              </li>
            </ul>
          </form>

          <!-- Footer -->
          <footer
            class="flex-shrink-0 px-7 py-4 border-t border-n-weak flex items-center justify-end gap-3 bg-n-alpha-1"
          >
            <BeclinicButton
              :label="$t('AI_AGENT.TRAINING.FORM.CANCEL')"
              variant="outline"
              color="slate"
              @click="closeModal"
            />
            <BeclinicButton
              :label="
                zipFiles.length > 1
                  ? $t('AI_AGENT.TRAINING.FORM.SUBMIT_MANY', {
                      count: zipFiles.length,
                    })
                  : $t('AI_AGENT.TRAINING.FORM.SUBMIT')
              "
              :is-loading="isSaving"
              :disabled="!canSubmit"
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
</style>
