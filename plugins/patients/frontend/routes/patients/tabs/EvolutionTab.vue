<script setup>
/**
 * EvolutionTab — aba "Evolução" unificada (procedimentos + evolução clínica).
 *
 * Composição:
 *   • Sub-aba "Ficha de Tratamentos em Andamento"  → InProgressTreatmentsList
 *   • Sub-aba "Ficha Clínica"                       → ClinicalRecordTimeline
 *   • Sub-aba "Histórico de Evolução"              → EvolutionHistoryTable
 *
 * Modais:
 *   • SessionFormModal           (cadastro/edição completo)
 *   • RequestPatientSignatureModal (canal/modo)
 *   • SignatureModal             (canvas — reusa do consents-tab)
 *   • ClinicalGuardModal         (override clínico antes do save)
 *   • ConfirmDangerModal         (delete e errata)
 *
 * Substitui ProceduresTab.vue + EvolutionTab antigo (ClinicalNote).
 */
import { ref, computed, onMounted } from 'vue';
import { useStore } from 'vuex';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { usePermissions } from 'dashboard/composables/usePermissions';
import { useAccount } from 'dashboard/composables/useAccount';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import ClinicalGuardModal from '@plugins/beclinic_core/frontend/components/ClinicalGuardModal.vue';
import { useSessionLogs } from '@plugins/patients/frontend/features/patient-record/composables/useSessionLogs';
import { usePatientClinicalGuards } from '@plugins/patients/frontend/features/patient-record/composables/usePatientClinicalGuards';
import { usePatientActivePlanItems } from '@plugins/patients/frontend/features/patient-record/composables/usePatientActivePlanItems';
import { EVOLUTION_SUBTABS } from '@plugins/patients/frontend/constants/evolution';
import InProgressTreatmentsList from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/InProgressTreatmentsList.vue';
import ClinicalRecordTimeline from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ClinicalRecordTimeline.vue';
import EvolutionHistoryTable from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/EvolutionHistoryTable.vue';
import SessionFormModal from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/SessionFormModal.vue';
import RequestPatientSignatureModal from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/RequestPatientSignatureModal.vue';
import ErratumDialogModal from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/ErratumDialogModal.vue';
import RemoteLinkInfoModal from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/RemoteLinkInfoModal.vue';
import SignatureViewerModal from '@plugins/patients/frontend/features/patient-record/components/evolution-tab/SignatureViewerModal.vue';
import SignatureModal from '@plugins/patients/frontend/features/patient-record/components/consents-tab/SignatureModal.vue';
import PrintPreviewModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/PrintPreviewModal.vue';
import { buildClinicalRecordHtml } from '@plugins/patients/frontend/features/patient-record/utils/clinicalRecordPrintTemplate';

