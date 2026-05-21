<script setup>
/**
 * TreatmentPlanTab — Aba "Plano de Tratamento" do prontuário.
 *
 * Orquestrador. Composição:
 *   • useTreatmentPlans — fetch + plan CRUD + item CRUD (com lock_version #13)
 *   • usePatientClinicalGuards — guard #16 cruzando procedimento ↔ anamnese
 *   • treatment-plan-tab/* (4 sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota. Recebe `agendaServices` para o
 * dropdown de procedimentos (cada serviço tem nome + preço).
 */
import { ref, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useI18n } from 'vue-i18n';
import ConfirmDangerModal from '@plugins/beclinic_core/frontend/components/ConfirmDangerModal.vue';
import ClinicalGuardModal from '@plugins/beclinic_core/frontend/components/ClinicalGuardModal.vue';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';
import { useTreatmentPlans } from '@plugins/patients/frontend/features/patient-record/composables/useTreatmentPlans';
import { usePatientClinicalGuards } from '@plugins/patients/frontend/features/patient-record/composables/usePatientClinicalGuards';
import TreatmentPlanHeader from '@plugins/patients/frontend/features/patient-record/components/treatment-plan-tab/TreatmentPlanHeader.vue';
import TreatmentPlanCard from '@plugins/patients/frontend/features/patient-record/components/treatment-plan-tab/TreatmentPlanCard.vue';
import TreatmentItemModal from '@plugins/patients/frontend/features/patient-record/components/treatment-plan-tab/TreatmentItemModal.vue';

const props = defineProps({
  agendaServices: { type: Array, default: () => [] },
});

const { t } = useI18n();
const route = useRoute();

const {
  treatmentPlans,
  isSavingItem,
  fetch: fetchPlans,
  create: createPlanAction,
  updatePlan,
  updatePlanSilent,
  approvePlan,
  deletePlan,
  saveItem,
  deleteItem,
} = useTreatmentPlans(() => route.params.patientId);

const {
  ensureLoaded: ensureClinicalGuardsLoaded,
  checkProcedureForConflicts,
} = usePatientClinicalGuards(route.params.patientId);

// ── Local state ────────────────────────────────────────────
const editingPlanId = ref(null);
const isCreatingPlan = ref(false);

const showItemModal = ref(false);
const activePlanId = ref(null);
const editingItem = ref(null);
// Quando true, fecha modal de item via "Adicionar depois" (skip) em vez de
// "Cancelar". Usado no fluxo encadeado: criar plano → abrir item modal.
const isItemModalChained = ref(false);

const showConfirmDeletePlan = ref(false);
const planToDelete = ref(null);

// Cascade (canon Regra 3 — PT com Budget v2 aprovado SEM pagamento).
// Backend retorna 409 + cascade_required; segunda confirmação envia
// header X-Confirm-Cascade pra cancelar Budget + soft-delete PT atomicamente.
const showConfirmCascadeDelete = ref(false);
const cascadeBudget = ref(null);

const showConfirmDeleteItem = ref(false);
const itemToDelete = ref({ planId: null, itemId: null });

const showClinicalGuardModal = ref(false);
const detectedConflicts = ref([]);
const pendingClinicalProcedureName = ref('');
const pendingItemPayload = ref(null);

// ── Handlers: plano ────────────────────────────────────────
// Fluxo "Novo Plano": só abre o modal de procedimento. Plano é criado
// apenas quando o usuário salva o primeiro procedimento. Cancelar = nada
// persistido (sem planos vazios poluindo a lista).
const openNewPlanModal = () => {
  editingPlanId.value = null;
  activePlanId.value = null; // null = sinaliza fluxo de novo plano
  editingItem.value = null;
  isItemModalChained.value = true;
  showItemModal.value = true;
};

const handleSavePlan = async plan => {
  const { ok } = await updatePlan(plan);
  if (ok) editingPlanId.value = null;
};

const handleApprovePlan = async planId => {
  const { ok } = await approvePlan(planId);
  if (ok) editingPlanId.value = null;
};

const requestDeletePlan = planId => {
  planToDelete.value = planId;
  showConfirmDeletePlan.value = true;
};

const cancelDeletePlan = () => {
  showConfirmDeletePlan.value = false;
  planToDelete.value = null;
};

const confirmDeletePlan = async () => {
  if (!planToDelete.value) return;
  const result = await deletePlan(planToDelete.value);

  // Canon Regra 3: 409 cascade_required → abre confirmação dupla.
  // O planToDelete fica preservado pra reusar na 2ª confirmação.
  if (result.cascade) {
    cascadeBudget.value = result.budget;
    showConfirmDeletePlan.value = false;
    showConfirmCascadeDelete.value = true;
    return;
  }

  cancelDeletePlan();
};

