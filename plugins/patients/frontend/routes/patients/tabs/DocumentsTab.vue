<script setup>
/**
 * DocumentsTab — Aba "Documentos" do prontuário.
 *
 * Orquestrador. Composição:
 *   • useDocuments — fetch + generate + download + sendWhatsApp + delete
 *   • documents-tab/* (3 sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota.
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import { useDocuments } from '@plugins/patients/frontend/features/patient-record/composables/useDocuments';
import DocumentsHeader from '@plugins/patients/frontend/features/patient-record/components/documents-tab/DocumentsHeader.vue';
import DocumentsTable from '@plugins/patients/frontend/features/patient-record/components/documents-tab/DocumentsTable.vue';
import GenerateDocumentModal from '@plugins/patients/frontend/features/patient-record/components/documents-tab/GenerateDocumentModal.vue';
import DocumentPreviewModal from '@plugins/patients/frontend/features/patient-record/components/documents-tab/DocumentPreviewModal.vue';

const { t } = useI18n();
const route = useRoute();
const patientId = computed(() => route.params.patientId);

const {
  documents,
  isGenerating,
  fetch: fetchDocuments,
  generate,
  download,
  fetchPreviewUrl,
  sendWhatsApp,
  remove,
} = useDocuments(patientId);

// ── UI state ───────────────────────────────────────────────
const showGenerateModal = ref(false);
const showDeleteModal = ref(false);
const pendingDeleteId = ref(null);
const showPreviewModal = ref(false);
const previewSrc = ref('');
const previewTitle = ref('');
const previewDoc = ref(null);

// ── Handlers ───────────────────────────────────────────────
const openGenerateModal = () => {
  showGenerateModal.value = true;
};

const handleGenerate = async form => {
  const { ok } = await generate(form);
  if (ok) showGenerateModal.value = false;
};

const requestDelete = documentId => {
  if (!documentId) return;
  pendingDeleteId.value = documentId;
  showDeleteModal.value = true;
};

const confirmDelete = async () => {
  if (!pendingDeleteId.value) return;
  await remove(pendingDeleteId.value);
  showDeleteModal.value = false;
  pendingDeleteId.value = null;
};

const cancelDelete = () => {
  showDeleteModal.value = false;
  pendingDeleteId.value = null;
};

const openPreview = async doc => {
  if (!doc?.id) return;
  previewDoc.value = doc;
  previewTitle.value = doc.title || t('PATIENT_DOCUMENTS.TABLE.DEFAULT_TITLE');
  previewSrc.value = '';
  showPreviewModal.value = true;
  const url = await fetchPreviewUrl(doc);
  if (!url) {
    showPreviewModal.value = false;
    return;
  }
  previewSrc.value = url;
};

const closePreview = () => {
  showPreviewModal.value = false;
  previewSrc.value = '';
  previewDoc.value = null;
};

const downloadFromPreview = () => {
  if (previewDoc.value) download(previewDoc.value);
};

onMounted(() => {
  fetchDocuments();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <DocumentsHeader @generate="openGenerateModal" />

    <DocumentsTable
      :documents="documents"
      @generate="openGenerateModal"
      @preview="openPreview"
      @download="download"
      @send-whatsapp="sendWhatsApp"
      @delete="requestDelete"
    />

    <GenerateDocumentModal
      :open="showGenerateModal"
      :loading="isGenerating"
      @close="showGenerateModal = false"
      @generate="handleGenerate"
    />

    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      :title="t('PATIENT_DOCUMENTS.DELETE_MODAL.TITLE')"
      :message="t('PATIENT_DOCUMENTS.DELETE_MODAL.MESSAGE')"
      :confirm-label="t('PATIENT_DOCUMENTS.DELETE_MODAL.CONFIRM')"
      @confirm="confirmDelete"
      @cancel="cancelDelete"
    />

    <DocumentPreviewModal
      :open="showPreviewModal"
      :title="previewTitle"
      :src="previewSrc"
      @close="closePreview"
      @download="downloadFromPreview"
    />
  </div>
</template>