const props = defineProps({
  patient: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const route = useRoute();
const store = useStore();
const { can } = usePermissions();
const { currentAccount } = useAccount();

const patientId = computed(() => route.params.patientId);

const canSign = computed(() => can('patients', 'sign_clinical_notes'));
const canDelete = computed(() => can('patients', 'delete_clinical_notes'));

const {
  sessionLogs,
  isLoading,
  isSaving,
  fetch: fetchLogs,
  create: createSession,
  update: updateSession,
  sign: signSession,
  markErratum,
  remove: removeSession,
  signPatientLocally,
  sendPatientSignatureLink,
} = useSessionLogs(patientId);

const { ensureLoaded: ensureClinicalGuardsLoaded, checkProcedureForConflicts } =
  usePatientClinicalGuards(patientId.value);

const {
  ensureLoaded: ensureActivePlanItemsLoaded,
  pendingItems,
  pendingItemOptions,
  findItem,
  refresh: refreshActivePlanItems,
} = usePatientActivePlanItems(patientId.value);

const activeSubtab = ref(EVOLUTION_SUBTABS.IN_PROGRESS);

const showFormModal = ref(false);
const editingSessionId = ref(null);
const initialSession = ref(null);

const showClinicalGuardModal = ref(false);
const detectedConflicts = ref([]);
const pendingClinicalProcedureName = ref('');
const pendingPayload = ref(null);
const pendingSignFlag = ref(false);

const showErratumModal = ref(false);
const erratumSession = ref(null);
const showDeleteModal = ref(false);
const sessionToDelete = ref(null);

const showSignRequestModal = ref(false);
const showCanvasModal = ref(false);
const showRemoteLinkModal = ref(false);
const showSignatureViewerModal = ref(false);
const viewedSignatureSession = ref(null);
const remoteLinkData = ref(null);
const sessionForSignature = ref(null);

const agents = computed(() => store.getters['agents/getAgents'] || []);
const professionalOptions = computed(() =>
  agents.value
    .filter(
      a =>
        /profession/i.test(a?.custom_role?.name || '') ||
        a.role === 'agent' ||
        a.role === 'administrator'
    )
    .map(a => ({
      value: a.id,
      label: a.available_name || a.name,
    }))
);

// Link público que o paciente abre no celular pra assinar. Aponta pra
// página HTML (`PublicSessionSignaturesController#show`), NÃO pra a API JSON.
// A página é que faz o fetch na API com o mesmo token.
const remoteLinkUrl = computed(() => {
  if (!remoteLinkData.value?.remote_token) return '';
  return `${window.location.origin}/public/sessao/${remoteLinkData.value.remote_token}`;
});

const buildPayload = formData => ({
  performed_at: formData.performed_at,
  procedure_name: formData.procedure_name,
  professional_id: formData.professional_id || null,
  duration_minutes: formData.duration_minutes || 30,
  complaint_of_day: formData.complaint_of_day || null,
  assessment: formData.assessment || null,
  next_consultation_details: formData.next_consultation_details || null,
  observation: formData.observation || null,
  complications: formData.complications || null,
  result_observed: formData.result_observed || null,
  return_needed: !!formData.return_in_days,
  return_in_days: formData.return_in_days || null,
  treatment_item_id: formData.treatment_item_id || null,
  treatment_plan_id: formData.treatment_plan_id || null,
  areas_treated: formData.area_treated
    ? [
        {
          region: formData.area_treated,
          description: formData.procedure_name,
        },
      ]
    : [],
  products_used: formData.product_name
    ? [
        {
          name: formData.product_name,
          quantity: formData.quantity || '1',
          unit: formData.unit || 'un',
          batch: formData.batch || null,
          expires_at: formData.product_expires_at || null,
        },
      ]
    : [],
});

const openNewSessionModal = (overrides = {}) => {
  editingSessionId.value = null;
  initialSession.value = { ...overrides };
  showFormModal.value = true;
};

const openEditSessionModal = session => {
  editingSessionId.value = session.id;
  initialSession.value = {
    performed_at: session.performed_at?.split('T')[0],
    procedure_name: session.procedure_name,
    complaint_of_day: session.complaint_of_day,
    assessment: session.assessment,
    next_consultation_details: session.next_consultation_details,
    observation: session.observation,
    area_treated: session.areas_treated?.[0]?.region || '',
    product_name: session.products_used?.[0]?.name || '',
    quantity: session.products_used?.[0]?.quantity || '',
    unit: session.products_used?.[0]?.unit || 'un',
    batch: session.products_used?.[0]?.batch || '',
    product_expires_at: session.products_used?.[0]?.expires_at || '',
    complications: session.complications,
    result_observed: session.result_observed,
    return_needed: session.return_needed,
    return_in_days: session.return_in_days,
    duration_minutes: session.duration_minutes,
    treatment_item_id: session.treatment_item_id,
    treatment_plan_id: session.treatment_plan_id,
    professional_id: session.professional_id,
  };
  showFormModal.value = true;
};

const onExecuteItem = item => {
  openNewSessionModal({
    treatment_item_id: item.item_id,
    treatment_plan_id: item.plan_id,
    procedure_name: item.item_name,
  });
};

const onSelectTreatmentItem = itemId => {
  const meta = findItem(itemId);
  if (!meta || !initialSession.value) return;
  initialSession.value = {
    ...initialSession.value,
    treatment_item_id: meta.item_id,
    treatment_plan_id: meta.plan_id,
    procedure_name:
      initialSession.value.procedure_name?.trim() || meta.item_name,
  };
};

const closeFormModal = () => {
  showFormModal.value = false;
  editingSessionId.value = null;
  initialSession.value = null;
};

const proceedSave = async (overrideOpts = {}) => {
  const payload = pendingPayload.value;
  const sign = pendingSignFlag.value;
  if (!payload) return;

  let result;
  if (editingSessionId.value) {
    result = await updateSession(editingSessionId.value, payload);
  } else {
    result = await createSession(payload, overrideOpts);
    if (result.ok && sign && result.sessionLog?.id) {
      await signSession(result.sessionLog.id);
    }
  }

  if (result.ok) {
    closeFormModal();
    await refreshActivePlanItems();
  }
  pendingPayload.value = null;
  pendingSignFlag.value = false;
};

const onFormSave = async ({ payload: formData, sign }) => {
  if (!formData.performed_at) {
    useNotification.warning(t('PATIENT_EVOLUTION.MESSAGES.MISSING_DATE'));
    return;
  }
  if (!formData.procedure_name?.trim()) {
    useNotification.warning(t('PATIENT_EVOLUTION.MESSAGES.MISSING_PROCEDURE'));
    return;
  }

  await ensureClinicalGuardsLoaded();
  const conflicts = checkProcedureForConflicts({
    procedureName: formData.procedure_name,
    productName: formData.product_name,
  });

  pendingPayload.value = buildPayload(formData);
  pendingSignFlag.value = !!sign;

  if (conflicts.length > 0 && !editingSessionId.value) {
    detectedConflicts.value = conflicts;
    pendingClinicalProcedureName.value = formData.procedure_name;
    showClinicalGuardModal.value = true;
    return;
  }

  await proceedSave();
};

const onClinicalOverrideConfirm = async reason => {
  showClinicalGuardModal.value = false;
  await proceedSave({ clinicalOverrideReason: reason });
  detectedConflicts.value = [];
  pendingClinicalProcedureName.value = '';
};

const onClinicalOverrideCancel = () => {
  detectedConflicts.value = [];
  pendingClinicalProcedureName.value = '';
  pendingPayload.value = null;
  pendingSignFlag.value = false;
};

const onSignSession = async id => {
  await signSession(id);
};

const onRequestDelete = id => {
  sessionToDelete.value = id;
  showDeleteModal.value = true;
};

const onConfirmDelete = async () => {
  if (!sessionToDelete.value) return;
  await removeSession(sessionToDelete.value);
  showDeleteModal.value = false;
  sessionToDelete.value = null;
};

const onCancelDelete = () => {
  showDeleteModal.value = false;
  sessionToDelete.value = null;
};

const onRequestErratum = session => {
  erratumSession.value = session;
  showErratumModal.value = true;
};

const onConfirmErratum = async reason => {
  if (!reason) {
    useNotification.warning('Informe a justificativa.');
    return;
  }
  await markErratum(erratumSession.value.id, reason);
  showErratumModal.value = false;
  erratumSession.value = null;
};

const onCancelErratum = () => {
  showErratumModal.value = false;
  erratumSession.value = null;
};

const onRequestPatientSignature = session => {
  sessionForSignature.value = session;
  showSignRequestModal.value = true;
};

const onSignRequestConfirm = async ({ mode }) => {
  showSignRequestModal.value = false;
  if (!sessionForSignature.value) return;

  if (mode === 'screen') {
    showCanvasModal.value = true;
  } else {
    const result = await sendPatientSignatureLink(
      sessionForSignature.value.id,
      {}
    );
    if (result.ok) {
      remoteLinkData.value = result.data;
      showRemoteLinkModal.value = true;
    }
  }
};

const onCanvasConfirm = async signatureBlob => {
  if (!sessionForSignature.value) {
    showCanvasModal.value = false;
    return;
  }
  await signPatientLocally(
    sessionForSignature.value.id,
    signatureBlob,
    navigator.userAgent
  );
  showCanvasModal.value = false;
  sessionForSignature.value = null;
};

const onCanvasClose = () => {
  showCanvasModal.value = false;
};

const onSignRequestCancel = () => {
  showSignRequestModal.value = false;
  sessionForSignature.value = null;
};

const onCloseRemoteLinkModal = () => {
  showRemoteLinkModal.value = false;
  remoteLinkData.value = null;
  sessionForSignature.value = null;
};

const copyRemoteLink = () => {
  if (!remoteLinkUrl.value) return;
  navigator.clipboard?.writeText(remoteLinkUrl.value);
  useNotification.success(t('PATIENT_EVOLUTION.REMOTE_LINK_MODAL.COPIED'));
};

// Em vez de abrir a imagem em aba nova (UX antiga, perdia contexto), agora
// renderizamos um modal interno com metadata + imagem da assinatura.
// Veja `SignatureViewerModal.vue`.
const onViewSignature = session => {
  if (!session?.patient_signature_image_url) return;
  viewedSignatureSession.value = session;
  showSignatureViewerModal.value = true;
};

const onCloseSignatureViewer = () => {
  showSignatureViewerModal.value = false;
  viewedSignatureSession.value = null;
};

const showPrintModal = ref(false);
const printHtmlContent = ref('');
const printTitle = ref('');

const printRecord = () => {
  printHtmlContent.value = buildClinicalRecordHtml({
    patient: props.patient,
    sessions: sessionLogs.value,
    accountName: currentAccount.value?.name || 'Klivy',
  });
  printTitle.value = t('PATIENT_EVOLUTION.CLINICAL_RECORD.PRINT_MODAL_TITLE');
  showPrintModal.value = true;
};

onMounted(() => {
  fetchLogs();
  ensureClinicalGuardsLoaded();
  ensureActivePlanItemsLoaded();
  store.dispatch('agents/get');
});

const defaultPhone = computed(
  () => props.patient?.phone_number || props.patient?.phone || ''
);
</script>

<template>
  <div class="tab-pane fade-in evo-tab-root">
    <header class="evo-tab-header hide-on-print">
      <h2 class="evo-tab-title">
        {{ t('PATIENT_EVOLUTION.HEADER.TITLE') }}
      </h2>
      <p class="evo-tab-subtitle">
        {{ t('PATIENT_EVOLUTION.HEADER.SUBTITLE') }}
      </p>
    </header>

    <nav class="evo-subtabs hide-on-print">
      <button
        type="button"
        class="evo-subtab-btn"
        :class="{ 'is-active': activeSubtab === EVOLUTION_SUBTABS.IN_PROGRESS }"
        @click="activeSubtab = EVOLUTION_SUBTABS.IN_PROGRESS"
      >
        <i class="i-lucide-list-todo w-4 h-4" />
        {{ t('PATIENT_EVOLUTION.SUBTABS.IN_PROGRESS') }}
      </button>
      <button
        type="button"
        class="evo-subtab-btn"
        :class="{ 'is-active': activeSubtab === EVOLUTION_SUBTABS.CLINICAL_RECORD }"
        @click="activeSubtab = EVOLUTION_SUBTABS.CLINICAL_RECORD"
      >
        <i class="i-lucide-clipboard w-4 h-4" />
        {{ t('PATIENT_EVOLUTION.SUBTABS.CLINICAL_RECORD') }}
        <span v-if="sessionLogs.length > 0" class="evo-subtab-badge">
          {{ sessionLogs.length }}
        </span>
      </button>
      <button
        type="button"
        class="evo-subtab-btn"
        :class="{ 'is-active': activeSubtab === EVOLUTION_SUBTABS.EVOLUTION_HISTORY }"
        @click="activeSubtab = EVOLUTION_SUBTABS.EVOLUTION_HISTORY"
      >
        <i class="i-lucide-table w-4 h-4" />
        {{ t('PATIENT_EVOLUTION.SUBTABS.EVOLUTION_HISTORY') }}
      </button>
    </nav>

    <InProgressTreatmentsList
      v-if="activeSubtab === EVOLUTION_SUBTABS.IN_PROGRESS"
      :pending-items="pendingItems"
      :is-loading="isLoading"
      @execute-item="onExecuteItem"
    />

    <ClinicalRecordTimeline
      v-else-if="activeSubtab === EVOLUTION_SUBTABS.CLINICAL_RECORD"
      :sessions="sessionLogs"
      :is-loading="isLoading"
      :can-sign="canSign"
      :can-delete="canDelete"
      @new-session="openNewSessionModal()"
      @print="printRecord"
      @edit="openEditSessionModal"
      @sign="onSignSession"
      @mark-erratum="onRequestErratum"
      @delete="onRequestDelete"
      @request-signature="onRequestPatientSignature"
    />

    <EvolutionHistoryTable
      v-else-if="activeSubtab === EVOLUTION_SUBTABS.EVOLUTION_HISTORY"
      :sessions="sessionLogs"
      :is-loading="isLoading"
      :can-sign="canSign"
      @edit="openEditSessionModal"
      @mark-erratum="onRequestErratum"
      @request-signature="onRequestPatientSignature"
      @view-signature="onViewSignature"
    />

    <SessionFormModal
      :open="showFormModal"
      :initial-session="initialSession"
      :editing-id="editingSessionId"
      :pending-item-options="pendingItemOptions"
      :professional-options="professionalOptions"
      :is-saving="isSaving"
      :can-sign="canSign"
      @close="closeFormModal"
      @save="onFormSave"
      @select-treatment-item="onSelectTreatmentItem"
    />

    <RequestPatientSignatureModal
      :open="showSignRequestModal"
      :default-phone="defaultPhone"
      :loading="isSaving"
      @close="onSignRequestCancel"
      @confirm="onSignRequestConfirm"
    />

    <SignatureModal
      :open="showCanvasModal"
      :loading="isSaving"
      @close="onCanvasClose"
      @confirm="onCanvasConfirm"
    />

    <ClinicalGuardModal
      v-model:show="showClinicalGuardModal"
      :conflicts="detectedConflicts"
      :procedure-name="pendingClinicalProcedureName"
      :loading="isSaving"
      @confirm="onClinicalOverrideConfirm"
      @cancel="onClinicalOverrideCancel"
    />

    <ConfirmDangerModal
      v-model:show="showDeleteModal"
      :title="t('PATIENT_EVOLUTION.DELETE_DIALOG.TITLE')"
      :message="t('PATIENT_EVOLUTION.DELETE_DIALOG.DESCRIPTION')"
      :confirm-label="t('PATIENT_EVOLUTION.DELETE_DIALOG.CONFIRM')"
      @confirm="onConfirmDelete"
      @cancel="onCancelDelete"
    />

    <ErratumDialogModal
      :open="showErratumModal"
      :loading="isSaving"
      @close="onCancelErratum"
      @confirm="onConfirmErratum"
    />

    <SignatureViewerModal
      :open="showSignatureViewerModal"
      :session="viewedSignatureSession"
      @close="onCloseSignatureViewer"
    />

    <RemoteLinkInfoModal
      :open="showRemoteLinkModal"
      :url="remoteLinkUrl"
      :expires-at="remoteLinkData?.expires_at || ''"
      :patient-phone="defaultPhone"
      :patient-name="patient?.name || ''"
      @close="onCloseRemoteLinkModal"
      @copy="copyRemoteLink"
    />

    <PrintPreviewModal
      :open="showPrintModal"
      :title="printTitle"
      :html-content="printHtmlContent"
      @close="showPrintModal = false"
    />
  </div>
</template>