const cancelCascadeDelete = () => {
  showConfirmCascadeDelete.value = false;
  cascadeBudget.value = null;
  planToDelete.value = null;
};

const confirmCascadeDelete = async () => {
  if (!planToDelete.value) return;
  await deletePlan(planToDelete.value, { confirmCascade: true });
  cancelCascadeDelete();
};

// Backend retorna `budget.total` em BRL (já dividido por 100), não em centavos.
const formatBRL = value => {
  const n = typeof value === 'number' ? value : Number(value) || 0;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(n);
};

// ── Handlers: item modal ───────────────────────────────────
const openItemModal = async (plan, item = null) => {
  // Flush edits pendentes do plano antes de abrir o modal de item.
  if (editingPlanId.value === plan.id) {
    const { ok } = await updatePlanSilent(plan);
    if (!ok) return;
    editingPlanId.value = null;
  }
  activePlanId.value = plan.id;
  editingItem.value = item ? { ...item } : null;
  isItemModalChained.value = false;
  showItemModal.value = true;
};

const closeItemModal = () => {
  showItemModal.value = false;
  isItemModalChained.value = false;
};

// Garante que existe um plano para receber o item. Se `activePlanId` for
// null (fluxo de "Novo Plano"), cria um plano vazio e retorna o id. Se já
// existe (edição/adicionar a plano existente), só devolve o id atual.
const ensureActivePlan = async () => {
  if (activePlanId.value) return activePlanId.value;

  isCreatingPlan.value = true;
  try {
    const { ok, id } = await createPlanAction({ title: '', description: '' });
    if (ok && id) {
      activePlanId.value = id;
      return id;
    }
    return null;
  } finally {
    isCreatingPlan.value = false;
  }
};

const handleItemSave = async itemPayload => {
  await ensureClinicalGuardsLoaded();
  const conflicts = checkProcedureForConflicts({
    procedureName: itemPayload.procedure_name,
    productName: '',
  });

  if (conflicts.length > 0) {
    detectedConflicts.value = conflicts;
    pendingClinicalProcedureName.value = itemPayload.procedure_name;
    pendingItemPayload.value = itemPayload;
    showClinicalGuardModal.value = true;
    return;
  }

  const planId = await ensureActivePlan();
  if (!planId) return; // falha ao criar o plano — useNotification já avisou

  const { ok } = await saveItem(planId, itemPayload);
  if (ok) closeItemModal();
};

const onClinicalOverrideConfirm = async reason => {
  showClinicalGuardModal.value = false;
  if (!pendingItemPayload.value) return;

  const planId = await ensureActivePlan();
  if (!planId) {
    pendingItemPayload.value = null;
    return;
  }

  const { ok } = await saveItem(planId, pendingItemPayload.value, {
    clinicalOverrideReason: reason,
  });
  if (ok) closeItemModal();
  detectedConflicts.value = [];
  pendingClinicalProcedureName.value = '';
  pendingItemPayload.value = null;
};

const onClinicalOverrideCancel = () => {
  detectedConflicts.value = [];
  pendingClinicalProcedureName.value = '';
  pendingItemPayload.value = null;
};

// ── Handlers: delete item ──────────────────────────────────
const requestDeleteItem = (planId, itemId) => {
  itemToDelete.value = { planId, itemId };
  showConfirmDeleteItem.value = true;
};

const cancelDeleteItem = () => {
  showConfirmDeleteItem.value = false;
  itemToDelete.value = { planId: null, itemId: null };
};

const confirmDeleteItem = async () => {
  if (!itemToDelete.value.planId || !itemToDelete.value.itemId) return;
  await deleteItem(itemToDelete.value.planId, itemToDelete.value.itemId);
  cancelDeleteItem();
};

// ── Handlers: PDF / print ──────────────────────────────────
// `loadingPdfPlanId` rastreia o plano atualmente em download para
// dar feedback visual no botão (spinner + disabled) e bloquear cliques
// duplicados que abrem múltiplas abas.
const loadingPdfPlanId = ref(null);

// Usa axios + blob (responseType) em vez de window.open(url) — o endpoint
// `/treatment_plans/:id/pdf` exige `api_access_token` no header, e nova aba
// aberta com `window.open` não envia esse header (cai em 401 do Devise).
const openPdf = async plan => {
  if (!plan?.id || !plan?.pdf_url) return;
  if (loadingPdfPlanId.value === plan.id) return;

  loadingPdfPlanId.value = plan.id;
  try {
    const res = await TreatmentPlansAPI.downloadPdf(
      route.params.patientId,
      plan.id
    );
    const blob = new Blob([res.data], { type: 'application/pdf' });
    const url = URL.createObjectURL(blob);
    window.open(url, '_blank', 'noopener,noreferrer');
    setTimeout(() => URL.revokeObjectURL(url), 10000);
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[TreatmentPlan] Falha ao baixar PDF', err);
  } finally {
    loadingPdfPlanId.value = null;
  }
};

