<script setup>
import { computed, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';

const props = defineProps({
  mode: {
    type: String,
    required: true,
    validator: v => ['bug', 'feature'].includes(v),
  },
});

const emit = defineEmits(['submitted']);

const currentUser = useMapGetter('getCurrentUser');

const MAX_FILES = 5;
const MAX_FILE_SIZE = 20 * 1024 * 1024;
const ACCEPTED_TYPES = {
  'image/jpeg': ['jpg', 'jpeg'],
  'image/png': ['png'],
  'video/mp4': ['mp4'],
  'application/pdf': ['pdf'],
};
const ACCEPT_ATTR = '.jpg,.jpeg,.png,.mp4,.pdf';

const name = ref(
  currentUser.value?.available_name || currentUser.value?.name || ''
);
const email = ref(currentUser.value?.email || '');
const message = ref('');
const files = ref([]);
const fileError = ref('');
const submitting = ref(false);
const submitted = ref(false);

const fileInputRef = ref(null);

const isBug = computed(() => props.mode === 'bug');

const heading = computed(() =>
  isBug.value ? 'Reportar um erro' : 'Solicitar uma melhoria'
);
const subheading = computed(() =>
  isBug.value
    ? 'Descreva o problema que você encontrou. Quanto mais detalhes, mais rápido a gente resolve.'
    : 'Compartilhe a sua ideia ou sugestão de melhoria. Toda dica é avaliada pelo nosso time.'
);
const messageLabel = computed(() =>
  isBug.value ? 'Descrição do erro' : 'Sua sugestão'
);
const messagePlaceholder = computed(() =>
  isBug.value
    ? 'Conte o que aconteceu, em qual tela e os passos para reproduzir o erro.'
    : 'Descreva sua ideia, o que ela resolveria e como imagina o funcionamento.'
);
const submitLabel = computed(() =>
  isBug.value ? 'Enviar relato' : 'Enviar sugestão'
);

const canSubmit = computed(
  () =>
    name.value.trim().length > 0 &&
    email.value.trim().length > 0 &&
    message.value.trim().length > 0 &&
    !submitting.value
);

function isAcceptedFile(file) {
  if (!ACCEPTED_TYPES[file.type]) return false;
  const ext = file.name.split('.').pop()?.toLowerCase();
  return ACCEPTED_TYPES[file.type].includes(ext);
}

function formatSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
}

function fileKindIcon(file) {
  if (file.type.startsWith('image/')) return 'i-lucide-image';
  if (file.type.startsWith('video/')) return 'i-lucide-film';
  return 'i-lucide-file-text';
}

function onPickFiles() {
  fileInputRef.value?.click();
}

function handleFiles(event) {
  fileError.value = '';
  const incoming = Array.from(event.target.files || []);
  if (!incoming.length) return;

  const next = [...files.value];
  let limitReached = false;

  incoming.forEach(file => {
    if (limitReached) return;
    if (next.length >= MAX_FILES) {
      fileError.value = `Você pode anexar no máximo ${MAX_FILES} arquivos.`;
      limitReached = true;
      return;
    }
    if (!isAcceptedFile(file)) {
      fileError.value =
        'Formato não suportado. Use JPG, JPEG, PNG, MP4 ou PDF.';
      return;
    }
    if (file.size > MAX_FILE_SIZE) {
      fileError.value = `"${file.name}" passa do limite de 20MB.`;
      return;
    }
    const isDuplicate = next.some(
      f => f.name === file.name && f.size === file.size
    );
    if (isDuplicate) return;
    next.push(file);
  });

  files.value = next;
  event.target.value = '';
}

function removeFile(index) {
  files.value.splice(index, 1);
  fileError.value = '';
}

async function onSubmit() {
  if (!canSubmit.value) return;
  submitting.value = true;
  try {
    // Mock submit — backend endpoint a ser conectado posteriormente.
    await new Promise(resolve => {
      setTimeout(resolve, 600);
    });
    submitted.value = true;
    emit('submitted', {
      mode: props.mode,
      name: name.value,
      email: email.value,
      message: message.value,
      files: files.value,
    });
  } finally {
    submitting.value = false;
  }
}

