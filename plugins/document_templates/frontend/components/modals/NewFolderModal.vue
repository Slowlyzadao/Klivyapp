<script setup>
// Modal "Nova pasta" — apenas nome. Layout matches mockup M3 Klivy
// (mesmo BaseModal + form-stack, mas só um campo full-width).

import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useDocumentTemplatesStore } from '../../stores/documentTemplates';
import BaseModal from './BaseModal.vue';

const emit = defineEmits(['close', 'created']);

const { t } = useI18n();
const store = useDocumentTemplatesStore();

const name = ref('');
const saving = ref(false);

const canSubmit = () => name.value.trim().length >= 2;

const submit = async () => {
  if (!canSubmit()) return;
  saving.value = true;
  try {
    const folder = await store.createFolder({ name: name.value.trim(), position: 0 });
    useAlert(t('DOCUMENT_TEMPLATES.MESSAGES.FOLDER_CREATED', { name: folder.name }));
    emit('created', folder);
  } catch (e) {
    useAlert(e.response?.data?.errors?.join(', ') || e.message);
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <BaseModal
    :title="t('DOCUMENT_TEMPLATES.MODAL.NEW_FOLDER_TITLE')"
    @close="emit('close')"
  >
    <form class="form-stack" @submit.prevent="submit">
      <div class="form-stack__field form-stack__field--full">
        <label class="form-stack__label" for="folder-name">
          {{ t('DOCUMENT_TEMPLATES.FIELDS.FOLDER_NAME') }}
        </label>
        <input
          id="folder-name"
          v-model="name"
          type="text"
          autofocus
          :placeholder="t('DOCUMENT_TEMPLATES.FIELDS.FOLDER_NAME_PLACEHOLDER')"
          class="form-stack__input"
        />
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
        :disabled="!canSubmit() || saving"
        @click="submit"
      >
        {{ saving
          ? t('DOCUMENT_TEMPLATES.MODAL.SAVING')
          : t('DOCUMENT_TEMPLATES.MODAL.CREATE') }}
      </button>
    </template>
  </BaseModal>
</template>

<style lang="scss" scoped>
@use '../../styles/modals/form-stack';
</style>
