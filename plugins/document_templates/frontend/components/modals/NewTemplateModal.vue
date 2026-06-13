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
import FormSelect from '@plugins/beclinic_core/frontend/components/FormSelect.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';

const props = defineProps({
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

const folderOptions = computed(() => [
  { value: '', label: t('DOCUMENT_TEMPLATES.FIELDS.NO_FOLDER') },
  ...props.folders.map(f => ({ value: f.id, label: f.name })),
]);

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
    :close-on-backdrop="false"
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
          class="form-stack__input reset-base"
        />
      </div>

      <div class="form-stack__field">
        <label class="form-stack__label">
          {{ t('DOCUMENT_TEMPLATES.FIELDS.DOCUMENT_TYPE') }}
        </label>
        <FormSelect
          v-model="documentType"
          :options="typeOptions"
          auto-searchable
        />
      </div>

      <div class="form-stack__field">
        <label class="form-stack__label">
          {{ t('DOCUMENT_TEMPLATES.FIELDS.FOLDER') }}
          <span class="form-stack__label-hint">
            ({{ t('DOCUMENT_TEMPLATES.MODAL.OPTIONAL') }})
          </span>
        </label>
        <FormSelect
          v-model="folderId"
          :options="folderOptions"
          :placeholder="t('DOCUMENT_TEMPLATES.FIELDS.NO_FOLDER')"
        />
      </div>
    </form>

    <template #footer>
      <BeclinicButton
        variant="outline"
        color="slate"
        :label="t('DOCUMENT_TEMPLATES.MODAL.CANCEL')"
        :disabled="saving"
        @click="emit('close')"
      />
      <BeclinicButton
        color="blue"
        :label="saving
          ? t('DOCUMENT_TEMPLATES.MODAL.SAVING')
          : t('DOCUMENT_TEMPLATES.MODAL.CREATE_AND_EDIT')"
        :is-loading="saving"
        :disabled="!canSubmit || saving"
        @click="submit"
      />
    </template>
  </BaseModal>
</template>

<style lang="scss" scoped>
@use '../../styles/modals/form-stack';
</style>
