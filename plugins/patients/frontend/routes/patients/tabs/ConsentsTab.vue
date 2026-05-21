<script setup>
/**
 * ConsentsTab — Aba "Consentimentos e Assinaturas" do prontuário.
 *
 * Orquestrador. Composição:
 *   • useConsents — fetch + create + sign + sendRemote + revoke
 *   • useSignatureCanvas — canvas drawing (interno em SignatureModal)
 *   • consents-tab/* (6 sub-componentes)
 *
 * Recebe `patient` como prop pra preencher placeholders dos templates
 * ([NOME], [CPF], [RG], [ENDEREÇO], etc.) via fillConsentTemplate.
 * Auto-suficiente: lê patientId da rota.
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useConsents } from '@plugins/patients/frontend/features/patient-record/composables/useConsents';
import ConsentsHeader from '@plugins/patients/frontend/features/patient-record/components/consents-tab/ConsentsHeader.vue';
import ConsentsKpiGrid from '@plugins/patients/frontend/features/patient-record/components/consents-tab/ConsentsKpiGrid.vue';
import NewConsentForm from '@plugins/patients/frontend/features/patient-record/components/consents-tab/NewConsentForm.vue';
import ConsentsTable from '@plugins/patients/frontend/features/patient-record/components/consents-tab/ConsentsTable.vue';
import SignatureModal from '@plugins/patients/frontend/features/patient-record/components/consents-tab/SignatureModal.vue';
import ConsentViewModal from '@plugins/patients/frontend/features/patient-record/components/consents-tab/ConsentViewModal.vue';

defineProps({
  patient: { type: Object, required: true },
});

const route = useRoute();
const patientId = computed(() => route.params.patientId);

const {
  consents,
  isLoading,
  isSubmitting,
  fetch: fetchConsents,
  create,
  sign,
  sendRemote,
  revoke,
  loadDetailIfSigned,
} = useConsents(patientId);

// ── UI state ───────────────────────────────────────────────
const showForm = ref(false);
const showSignModal = ref(false);
const signingConsentId = ref(null);
const showViewModal = ref(false);
const consentInView = ref(null);
const formRef = ref(null);

// ── Computeds ──────────────────────────────────────────────
const stats = computed(() => ({
  total: consents.value.length,
  signed: consents.value.filter(c => c.status === 'signed').length,
  pending: consents.value.filter(c => c.status === 'pendente' || !c.status)
    .length,
  expired: consents.value.filter(c => c.status === 'vencido').length,
}));

// ── Handlers ───────────────────────────────────────────────
const toggleForm = () => {
  showForm.value = !showForm.value;
  if (showForm.value) formRef.value?.reset?.();
};

const handleCreate = async payload => {
  const { ok } = await create(payload);
  if (ok) showForm.value = false;
};

const openSignModal = consentId => {
  signingConsentId.value = consentId;
  showSignModal.value = true;
};

const handleSign = async dataUrl => {
  if (!signingConsentId.value) return;
  const { ok } = await sign(signingConsentId.value, dataUrl);
  if (ok) {
    showSignModal.value = false;
    signingConsentId.value = null;
  }
};

const openViewModal = async consent => {
  consentInView.value = consent;
  showViewModal.value = true;
  // Carrega detalhes (hash, IP, blob) se assinado — best-effort.
  consentInView.value = await loadDetailIfSigned(consent);
};

const handleSignFromView = consentId => {
  showViewModal.value = false;
  openSignModal(consentId);
};

onMounted(() => {
  fetchConsents();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <ConsentsHeader :form-open="showForm" @toggle-form="toggleForm" />
    <ConsentsKpiGrid :stats="stats" />

    <NewConsentForm
      v-if="showForm"
      ref="formRef"
      :patient="patient"
      :loading="isSubmitting"
      @close="showForm = false"
      @create="handleCreate"
    />

    <div v-if="isLoading" class="flex items-center justify-center py-16">
      <div
        class="w-8 h-8 rounded-full border-2 border-emerald-400 border-t-transparent animate-spin"
      />
    </div>

    <div
      v-else-if="!consents || consents.length === 0"
      class="reg-section"
    >
      <div class="proc-empty-state">
        <div class="proc-empty-icon">
          <i class="i-lucide-file-signature w-5 h-5" />
        </div>
        <p class="proc-empty-text">{{ $t('PATIENT_CONSENTS.EMPTY.TITLE') }}</p>
        <p class="proc-empty-hint">{{ $t('PATIENT_CONSENTS.EMPTY.HINT') }}</p>
      </div>
    </div>

    <ConsentsTable
      v-else
      :consents="consents"
      @view="openViewModal"
      @send-remote="sendRemote"
      @sign="openSignModal"
      @revoke="revoke"
    />

    <SignatureModal
      :open="showSignModal"
      :loading="isSubmitting"
      @close="showSignModal = false"
      @confirm="handleSign"
    />

    <ConsentViewModal
      :open="showViewModal"
      :consent="consentInView"
      @close="showViewModal = false"
      @sign="handleSignFromView"
    />
  </div>
</template>
