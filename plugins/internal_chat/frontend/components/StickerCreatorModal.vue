<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import {
  processStickerFile,
  STICKER_INPUT_ACCEPT,
} from '@plugins/internal_chat/frontend/composables/stickerImageProcessor';

const emit = defineEmits(['close', 'created']);
const store = useStore();

const file = ref(null);
const previewUrl = ref('');
const previewSize = ref({ width: 0, height: 0 });
const processing = ref(false);
const stickerName = ref('');
const error = ref('');
const dragOver = ref(false);
const fileInputRef = ref(null);

const isUploading = computed(
  () => store.getters['internalChatStickers/getUIFlags'].isUploading
);
const canSave = computed(() => Boolean(file.value) && !processing.value && !isUploading.value);

const onPick = async list => {
  const f = list?.[0];
  if (!f) return;
  error.value = '';
  processing.value = true;
  try {
    const { blob, width, height } = await processStickerFile(f);
    file.value = blob;
    previewSize.value = { width, height };
    if (previewUrl.value) URL.revokeObjectURL(previewUrl.value);
    previewUrl.value = URL.createObjectURL(blob);
  } catch (e) {
    error.value = e.message || 'Falha ao processar imagem.';
    file.value = null;
  } finally {
    processing.value = false;
  }
};

const onFileChange = e => {
  onPick(Array.from(e.target.files || []));
  e.target.value = '';
};

const onDrop = e => {
  e.preventDefault();
  dragOver.value = false;
  onPick(Array.from(e.dataTransfer.files || []));
};

const reset = () => {
  if (previewUrl.value) URL.revokeObjectURL(previewUrl.value);
  previewUrl.value = '';
  file.value = null;
  stickerName.value = '';
  error.value = '';
};

const save = async () => {
  if (!canSave.value) return;
  error.value = '';
  try {
    const created = await store.dispatch('internalChatStickers/upload', {
      blob: file.value,
      name: stickerName.value.trim() || null,
      width: previewSize.value.width,
      height: previewSize.value.height,
    });
    emit('created', created);
    emit('close');
    reset();
  } catch (e) {
    error.value =
      e?.response?.data?.errors?.join(', ') ||
      e?.response?.data?.error ||
      'Falha ao subir figurinha.';
  }
};

const close = () => {
  reset();
  emit('close');
};
</script>

<template>
  <div
    class="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 px-4"
    @click.self="close"
  >
    <div class="w-full max-w-md rounded-xl bg-n-solid-1 border border-n-weak shadow-2xl overflow-hidden">
      <header class="flex items-center justify-between px-5 py-3 border-b border-n-weak">
        <h3 class="text-sm font-semibold text-n-slate-12">Criar figurinha</h3>
        <button
          type="button"
          class="text-n-slate-11 hover:text-n-slate-12"
          @click="close"
        >
          <span class="i-lucide-x text-lg" />
        </button>
      </header>

      <div class="p-5 space-y-4">
        <div
          class="flex items-center justify-center w-full h-56 rounded-lg border-2 border-dashed transition cursor-pointer"
          :class="
            dragOver
              ? 'border-n-brand bg-n-alpha-1'
              : 'border-n-weak hover:border-n-slate-7 hover:bg-n-alpha-1'
          "
          @dragover.prevent="dragOver = true"
          @dragleave="dragOver = false"
          @drop="onDrop"
          @click="fileInputRef.click()"
        >
          <img
            v-if="previewUrl"
            :src="previewUrl"
            class="object-contain max-w-full max-h-full"
          >
          <div
            v-else
            class="flex flex-col items-center gap-2 text-center px-4"
          >
            <span class="i-lucide-image-up text-3xl text-n-slate-9" />
            <p class="text-sm text-n-slate-11">
              Arraste uma imagem ou clique para escolher
            </p>
            <p class="text-[11px] text-n-slate-10">
              PNG, JPG, GIF ou WebP. Será convertida em WebP 512×512.
            </p>
          </div>
        </div>
        <input
          ref="fileInputRef"
          type="file"
          :accept="STICKER_INPUT_ACCEPT"
          class="hidden"
          @change="onFileChange"
        >

        <div v-if="processing" class="text-xs text-n-slate-11">
          Processando imagem…
        </div>
        <div v-if="error" class="text-xs text-n-ruby-11">
          {{ error }}
        </div>

        <div v-if="file">
          <label class="block mb-1 text-xs font-medium text-n-slate-11">
            Nome (opcional)
          </label>
          <input
            v-model="stickerName"
            type="text"
            maxlength="60"
            placeholder="Ex.: bruna, ok, top..."
            class="w-full px-3 py-2 text-sm rounded-md bg-n-alpha-1 text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand"
          >
          <p class="mt-1 text-[11px] text-n-slate-10">
            Tamanho final: {{ Math.round((file.size || 0) / 1024) }}KB
            · {{ previewSize.width }}×{{ previewSize.height }}
          </p>
        </div>
      </div>

      <footer class="flex justify-end gap-2 px-5 py-3 border-t border-n-weak">
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium rounded-md text-n-slate-11 hover:bg-n-alpha-1 hover:text-n-slate-12"
          @click="close"
        >
          Cancelar
        </button>
        <button
          type="button"
          class="px-4 py-2 text-sm font-medium text-white rounded-md bg-n-brand hover:brightness-110 disabled:opacity-50"
          :disabled="!canSave"
          @click="save"
        >
          {{ isUploading ? 'Enviando…' : 'Salvar figurinha' }}
        </button>
      </footer>
    </div>
  </div>
</template>
