/**
 * useFinancialTimeline — fetch da nova timeline financeira unificada.
 *
 * PR 2 do refactor 2026-05-06. Análogo ao `useFinancialData`, mas consome o
 * endpoint v2 `/financial/v2/patient_timelines/:id` que agrega
 * `Financial::Budget` + `Financial::Installment` + `Financial::Entry` em uma
 * lista única ordenada por data, com hierarquia pai → parcelas.
 *
 * Comportamento de fallback silencioso:
 *   • Se a account não tem a flag `financial_timeline_v2` ligada, o backend
 *     responde 404. Tratamos como `unsupported = true` (sem erro de toast),
 *     pra que o caller mostre a visão clássica como fallback natural.
 *   • Outros erros HTTP disparam toast e marcam `error`.
 *
 * Race-condition guard:
 *   • `latestRequestId` evita que resposta lenta sobrescreva resposta nova
 *     (pattern já usado em `Index.vue` e `useFinancialData`).
 *
 * Estrutura de retorno do endpoint:
 *   {
 *     meta:    { request_id, generated_at, schema_version },
 *     entries: [...],         // FinancialTimelineBuilder
 *     summary: {...},         // mesmo shape de financial_summary
 *     credit:  { balance, source, breakdown }
 *   }
 *
 * Uso:
 *   const {
 *     entries, summary, credit, meta,
 *     loading, error, unsupported,
 *     fetchTimeline, cleanup,
 *     filteredEntries,
 *   } = useFinancialTimeline(patientId, { onStatusChange });
 *
 * `onStatusChange(status)` é chamado depois de cada fetch bem-sucedido com
 * 'Adimplente' | 'Inadimplente' (mesmo contrato de useFinancialData).
 */

import { ref, computed, onBeforeUnmount, unref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import FinancialV2 from '@plugins/financial/frontend/features/financial/v2/api/financialV2';

export function useFinancialTimeline(patientIdRef, { onStatusChange } = {}) {
  const { t } = useI18n();

  const entries = ref([]);
  const summary = ref(null);
  const credit = ref(null);
  const meta = ref(null);
  const loading = ref(false);
  const error = ref(null);
  const unsupported = ref(false);

  let latestRequestId = 0;

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetchTimeline = async () => {
    const id = resolveId();
    if (!id) return;

    const requestId = ++latestRequestId;
    loading.value = true;
    error.value = null;

    try {
      // Endpoint v2 (`financial/v2/patients/:id/timeline`) retorna shape
      // idêntico ao legacy `/patients/:id/financial_timeline` — entries + summary + credit.
      // Migração canônica: aba do paciente fica visualmente igual mas alimentada
      // pelos modelos Financial::* (canon docs/01-product/modules/financeiro-funcionamento.md).
      const { data } = await FinancialV2.patient.timeline(id);

      // Race guard: se outro fetch foi disparado depois deste, descartamos.
      if (requestId !== latestRequestId) return;

      entries.value = Array.isArray(data?.entries) ? data.entries : [];
      summary.value = data?.summary || null;
      credit.value = data?.credit || null;
      meta.value = data?.meta || null;
      unsupported.value = false;

      if (typeof onStatusChange === 'function' && summary.value?.overall_status) {
        onStatusChange(
          summary.value.overall_status === 'inadimplente'
            ? 'Inadimplente'
            : 'Adimplente'
        );
      }
    } catch (err) {
      if (requestId !== latestRequestId) return;

      // 404 = feature flag desligada para esta account → fallback silencioso.
      // NÃO é erro do ponto de vista do usuário; só significa "não disponível".
      if (err.response?.status === 404) {
        unsupported.value = true;
        entries.value = [];
        summary.value = null;
        credit.value = null;
        meta.value = null;
        return;
      }

      // eslint-disable-next-line no-console
      console.error('[FinancialTimeline] Falha ao carregar timeline', err);
      error.value = err;
      useNotification.error(t('PATIENT_FINANCIAL.MESSAGES.LOAD_ERROR'));
    } finally {
      if (requestId === latestRequestId) loading.value = false;
    }
  };

  /**
   * Filtro client-side aplicado ao array de `entries` por status agregado da
   * linha-pai. Não muda os dados subjacentes — o caller passa o filtro
   * desejado e recebe um computed reativo.
   *
   * Filtros suportados:
   *   - 'all'           → tudo
   *   - 'pendente'      → entries com status pendente OU que tem parcelas em aberto
   *   - 'pago'          → entries totalmente pagas
   *   - 'vencido'       → entries com pelo menos uma parcela vencida
   *   - 'reembolsado'   → entries com status reembolsado
   *
   * Sub-filtro semântico (recurrence_type):
   *   - 'all' | 'avulso' | 'parcelamento' | 'mensalidade'
   *   - Linhas-pai do tipo Transaction (sem recurrence_type) ficam de fora
   *     dos filtros específicos `parcelamento`/`mensalidade`.
   */
  // Aceita tanto strings literais quanto refs (`unref` desempacota
   // automaticamente). Computed reativo a entries + filtros.
  const filteredEntries = (statusFilter, recurrenceFilter) =>
    computed(() => {
      const list = entries.value || [];
      const byStatus = filterByStatus(list, unref(statusFilter) || 'all');
      return filterByRecurrence(byStatus, unref(recurrenceFilter) || 'all');
    });

  const cleanup = () => {
    latestRequestId++; // invalida qualquer fetch em andamento
  };

  onBeforeUnmount(cleanup);

  return {
    entries,
    summary,
    credit,
    meta,
    loading,
    error,
    unsupported,
    fetchTimeline,
    cleanup,
    filteredEntries,
  };
}

// ───────── helpers de filtro ─────────

// Filtro por status da entry (status do orçamento agregado, vindo de
// `derive_overall_status` no backend). O chip 'em_aberto' agrupa
// `pendente` + `parcial` porque ambos têm saldo a receber — diferenciar
// só confundiria o usuário ("por que minha parcela parcial não aparece
// em Pendentes?"). Vencido fica em chip separado pra dar destaque.
function filterByStatus(list, status) {
  if (status === 'all') return list;
  if (status === 'em_aberto') {
    return list.filter(e => ['pendente', 'parcial'].includes(e.status));
  }
  if (status === 'reembolsado') return list.filter(e => e.status === 'reembolsado');
  if (status === 'pago') return list.filter(e => e.status === 'pago');
  if (status === 'vencido') return list.filter(e => e.status === 'vencido');
  if (status === 'cancelado') return list.filter(e => e.status === 'cancelado');
  // Compat: aceita 'pendente' legacy mas comporta-se como 'em_aberto'.
  if (status === 'pendente') {
    return list.filter(e => ['pendente', 'parcial'].includes(e.status));
  }
  return list;
}

function filterByRecurrence(list, recurrence) {
  if (recurrence === 'all') return list;

  // Linhas-pai do tipo Transaction não têm recurrence_type — ficam de fora
  // dos filtros específicos.
  return list.filter(e => e.recurrence_type === recurrence);
}
