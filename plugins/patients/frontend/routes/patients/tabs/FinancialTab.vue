<script setup>
/**
 * FinancialTab — Aba "Financeiro do Paciente" do prontuário.
 *
 * Após PR 3 do refactor 2026-05-06, a visão é exclusivamente a Timeline
 * unificada. Os 4 componentes legados foram deletados:
 *   - FinancialTabsBar
 *   - FinancialTransactionsTable
 *   - FinancialEstimatesList
 *   - FinancialReceiptsTable
 * Toggle clássica/timeline removido. Recibos viraram ação contextual de
 * linha (na própria timeline).
 *
 * A feature flag `financial_timeline_v2` permanece como kill-switch um
 * release inteiro: accounts sem ela veem mensagem amigável "Em manutenção"
 * (não há mais fallback para visão clássica — ela não existe).
 *
 * Recebe `patient` como prop (nome em recibo/extrato).
 * Emite `update-financial-status` para o pai sincronizar o badge no header.
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import Tooltip from '@plugins/beclinic_core/frontend/components/Tooltip.vue';
import { useFinancialData } from '@plugins/patients/frontend/features/patient-record/composables/useFinancialData';
import { useFinancialActions } from '@plugins/patients/frontend/features/patient-record/composables/useFinancialActions';
import { useFinancialTimeline } from '@plugins/patients/frontend/features/patient-record/composables/useFinancialTimeline';
import { buildExtratoHtml } from '@plugins/patients/frontend/features/patient-record/utils/financialPrintTemplates';
// Recibo individual (`downloadTransactionReceipt`) desabilitado em 2026-05-11
// (Fase A) — PDF generator v2 equivalente está em backlog. Botão "Recibo"
// da timeline mostra toast informativo enquanto isso.
import FinancialKpiGrid from '@plugins/patients/frontend/features/patient-record/components/financial-tab/FinancialKpiGrid.vue';
import FinancialTimeline from '@plugins/patients/frontend/features/patient-record/components/financial-tab/FinancialTimeline.vue';
import PayTransactionModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/PayTransactionModal.vue';
import CreateEstimateModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/CreateEstimateModal.vue';
import UploadProofModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/UploadProofModal.vue';
import PrintPreviewModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/PrintPreviewModal.vue';
import RefundTransactionModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/RefundTransactionModal.vue';
import EditInstallmentModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/EditInstallmentModal.vue';
import PlanDetailsModal from '@plugins/patients/frontend/features/patient-record/components/financial-tab/PlanDetailsModal.vue';

const props = defineProps({
  patient: { type: Object, required: true },
});
const emit = defineEmits(['update-financial-status']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();
const { currentAccount } = useAccount();
const patientId = computed(() => route.params.patientId);
const accountId = computed(() => Number(route.params.accountId));

// ── Kill-switch da feature ──
//
// `financial_timeline_v2` é gated em `Account#custom_attributes['beta_features']`
// (Patients::BetaFeatureChecker no backend). Após PR 3, a timeline é a UI
// padrão; a flag continua como kill-switch um release inteiro. Account sem a
// flag vê mensagem amigável (não há mais visão clássica para fallback).
const isTimelineFeatureEnabled = computed(() => {
  if (!accountId.value) return false;
  return store.getters['accounts/isBetaFeatureEnabledOnAccount'](
    accountId.value,
    'financial_timeline_v2'
  );
});

// ── Data fetching ──
//
// `useFinancialData` cuida do KPI grid (summary) e das contas bancárias do
// modal Receber. `useFinancialTimeline` é o source-of-truth da listagem
// renderizada — e também alimenta `buildExtratoHtml` (extrato impresso usa
// EXATAMENTE os mesmos entries da tela, evitando divergência).
const {
  financialSummary,
  bankAccounts,
  fetchFinancialData,
  loadBankAccountsForPay,
} = useFinancialData(patientId, {
  onStatusChange: status => emit('update-financial-status', status),
});

const {
  entries: timelineEntries,
  loading: timelineLoading,
  unsupported: timelineUnsupported,
  fetchTimeline,
  filteredEntries,
} = useFinancialTimeline(patientId);

// ── Filtro de status (chips na timeline) ──
// Persistência simples em ref (não localStorage — filtro é sessional).
const timelineStatusFilter = ref('all');
const timelineRecurrenceFilter = ref('all');
const timelineEntriesFiltered = filteredEntries(
  timelineStatusFilter,
  timelineRecurrenceFilter
);

const reloadAll = async () => {
  // Refresh paralelo: KPI/extrato + timeline. Falham independentemente.
  await Promise.all([fetchFinancialData(), fetchTimeline()]);
};

const {
  payLoading,
  estimateLoading,
  proofUploading,
  pay,
  chargeWhatsapp,
  refund,
  approveEstimate,
  cancelEstimate,
  uploadProof,
  createEstimate,
  editInstallment,
} = useFinancialActions(patientId, { onSuccess: reloadAll });

// Estado do modal de editar parcela (canon BUG-02).
const showEditInstallmentModal = ref(false);
const editingInstallment = ref(null);
const editingBudgetId = ref(null);
// Guarda o entry pai pra modal mostrar contexto (descrição do orçamento,
// origem PT, total atual) e preview do novo total ao mudar valor.
const editingEntry = ref(null);

const openEditInstallmentModal = ({ installment, entry }) => {
  editingInstallment.value = installment;
  editingBudgetId.value = entry?.source_id || entry?.id;
  editingEntry.value = entry || null;
  showEditInstallmentModal.value = true;
};

const onConfirmEditInstallment = async ({ budgetId, installmentId, payload }) => {
  const result = await editInstallment({ budgetId, installmentId, payload });
  if (result.ok) {
    showEditInstallmentModal.value = false;
    editingInstallment.value = null;
    editingBudgetId.value = null;
    editingEntry.value = null;
  }
};

// ── Helpers para achar parcela por id na timeline ──
// O modal de Refund/Pay/Proof recebe um `installmentId` e precisa achar a
// parcela correspondente no shape da timeline (estrutura hierárquica).
const findInstallmentById = id => {
  for (const entry of timelineEntries.value) {
    const found = (entry.installments || []).find(i => i.id === id);
    if (found) return found;
  }
  return null;
};

// `transactionsForPayModal` — adapter que achata a timeline em array plano
// no shape que o `PayTransactionModal` espera (Transaction-like) +
// enriquece com contexto do lançamento pai (origem, tipo, ícone) para o
// modal poder identificar de qual orçamento/plano cada parcela é.
const transactionsForPayModal = computed(() => {
  const flat = [];
  for (const entry of timelineEntries.value) {
    for (const inst of entry.installments || []) {
      flat.push({
        ...inst,
        installment_number: inst.number,
        total_installments: inst.total,
        // Contexto do lançamento pai (necessário pro usuário identificar
        // qual orçamento/plano está pagando quando abre pelo botão do header).
        parent_id: entry.id,
        parent_label: entry.origin?.label || entry.description,
        parent_kind: entry.origin?.kind || 'standalone',
        parent_recurrence: entry.recurrence_type || null,
      });
    }
  }
  return flat;
});

// Botão "Receber Pagamento" do header só faz sentido quando há parcelas
// passíveis de receber (pendente/vencido/parcial). Sem isso o modal abriria
// vazio com mensagem "Nenhuma parcela pendente" — péssima UX.
const hasPendingInstallments = computed(() =>
  transactionsForPayModal.value.some(tx =>
    ['pendente', 'vencido', 'parcial'].includes(tx.status)
  )
);

// ── Refund modal ──
const showRefundModal = ref(false);
const refundingTxId = ref(null);
const refundLoading = ref(false);
const refundingTx = computed(() => findInstallmentById(refundingTxId.value));

const onRefundRequest = txId => {
  refundingTxId.value = txId;
  showRefundModal.value = true;
};

const onRefundConfirm = async payload => {
  if (!refundingTxId.value) return;
  refundLoading.value = true;
  const result = await refund(refundingTxId.value, payload);
  refundLoading.value = false;
  if (result.ok) {
    showRefundModal.value = false;
    refundingTxId.value = null;
  }
};

const onRefundCancel = () => {
  showRefundModal.value = false;
  refundingTxId.value = null;
};

// ── Pay / Estimate / Proof modais ──
const showPayModal = ref(false);
const payInitialTxId = ref(null);

const showEstimateModal = ref(false);

const showProofModal = ref(false);
const proofTxId = ref(null);
const proofTransaction = computed(() => findInstallmentById(proofTxId.value));

const showPrintModal = ref(false);
const printHtmlContent = ref('');
const printTitle = ref('');

const openPayModal = (txId = null) => {
  payInitialTxId.value = txId;
  showPayModal.value = true;
};

const handlePayConfirm = async ({ txId, payload }) => {
  const { ok } = await pay(txId, payload);
  if (ok) showPayModal.value = false;
};

const openEstimateModal = () => {
  showEstimateModal.value = true;
};

const handleEstimateConfirm = async payload => {
  const { ok } = await createEstimate(payload);
  if (ok) showEstimateModal.value = false;
};

const openProofModal = txId => {
  proofTxId.value = txId;
  showProofModal.value = true;
};

const handleProofUpload = async file => {
  const { ok } = await uploadProof(proofTxId.value, file);
  if (ok) showProofModal.value = false;
};

const openPrintPreview = (html, title) => {
  printHtmlContent.value = html;
  printTitle.value = title;
  showPrintModal.value = true;
};

const printFinancial = () => {
  // Source-of-truth única: `timelineEntries` (mesma estrutura que alimenta
  // a `FinancialTimeline.vue` na aba). Garante que extrato impresso = tela.
  const html = buildExtratoHtml({
    patient: props.patient,
    summary: financialSummary.value,
    entries: timelineEntries.value,
    accountName: currentAccount.value?.name || 'Klivy',
  });
  openPrintPreview(html, t('PATIENT_FINANCIAL.PRINT.STATEMENT_TITLE'));
};

const loadingReceiptTxId = ref(null);

// Stub: PDF de recibo individual está em backlog (gerador v2 não implementado
// após remoção do `Patients::ReceiptPdfGenerator` legacy). Toast informa o
// usuário em vez de deixar o botão silenciosamente quebrado.
const printReceipt = async tx => {
  if (!tx?.id) return;
  useNotification.info(
    'Recibo individual em PDF está sendo reimplementado. Use Imprimir Extrato como alternativa.'
  );
};

// ── Handlers de eventos da timeline ──
// A timeline emite eventos com `installment_id` ou `entry`; mapeamos pros
// modais e composables existentes (zero duplicação de fluxo).

const onTimelineApproveEstimate = async entry => {
  await approveEstimate(entry.source_id);
};

const onTimelineCancelEstimate = async entry => {
  await cancelEstimate(entry.source_id);
};

const onTimelineReceipt = async installment => {
  await printReceipt(installment);
};

const onTimelineViewProof = inst => {
  if (inst?.payment_proof_url) window.open(inst.payment_proof_url, '_blank');
};

const onTimelineUploadProof = inst => {
  if (inst?.id) openProofModal(inst.id);
};

const onTimelineChargeWhatsapp = installmentId => {
  chargeWhatsapp(installmentId);
};

// Estado do modal de detalhes do PT (peek do plano sem sair do Financeiro).
const showPlanDetailsModal = ref(false);
const planDetailsId = ref(null);

const onTimelineOpenLink = entry => {
  // UX: abrir modal "peek" com detalhes do PT em vez de navegar direto.
  // O usuário pode ver itens/total/profissional sem perder o contexto do
  // financeiro. Pra ver completo, modal tem botão "Abrir no Plano de
  // Tratamento" que faz a navegação real.
  if (entry?.origin?.kind === 'treatment_plan' && entry.origin.link) {
    planDetailsId.value = entry.origin.link;
    showPlanDetailsModal.value = true;
  }
};

const onOpenPlanInTab = ({ planId }) => {
  // Mesma navegação que existia antes — agora disparada pelo botão dentro
  // do modal de detalhes. Usa `router.replace` (mesmo pattern do Record.vue:154):
  // muda `?tab=` na URL e o `Record.vue` reage via watch trocando de tab.
  showPlanDetailsModal.value = false;
  router.replace({
    query: {
      ...route.query,
      tab: 'treatment_plan',
      treatment_plan_id: planId,
    },
  }).catch(() => {});
};

onMounted(async () => {
  await fetchFinancialData();
  if (isTimelineFeatureEnabled.value) {
    await fetchTimeline();
  }
  loadBankAccountsForPay();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <!-- Header -->
    <div class="reg-header mb-5">
      <div>
        <h3 class="text-xl font-semibold text-slate-100">
          {{ t('PATIENT_FINANCIAL.HEADER.TITLE') }}
        </h3>
        <p class="text-sm text-slate-400 mt-0.5">
          {{ t('PATIENT_FINANCIAL.HEADER.SUBTITLE') }}
        </p>
      </div>
      <div class="flex items-center gap-3">
        <BeclinicButton
          variant="ghost"
          color="slate"
          icon="i-lucide-printer"
          :label="t('PATIENT_FINANCIAL.HEADER.PRINT_STATEMENT')"
          @click="printFinancial"
        />
        <BeclinicButton
          v-can="['financial', 'create_estimate']"
          variant="faded"
          color="slate"
          icon="i-lucide-file-plus"
          :label="t('PATIENT_FINANCIAL.HEADER.NEW_ENTRY')"
          @click="openEstimateModal"
        />
        <!-- Receber Pagamento desabilitado quando não há parcelas pendentes —
             evita modal vazio com mensagem "Nenhuma parcela pendente". Pra
             criar lançamento novo, usa o botão "Novo Lançamento" ao lado. -->
        <Tooltip
          :label="hasPendingInstallments ? '' : 'Sem parcelas pendentes — crie um lançamento primeiro'"
          :disabled="hasPendingInstallments"
        >
          <BeclinicButton
            v-can="['financial', 'create_transaction']"
            variant="solid"
            color="teal"
            icon="i-lucide-receipt"
            :label="t('PATIENT_FINANCIAL.HEADER.RECEIVE_PAYMENT')"
            :disabled="!hasPendingInstallments"
            @click="openPayModal(null)"
          />
        </Tooltip>
      </div>
    </div>

    <FinancialKpiGrid :summary="financialSummary" />

    <!-- Kill-switch: account sem a flag vê mensagem amigável.
         A visão clássica foi deletada no PR 3 — não há fallback. -->
    <div v-if="!isTimelineFeatureEnabled" class="fin-tl-fallback">
      <i class="i-lucide-info w-4 h-4 mr-1.5" />
      {{ t('PATIENT_FINANCIAL.TIMELINE.FEATURE_DISABLED_HINT') }}
    </div>

    <!-- Aviso para desincronização (flag local on, backend retorna 404) -->
    <div v-else-if="timelineUnsupported" class="fin-tl-fallback">
      <i class="i-lucide-info w-4 h-4 mr-1.5" />
      {{ t('PATIENT_FINANCIAL.TIMELINE.UNSUPPORTED_HINT') }}
    </div>

    <FinancialTimeline
      v-else
      v-model:filter="timelineStatusFilter"
      :entries="timelineEntriesFiltered"
      :loading="timelineLoading"
      :loading-receipt-id="loadingReceiptTxId"
      @pay="openPayModal"
      @refund="onRefundRequest"
      @charge-whatsapp="onTimelineChargeWhatsapp"
      @receipt="onTimelineReceipt"
      @upload-proof="onTimelineUploadProof"
      @view-proof="onTimelineViewProof"
      @approve-estimate="onTimelineApproveEstimate"
      @cancel-estimate="onTimelineCancelEstimate"
      @open-link="onTimelineOpenLink"
      @edit-installment="openEditInstallmentModal"
    />

    <PrintPreviewModal
      :open="showPrintModal"
      :title="printTitle"
      :html-content="printHtmlContent"
      @close="showPrintModal = false"
    />

    <UploadProofModal
      :open="showProofModal"
      :transaction="proofTransaction"
      :uploading="proofUploading"
      @close="showProofModal = false"
      @upload="handleProofUpload"
    />

    <PayTransactionModal
      :open="showPayModal"
      :initial-tx-id="payInitialTxId"
      :transactions="transactionsForPayModal"
      :bank-accounts="bankAccounts"
      :patient="patient"
      :loading="payLoading"
      @close="showPayModal = false"
      @confirm="handlePayConfirm"
    />

    <CreateEstimateModal
      :open="showEstimateModal"
      :loading="estimateLoading"
      @close="showEstimateModal = false"
      @confirm="handleEstimateConfirm"
    />

    <RefundTransactionModal
      :open="showRefundModal"
      :transaction="refundingTx"
      :loading="refundLoading"
      @close="onRefundCancel"
      @confirm="onRefundConfirm"
    />

    <EditInstallmentModal
      :open="showEditInstallmentModal"
      :installment="editingInstallment"
      :budget-id="editingBudgetId"
      :entry="editingEntry"
      :loading="estimateLoading"
      @close="showEditInstallmentModal = false"
      @confirm="onConfirmEditInstallment"
    />

    <PlanDetailsModal
      :open="showPlanDetailsModal"
      :plan-id="planDetailsId"
      :patient-id="patientId"
      @close="showPlanDetailsModal = false"
      @open-in-tab="onOpenPlanInTab"
    />
  </div>
</template>
