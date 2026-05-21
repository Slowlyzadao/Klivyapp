/**
 * useFinancialActions — mutações financeiras do paciente (Roadmap #12).
 *
 * Concentra as 7 mutações que estavam inline em FinancialTab.vue, com
 * tratamento de erro padronizado (toast via useNotification) e invalidação
 * via callback `onSuccess` (tipicamente `fetchFinancialData`).
 *
 *   pay(txId, payload)              → registra pagamento
 *   chargeWhatsapp(txId)            → abre wa.me com mensagem pronta
 *   refund(txId)                    → estorna (pede confirm nativo)
 *   approveEstimate(estimateId)     → aprova orçamento (gera parcelas)
 *   cancelEstimate(estimateId)      → cancela orçamento
 *   uploadProof(txId, file)         → anexa comprovante
 *   createEstimate(payload)         → cria orçamento avulso
 *
 * Cada método retorna `{ ok: boolean, data?: any }` — caller pode reagir sem
 * try/catch. Em caso de erro de validação (estimates), repassa a mensagem
 * do backend.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
// Todos os métodos abaixo consomem `FinancialV2` (Financial::* namespace).
import FinancialV2 from '@plugins/financial/frontend/features/financial/v2/api/financialV2';

export function useFinancialActions(patientIdRef, { onSuccess } = {}) {
  const { t } = useI18n();

  const payLoading = ref(false);
  const estimateLoading = ref(false);
  const proofUploading = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const refresh = async () => {
    if (typeof onSuccess === 'function') await onSuccess();
  };

  const pay = async (txId, payload) => {
    if (!txId) return { ok: false };
    payLoading.value = true;
    try {
      // Endpoint v2: POST /financial/v2/installments/:id/pay
      // Cria PaymentReceipt + atualiza Installment.received_amount_cents +
      // dispara Financial::Entry de entrada na conta destino + atualiza
      // CommissionEntry. Tudo em transação atômica (canon §5.3).
      // Suporta baixa parcial (BUG-01) via amount_cents < remaining,
      // juros/multa/desconto, abater crédito do paciente, observações,
      // e keep_installment_open (controle de geração de nova parcela).
      await FinancialV2.installments.pay(txId, {
        payment_method: payload?.payment_method,
        paid_at: payload?.paid_at,
        bank_account_id: payload?.bank_account_id,
        amount_cents: payload?.amount_cents,
        interest_cents: payload?.interest_cents,
        fine_cents: payload?.fine_cents,
        discount_cents: payload?.discount_cents,
        apply_patient_credit_cents: payload?.apply_patient_credit_cents,
        keep_installment_open: payload?.keep_installment_open,
        notes: payload?.notes,
      });
      useNotification.success(t('PATIENT_FINANCIAL.MESSAGES.PAY_SUCCESS'));
      await refresh();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao registrar pagamento', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  t('PATIENT_FINANCIAL.MESSAGES.PAY_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      payLoading.value = false;
    }
  };

  const chargeWhatsapp = async txId => {
    try {
      // Endpoint v2 retorna { phone, whatsapp_message } — frontend abre wa.me
      // (deep link). Sem envio em background — operador clica e o WhatsApp abre
      // com a mensagem pré-formatada para revisar e disparar manualmente.
      const res = await FinancialV2.installments.chargeWhatsapp(txId);
      const msg = res.data?.whatsapp_message || '';
      const phone = res.data?.phone || '';
      if (phone) {
        const url = `https://wa.me/${phone.replace(/\D/g, '')}?text=${encodeURIComponent(msg)}`;
        window.open(url, '_blank');
        return { ok: true };
      }
      useNotification.warning(t('PATIENT_FINANCIAL.MESSAGES.WHATSAPP_NO_PHONE'));
      return { ok: false };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao preparar cobrança WhatsApp', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  t('PATIENT_FINANCIAL.MESSAGES.WHATSAPP_ERROR');
      useNotification.error(msg);
      return { ok: false };
    }
  };

  // Confirmação de UI agora fica no componente (`RefundTransactionModal`
  // no FinancialTab). Composable só executa — separação de concerns:
  // lógica de negócio aqui, UX modal lá.
  //
  // `payload` opcional aceita { amount, notes, payment_method } pra
  // estorno parcial / com motivo / em método diferente do original.
  // Sem payload → backend reembolsa o valor cheio com método original.
  const refund = async (txId, payload = {}) => {
    try {
      // Endpoint v2: POST /financial/v2/installments/:id/refund
      // Estorna o último PaymentReceipt da Installment (efeitos atômicos
      // canônicos: parcela volta a status, conta saldo, entry estorno,
      // comissão revertida — canon §7.3).
      // Suporta estorno parcial via amount_cents < received.
      await FinancialV2.installments.refund(txId, {
        amount_cents: payload?.amount_cents,
        payment_method: payload?.payment_method,
        notes: payload?.notes,
        generate_patient_credit: payload?.generate_patient_credit,
      });
      useNotification.success(t('PATIENT_FINANCIAL.MESSAGES.REFUND_SUCCESS'));
      await refresh();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao estornar transação', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  t('PATIENT_FINANCIAL.MESSAGES.REFUND_ERROR');
      useNotification.error(msg);
      return { ok: false };
    }
  };

  const approveEstimate = async estimateId => {
    try {
      // Endpoint v2: POST /financial/v2/budgets/:id/approve
      // Aceita installments_plan opcional; sem ele, distribui valor total em
      // N parcelas iguais conforme `installments_count` do budget.
      await FinancialV2.budgets.approve(estimateId, {});
      useNotification.success(t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_APPROVED'));
      await refresh();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao aprovar orçamento', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_APPROVE_ERROR');
      useNotification.error(msg);
      return { ok: false };
    }
  };

  // Editar uma única parcela pendente (canon BUG-02). Backend valida que a
  // parcela ainda não recebeu pagamento — caso contrário retorna 422 e o
  // composable repassa a mensagem.
  const editInstallment = async ({ budgetId, installmentId, payload }) => {
    if (!budgetId || !installmentId) return { ok: false };
    estimateLoading.value = true;
    try {
      // PATCH /financial/v2/budgets/:id/update_installments espera array.
      await FinancialV2.budgets.updateInstallments(budgetId, [
        {
          id: installmentId,
          amount_cents: payload.amount_cents,
          due_date: payload.due_date,
          payment_method: payload.payment_method,
        },
      ]);
      useNotification.success('Parcela atualizada');
      await refresh();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao editar parcela', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  error.response?.data?.error ||
                  'Erro ao atualizar parcela';
      useNotification.error(msg);
      return { ok: false };
    } finally {
      estimateLoading.value = false;
    }
  };

  const cancelEstimate = async estimateId => {
    try {
      // Endpoint v2: POST /financial/v2/budgets/:id/cancel
      await FinancialV2.budgets.cancel(estimateId, { reason: 'Cancelado pela aba do paciente' });
      useNotification.info(t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_CANCELLED'));
      await refresh();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao cancelar orçamento', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_CANCEL_ERROR');
      useNotification.error(msg);
      return { ok: false };
    }
  };

  const uploadProof = async (txId, file) => {
    if (!file) return { ok: false };
    proofUploading.value = true;
    try {
      // Endpoint v2: POST /financial/v2/installments/:id/upload_proof  (multipart)
      // Anexa via Active Storage à Installment v2. Retorna URL signed (15 min).
      await FinancialV2.installments.uploadProof(txId, file);
      useNotification.success(t('PATIENT_FINANCIAL.MESSAGES.PROOF_SUCCESS'));
      await refresh();
      return { ok: true };
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao anexar comprovante', error);
      const msg = error.response?.data?.errors?.join(', ') ||
                  t('PATIENT_FINANCIAL.MESSAGES.PROOF_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      proofUploading.value = false;
    }
  };

  // Adapta payload do CreateEstimateModal (legacy shape) para o body esperado
  // pelo FinancialV2.budgets.create. Mantém `CreateEstimateModal.vue` intacto
  // (sem mudar visual) — só o composable traduz o shape antigo para o v2.
  //
  // legacy payload:
  //   { recurrence_type, subtotal, discount_type, discount_value,
  //     installments_count, payment_method, notes, valid_until }
  //
  // v2 budget body:
  //   { budget: { patient_id, origin, status, installments_count, payment_method,
  //               notes, valid_until, discount_kind, discount_basis_points|discount_cents,
  //               items: [{ description, quantity, unit_price_cents, total_cents }] } }
  const buildBudgetPayloadFromLegacy = (legacy, patientId) => {
    const subtotalCents = Math.round((Number(legacy.subtotal) || 0) * 100);
    const discountValue = Number(legacy.discount_value) || 0;
    const discountKind = legacy.discount_type || null;
    const installments = parseInt(legacy.installments_count, 10) || 1;

    const origin = legacy.recurrence_type === 'mensalidade' ? 'mensalidade' : 'orcamento';

    const budget = {
      patient_id: patientId,
      origin,
      status: 'rascunho',
      installments_count: installments,
      payment_method: legacy.payment_method,
      notes: legacy.notes || null,
      valid_until: legacy.valid_until || null,
      discount_kind: discountKind,
      items: [
        {
          description: legacy.notes?.slice(0, 200) || 'Lançamento avulso',
          quantity: 1,
          unit_price_cents: subtotalCents,
          total_cents: subtotalCents,
        },
      ],
    };

    if (discountKind === 'percentual') {
      // 5,00% → 500 basis points
      budget.discount_basis_points = Math.round(discountValue * 100);
      budget.discount_cents = Math.round((subtotalCents * discountValue) / 100);
    } else if (discountKind === 'fixo') {
      budget.discount_cents = Math.round(discountValue * 100);
    }

    return { budget };
  };

  const createEstimate = async payload => {
    if (!payload?.subtotal || payload.subtotal <= 0) {
      useNotification.warning(
        t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_INVALID_SUBTOTAL')
      );
      return { ok: false };
    }
    estimateLoading.value = true;
    try {
      // POST /financial/v2/budgets — cria como rascunho (precisa aprovar
      // depois para gerar as parcelas em A Receber, igual fluxo legacy).
      const v2Payload = buildBudgetPayloadFromLegacy(payload, resolveId());
      const res = await FinancialV2.budgets.create(v2Payload);
      useNotification.success(t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_CREATED'));
      await refresh();
      return { ok: true, data: res.data };
    } catch (error) {
      const msg =
        error.response?.data?.errors?.join(', ') ||
        t('PATIENT_FINANCIAL.MESSAGES.ESTIMATE_CREATE_ERROR');
      useNotification.error(msg);
      return { ok: false };
    } finally {
      estimateLoading.value = false;
    }
  };

  return {
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
  };
}
