/**
 * useFinancialData — fetch agregado dos dados financeiros do paciente.
 *
 * Migrado pra v2 em 2026-05-11 (Fase A da depreciação v1):
 *   • Resumo (KPIs) — endpoint v2 `patient_summaries`
 *   • Contas bancárias (best-effort, para o modal Receber) — endpoint v2 `bank_accounts`
 *
 * O extrato impresso (`buildExtratoHtml`) passou a consumir a timeline v2
 * (`useFinancialTimeline.entries`) a partir de 2026-05-12 — os refs
 * `transactions`/`financialEstimates` legacy (que ficavam vazios após a Fase
 * A) foram removidos pra evitar regressão de "Nenhuma transação" no PDF.
 *
 * Uso:
 *   const { financialSummary, bankAccounts, financialLoading,
 *           fetchFinancialData, loadBankAccountsForPay } =
 *     useFinancialData(patientId, { onStatusChange });
 *
 * `onStatusChange(status)` é chamado depois de cada fetch com 'Adimplente' |
 * 'Inadimplente' — usado pelo pai pra emitir `update-financial-status`.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import FinancialV2 from '@plugins/financial/frontend/features/financial/v2/api/financialV2';

export function useFinancialData(patientIdRef, { onStatusChange } = {}) {
  const { t } = useI18n();

  const financialSummary = ref(null);
  const bankAccounts = ref([]);
  const financialLoading = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function' ? patientIdRef() : patientIdRef?.value ?? patientIdRef;

  const fetchFinancialData = async () => {
    const id = resolveId();
    if (!id) return;
    financialLoading.value = true;
    try {
      // Summary do endpoint v2 (Financial::* models). Campos: total_approved,
      // total_paid, total_open, total_overdue, credit_balance, overall_status,
      // next_due_date, next_due_amount.
      const summaryRes = await FinancialV2.patient.summary(id);

      financialSummary.value = summaryRes.data;
      if (typeof onStatusChange === 'function' && summaryRes.data?.overall_status) {
        onStatusChange(
          summaryRes.data.overall_status === 'inadimplente'
            ? 'Inadimplente'
            : 'Adimplente'
        );
      }
    } catch (error) {
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao carregar dados financeiros', error);
      useNotification.error(t('PATIENT_FINANCIAL.MESSAGES.LOAD_ERROR'));
    } finally {
      financialLoading.value = false;
    }
  };

  // Best-effort: se a API de contas falhar, o modal de pagamento ainda
  // funciona sem o seletor. Sem alert ao usuário — não é fluxo principal.
  // Lê do endpoint v2 (`financial/v2/bank_accounts`) — schema novo com kind
  // (checking|savings|cash|card_receivable) e initial_balance_cents.
  const loadBankAccountsForPay = async () => {
    try {
      const { data } = await FinancialV2.bankAccounts.index();
      // v2 retorna `{ data: [...] }`; legacy retornava `{ bank_accounts: [...] }`.
      // Normaliza para o shape esperado pelos consumers (PayTransactionModal).
      const list = data?.data || data?.bank_accounts || [];
      bankAccounts.value = list.map((b) => ({
        id: b.id,
        name: b.name,
        // Adiciona campos legacy esperados pelo modal sem breaking change visual.
        account_type: b.kind,
        bank_name: b.bank_name,
        initial_balance: b.initial_balance_cents != null ? b.initial_balance_cents / 100 : 0,
        active: b.active,
      }));
    } catch (error) {
      bankAccounts.value = [];
      // eslint-disable-next-line no-console
      console.error('[Financial] Falha ao carregar contas bancárias', error);
    }
  };

  return {
    financialSummary,
    bankAccounts,
    financialLoading,
    fetchFinancialData,
    loadBankAccountsForPay,
  };
}