onMounted(() => {
  fetchPlans();
  ensureClinicalGuardsLoaded();
});
</script>

<template>
  <div class="tab-pane fade-in print-section">
    <TreatmentPlanHeader @create-plan="openNewPlanModal" />

    <div class="rp-content-grid">
      <div
        v-if="!treatmentPlans || treatmentPlans.length === 0"
        class="rp-empty"
      >
        <div class="rp-empty-icon">
          <i class="i-lucide-clipboard-list" />
        </div>
        <p class="rp-empty-text">{{ t('PATIENT_TREATMENT_PLAN.EMPTY.TITLE') }}</p>
        <p class="rp-empty-hint">{{ t('PATIENT_TREATMENT_PLAN.EMPTY.HINT') }}</p>
      </div>

      <TreatmentPlanCard
        v-for="plan in treatmentPlans"
        :key="plan.id"
        :plan="plan"
        :is-editing="editingPlanId === plan.id"
        :is-pdf-loading="loadingPdfPlanId === plan.id"
        @edit-plan="editingPlanId = $event.id"
        @save-plan="handleSavePlan"
        @approve-plan="handleApprovePlan"
        @delete-plan="requestDeletePlan"
        @add-item="openItemModal"
        @edit-item="openItemModal"
        @delete-item="requestDeleteItem"
        @open-pdf="openPdf"
      />
    </div>

    <TreatmentItemModal
      :open="showItemModal"
      :initial-item="editingItem"
      :agenda-services="props.agendaServices"
      :loading="isSavingItem"
      :allow-skip="isItemModalChained"
      @close="closeItemModal"
      @skip="closeItemModal"
      @save="handleItemSave"
    />

    <ConfirmDangerModal
      v-model:show="showConfirmDeleteItem"
      :title="t('PATIENT_TREATMENT_PLAN.DELETE_ITEM_MODAL.TITLE')"
      :message="t('PATIENT_TREATMENT_PLAN.DELETE_ITEM_MODAL.MESSAGE')"
      :confirm-label="t('PATIENT_TREATMENT_PLAN.DELETE_ITEM_MODAL.CONFIRM')"
      @confirm="confirmDeleteItem"
      @cancel="cancelDeleteItem"
    />

    <ConfirmDangerModal
      v-model:show="showConfirmDeletePlan"
      :title="t('PATIENT_TREATMENT_PLAN.DELETE_PLAN_MODAL.TITLE')"
      :message="t('PATIENT_TREATMENT_PLAN.DELETE_PLAN_MODAL.MESSAGE')"
      :confirm-label="t('PATIENT_TREATMENT_PLAN.DELETE_PLAN_MODAL.CONFIRM')"
      @confirm="confirmDeletePlan"
      @cancel="cancelDeletePlan"
    />

    <!-- Confirmação dupla — canon Regra 3, cenário 2:
         PT tem Budget v2 aprovado SEM pagamento. Confirmar cancela Budget
         + soft-deleta PT atomicamente. Mensagem mostra dados do Budget
         pra usuário entender o impacto antes de confirmar. -->
    <ConfirmDangerModal
      v-model:show="showConfirmCascadeDelete"
      title="Excluir plano e cancelar orçamento?"
      confirm-label="Sim, excluir plano e cancelar orçamento"
      cancel-label="Voltar"
      @confirm="confirmCascadeDelete"
      @cancel="cancelCascadeDelete"
    >
      <p style="margin: 0; font-size: 13px; line-height: 1.5;">
        Este plano tem um orçamento financeiro vinculado (sem pagamentos
        recebidos ainda).
      </p>
      <div
        v-if="cascadeBudget"
        style="
          margin: 6px 0;
          padding: 8px 10px;
          border-radius: 8px;
          background: rgb(var(--slate-3));
          font-size: 13px;
          line-height: 1.5;
        "
      >
        <strong>Orçamento #{{ cascadeBudget.id }}</strong> ·
        {{ cascadeBudget.status }} ·
        <strong>{{ formatBRL(cascadeBudget.total) }}</strong>
      </div>
      <p style="margin: 0; font-size: 13px; line-height: 1.5;">
        Excluir o plano vai <strong>cancelar este orçamento</strong> e arquivar
        o plano. Essa ação não pode ser desfeita.
      </p>
    </ConfirmDangerModal>

    <ClinicalGuardModal
      v-model:show="showClinicalGuardModal"
      :conflicts="detectedConflicts"
      :procedure-name="pendingClinicalProcedureName"
      :loading="isSavingItem"
      @confirm="onClinicalOverrideConfirm"
      @cancel="onClinicalOverrideCancel"
    />
  </div>
</template>
