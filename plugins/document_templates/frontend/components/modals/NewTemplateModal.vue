<script setup>
// Modal "Novo modelo" — pede nome + tipo + pasta opcional.
//
// Layout (matches mockup M3):
//   ┌─ Header: "Novo modelo" + close ─────────┐
//   │  Nome (full width)                       │
//   │  ┌────────────┬─────────────┐            │
//   │  │ Tipo doc   │ Pasta (opc) │            │
//   │  └────────────┴─────────────┘            │
//   ├─ Footer: [Cancelar]   [Criar e editar] ──┤
//
// Após criar, emite `created` e pai redireciona pro editor.

import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useDocumentTemplatesStore } from '../../stores/documentTemplates';
import { DOCUMENT_TYPE_LABELS } from '../../constants/documentTypes';
import BaseModal from './BaseModal.vue';

defineProps({
  folders: { type: Array, default: () => [] },
});

const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useDocumentTemplatesStore();

const name = ref('');
const documentType = ref('atestado');
const folderId = ref('');
const saving = ref(false);

const typeOptions = computed(() =>
  Object.entries(DOCUMENT_TYPE_LABELS).map(([value, label]) => ({ value, label })),
);

const canSubmit = computed(
  () => name.value.trim().length >= 2 && Boolean(documentType.value),
);

const submit = async () => {
  if (!canSubmit.value) return;
  saving.value = true;
  try {
    const created = await store.createTemplate({
      name: name.value.trim(),
      document_type: documentType.value,
      folder_id: folderId.value || null,
      // Nasce 'active' — modelo criado pela clínica já é usável e deve
      // aparecer imediatamente na listagem.
      status: 'active',
      content_json: { type: 'doc', content: [{ type: 'paragraph' }] },
    });
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.TEMPLATE_CREATED', { name: created.name }));
    emit('created', created);
  } catch (e) {
    useAlert(e.response?.data?.errors?.join(', ') || e.message);
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <BaseModal
    :title="t('DOCUMENT_TEMPLATES.MODAL.NEW_TEMPLATE_TITLE')"
    @close="emit('close')"
  >
    <form class="form-stack" @submit.prevent="submit">
      <div class="form-stack__field form-stack__field--full">
        <label class="form-stack__label" for="tpl-name">
          {{ t('DOCUMENT_TEMPLATES.FIELDS.NAME') }}
        </label>
        <input
          id="tpl-name"
          v-model="name"
          type="text"
          autofocus
          :placeholder="t('DOCUMENT_TEMPLATES.FIELDS.NAME_PLACEHOLDER')"
          class="form-stack__input"
        />
      </div>

      <div class="form-stack__field">
        <label class="form-stack__label" for="tpl-type">
          {{ t('DOCUMENT_TEMPLATES.FIELDS.DOCUMENT_TYPE') }}
        </label>
        <div class="form-stack__select-wrap">
          <select id="tpl-type" v-model="documentType" class="form-stack__select">
            <option v-for="opt in typeOptions" :key="opt.value" :value="opt.value">
              {{ opt.label }}
            </option>
          </select>
          <span class="i-lucide-chevron-down form-stack__select-chevron" />
        </div>
      </div>

      <div class="form-stack__field">
        <label class="form-stack__label" for="tpl-folder">
          {{ t('DOCUMENT_TEMPLATES.FIELDS.FOLDER') }}
          <span class="form-stack__label-hint">
            ({{ t('DOCUMENT_TEMPLATES.MODAL.OPTIONAL') }})
          </span>
        </label>
        <div class="form-stack__select-wrap">
          <select id="tpl-folder" v-model="folderId" class="form-stack__select">
            <option value="">
              {{ t('DOCUMENT_TEMPLATES.FIELDS.NO_FOLDER') }}
            </option>
            <option v-for="folder in folders" :key="folder.id" :value="folder.id">
              {{ folder.name }}
            </option>
          </select>
          <span class="i-lucide-chevron-down form-stack__select-chevron" />
        </div>
      </div>
    </form>

    <template #footer>
      <button
        type="button"
        class="form-stack__btn form-stack__btn--secondary"
        :disabled="saving"
        @click="emit('close')"
      >
        {{ t('DOCUMENT_TEMPLATES.MODAL.CANCEL') }}
      </button>
      <button
        type="button"
        class="form-stack__btn form-stack__btn--primary"
        :disabled="!canSubmit || saving"
        @click="submit"
      >
        {{ saving
          ? t('DOCUMENT_TEMPLATES.MODAL.SAVING')
          : t('DOCUMENT_TEMPLATES.MODAL.CREATE_AND_EDIT') }}
      </button>
    </template>
  </BaseModal>
</template>

<style lang="scss" scoped>
@use '../../styles/modals/form-stack';
</style>
