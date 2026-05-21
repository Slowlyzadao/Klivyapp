<script setup>
/**
 * AuditTab — Aba "Auditoria e Permissões" do prontuário do paciente.
 *
 * Orquestrador. Composição:
 *   • useAuditLogs — fetch read-only com filtros + paginação + export PDF
 *   • audit-tab/* (4 sub-componentes)
 *
 * Auto-suficiente: lê patientId da rota. Recebe `patientName` apenas para
 * nomear o PDF exportado.
 */
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useAuditLogs } from '@plugins/patients/frontend/features/patient-record/composables/useAuditLogs';
import AuditHeader from '@plugins/patients/frontend/features/patient-record/components/audit-tab/AuditHeader.vue';
import AuditFilterBar from '@plugins/patients/frontend/features/patient-record/components/audit-tab/AuditFilterBar.vue';
import AuditLogsTable from '@plugins/patients/frontend/features/patient-record/components/audit-tab/AuditLogsTable.vue';
import AuditFooter from '@plugins/patients/frontend/features/patient-record/components/audit-tab/AuditFooter.vue';

const props = defineProps({
  patientName: { type: String, default: '' },
});

const route = useRoute();
const patientId = computed(() => route.params.patientId);

const {
  auditLogs,
  auditMeta,
  filters,
  isLoading,
  isExporting,
  fetch: fetchAuditLogs,
  applyFilters,
  clearFilters,
  nextPage,
  prevPage,
  exportPdf,
} = useAuditLogs(patientId);

// Expand state — Set é reativo a substituição mas não a mutação interna.
// Por isso reatribuímos uma cópia a cada toggle.
const expandedLogs = ref(new Set());

const toggleLogDetails = logId => {
  const next = new Set(expandedLogs.value);
  if (next.has(logId)) next.delete(logId);
  else next.add(logId);
  expandedLogs.value = next;
};

const handleExport = () => exportPdf(props.patientName);

onMounted(() => {
  fetchAuditLogs();
});
</script>

<template>
  <div class="tab-pane fade-in">
    <AuditHeader :is-exporting="isExporting" @export="handleExport" />

    <AuditFilterBar
      :filters="filters"
      @update:filters="filters = $event"
      @apply="applyFilters"
      @clear="clearFilters"
    />

    <AuditLogsTable
      :logs="auditLogs"
      :expanded="expandedLogs"
      :is-loading="isLoading"
      @toggle-details="toggleLogDetails"
    />

    <AuditFooter
      :meta="auditMeta"
      :current-page="filters.page"
      :is-loading="isLoading"
      @prev="prevPage"
      @next="nextPage"
    />
  </div>
</template>
