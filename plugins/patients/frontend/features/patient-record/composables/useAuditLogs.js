/**
 * useAuditLogs — fetch read-only de logs de auditoria com filtros + paginação.
 *
 *   fetch()                → carrega página atual com filtros aplicados
 *   applyFilters()         → reseta para page 1 e recarrega
 *   clearFilters()         → zera filtros e recarrega
 *   nextPage()/prevPage()  → navegação
 *   exportPdf(patientName) → download PDF do prontuário (caller pode passar
 *                            patientName para nomear o arquivo)
 *
 * Backend grava registros imutáveis. Override clínico (Roadmap #16.1) chega
 * com action `clinical_override` e changed_fields contendo metadata
 * `{ reason, source, target_action }` em vez do diff [old, new] padrão.
 */

import { ref } from 'vue';
import { useNotification } from '@plugins/beclinic_core/frontend/composables/useNotification';
import { useI18n } from 'vue-i18n';
import AuditLogsAPI from '@plugins/patients/frontend/api/patients/auditLogs';
import {
  blankAuditFilters,
  PAGE_SIZE,
} from '@plugins/patients/frontend/constants/audit';

export function useAuditLogs(patientIdRef) {
  const { t } = useI18n();

  const auditLogs = ref([]);
  const auditMeta = ref({ total_count: 0, current_page: 1, total_pages: 1 });
  const filters = ref(blankAuditFilters());
  const isLoading = ref(false);
  const isExporting = ref(false);

  const resolveId = () =>
    typeof patientIdRef === 'function'
      ? patientIdRef()
      : patientIdRef?.value ?? patientIdRef;

  const fetch = async () => {
    isLoading.value = true;
    try {
      const params = {
        page: filters.value.page,
        per_page: PAGE_SIZE,
      };
      if (filters.value.action_type) params.action_type = filters.value.action_type;
      if (filters.value.actor_id) params.actor_id = filters.value.actor_id;
      if (filters.value.start_date) params.start_date = filters.value.start_date;
      if (filters.value.end_date) params.end_date = filters.value.end_date;

      const response = await AuditLogsAPI.get(resolveId(), params);
      auditLogs.value = response.data?.audit_logs || [];
      auditMeta.value = response.data?.meta || {
        total_count: 0,
        current_page: 1,
        total_pages: 1,
      };
    } catch (error) {
      useNotification.error(t('PATIENT_AUDIT.MESSAGES.LOAD_ERROR'));
    } finally {
      isLoading.value = false;
    }
  };

  const applyFilters = async () => {
    filters.value.page = 1;
    await fetch();
  };

  const clearFilters = async () => {
    filters.value = blankAuditFilters();
    await fetch();
  };

  const nextPage = async () => {
    if (filters.value.page < auditMeta.value.total_pages) {
      filters.value.page += 1;
      await fetch();
    }
  };

  const prevPage = async () => {
    if (filters.value.page > 1) {
      filters.value.page -= 1;
      await fetch();
    }
  };

  const exportPdf = async patientName => {
    try {
      isExporting.value = true;
      const id = resolveId();
      const response = await AuditLogsAPI.export(id);
      const blob = new Blob([response.data], { type: 'application/pdf' });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      const name = patientName?.replace(/\s+/g, '_') || 'paciente';
      link.href = url;
      link.setAttribute('download', `prontuario_${name}_${id}.pdf`);
      document.body.appendChild(link);
      link.click();
      link.remove();
      window.URL.revokeObjectURL(url);
      useNotification.success(t('PATIENT_AUDIT.MESSAGES.EXPORT_SUCCESS'));
      return { ok: true };
    } catch (error) {
      useNotification.error(t('PATIENT_AUDIT.MESSAGES.EXPORT_ERROR'));
      return { ok: false };
    } finally {
      isExporting.value = false;
    }
  };

  return {
    auditLogs,
    auditMeta,
    filters,
    isLoading,
    isExporting,
    fetch,
    applyFilters,
    clearFilters,
    nextPage,
    prevPage,
    exportPdf,
  };
}