function resetForm() {
  message.value = '';
  files.value = [];
  fileError.value = '';
  submitted.value = false;
}
</script>

<template>
  <section class="hp-form-card">
    <header class="hp-form-head">
      <div class="hp-form-icon" :class="{ 'hp-form-icon--bug': isBug }">
        <span :class="isBug ? 'i-lucide-bug' : 'i-lucide-sparkles'" />
      </div>
      <div>
        <h2 class="hp-form-title">{{ heading }}</h2>
        <p class="hp-form-sub">{{ subheading }}</p>
      </div>
    </header>

    <div v-if="submitted" class="hp-form-success">
      <div class="hp-form-success-icon">
        <span class="i-lucide-check" />
      </div>
      <div class="hp-form-success-text">
        <strong>Mensagem enviada!</strong>
        <span>
          {{
            isBug
              ? 'Obrigado pelo relato — nosso time vai investigar.'
              : 'Obrigado pela sugestão — vamos avaliar com carinho.'
          }}
        </span>
      </div>
      <button type="button" class="hp-btn-ghost" @click="resetForm">
        Enviar outra
      </button>
    </div>

    <form v-else class="hp-form" @submit.prevent="onSubmit">
      <div class="hp-form-row">
        <label class="hp-form-field">
          <span class="hp-form-label">Nome</span>
          <input
            v-model="name"
            type="text"
            class="hp-form-input"
            placeholder="Seu nome"
            autocomplete="name"
          />
        </label>
        <label class="hp-form-field">
          <span class="hp-form-label">E-mail</span>
          <input
            v-model="email"
            type="email"
            class="hp-form-input"
            placeholder="seu@email.com"
            autocomplete="email"
          />
        </label>
      </div>

      <label class="hp-form-field">
        <span class="hp-form-label">{{ messageLabel }}</span>
        <textarea
          v-model="message"
          rows="6"
          class="hp-form-textarea"
          :placeholder="messagePlaceholder"
        />
      </label>

      <div class="hp-form-field">
        <span class="hp-form-label">
          Anexos
          <span class="hp-form-hint">
            Até {{ MAX_FILES }} arquivos · JPG, PNG, MP4 ou PDF · 20MB cada
          </span>
        </span>

        <button
          type="button"
          class="hp-form-dropzone"
          :disabled="files.length >= MAX_FILES"
          @click="onPickFiles"
        >
          <span class="i-lucide-paperclip hp-form-dropzone-icon" />
          <span class="hp-form-dropzone-text">
            <strong>Clique para selecionar</strong> ou arraste seus arquivos
          </span>
          <span class="hp-form-dropzone-meta">
            {{ files.length }} de {{ MAX_FILES }}
          </span>
        </button>
        <input
          ref="fileInputRef"
          type="file"
          multiple
          :accept="ACCEPT_ATTR"
          class="hp-form-file-input"
          @change="handleFiles"
        />

        <ul v-if="files.length" class="hp-form-files">
          <li v-for="(file, index) in files" :key="index" class="hp-form-file">
            <span class="hp-form-file-icon" :class="fileKindIcon(file)" />
            <div class="hp-form-file-info">
              <span class="hp-form-file-name">{{ file.name }}</span>
              <span class="hp-form-file-size">{{ formatSize(file.size) }}</span>
            </div>
            <button
              type="button"
              class="hp-form-file-remove"
              :title="'Remover ' + file.name"
              @click="removeFile(index)"
            >
              <span class="i-lucide-x" />
            </button>
          </li>
        </ul>

        <div v-if="fileError" class="hp-form-error">
          <span class="i-lucide-alert-circle" />
          {{ fileError }}
        </div>
      </div>

      <div class="hp-form-actions">
        <button type="submit" class="hp-btn-primary" :disabled="!canSubmit">
          <span
            :class="submitting ? 'i-lucide-loader-2 hp-spin' : 'i-lucide-send'"
            style="font-size: 14px"
          />
          {{ submitting ? 'Enviando...' : submitLabel }}
        </button>
      </div>
    </form>
  </section>
</template>
