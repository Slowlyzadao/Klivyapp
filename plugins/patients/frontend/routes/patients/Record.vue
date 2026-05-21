<script setup>
import '@plugins/patients/frontend/styles/record.scss';
import '@plugins/patients/frontend/styles/tabs.scss';

import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import AgendaServicesAPI from '@plugins/agenda/frontend/api/agendaServices';
import { usePermissions } from 'dashboard/composables/usePermissions';
import { usePatientSummary } from '@plugins/patients/frontend/features/patient-record/composables/usePatientSummary';
import { useClinicalTags } from '@plugins/patients/frontend/features/patient-record/composables/useClinicalTags';
import { useTreatmentPlanMirror } from '@plugins/patients/frontend/features/patient-record/composables/useTreatmentPlanMirror';
import { useResponsibleProfessional } from '@plugins/patients/frontend/features/patient-record/composables/useResponsibleProfessional';
import { useHeaderActions } from '@plugins/patients/frontend/features/patient-record/composables/useHeaderActions';
import PatientHeaderActions from '@plugins/patients/frontend/features/patient-record/components/record/PatientHeaderActions.vue';
import PatientArchivedBanner from '@plugins/patients/frontend/features/patient-record/components/record/PatientArchivedBanner.vue';
import PatientProfileBanner from '@plugins/patients/frontend/features/patient-record/components/record/PatientProfileBanner.vue';
import PatientNavSidebar from '@plugins/patients/frontend/features/patient-record/components/record/PatientNavSidebar.vue';
import GeneralTab from '@plugins/patients/frontend/features/patient-record/components/general-tab/GeneralTab.vue';
import ChangeResponsibleModal from '@plugins/patients/frontend/features/patient-record/components/general-tab/ChangeResponsibleModal.vue';
import EvolutionTab from './tabs/EvolutionTab.vue';
import ExamsTab from './tabs/ExamsTab.vue';
import TimelineTab from './tabs/TimelineTab.vue';
import AuditTab from './tabs/AuditTab.vue';
import AnamnesisTab from './tabs/AnamnesisTab.vue';
import DocumentsTab from './tabs/DocumentsTab.vue';
import ScheduleTab from './tabs/ScheduleTab.vue';
import ConsentsTab from './tabs/ConsentsTab.vue';
import TreatmentPlanTab from './tabs/TreatmentPlanTab.vue';
import FinancialTab from './tabs/FinancialTab.vue';
import RegistrationTab from './tabs/RegistrationTab.vue';

const router = useRouter();
const route = useRoute();
const store = useStore();

const { can } = usePermissions();

// Header action button gates
const canScheduleAppointment = computed(() => can('agenda', 'create_event'));
const canManageExams = computed(() => can('patients', 'manage_exams'));
const canManageDocuments = computed(() => can('patients', 'manage_documents'));
const canCharge = computed(() => can('financial', 'create_transaction'));
const canCreateClinicalNotes = computed(() =>
  can('patients', 'create_clinical_notes')
);

const goBack = () => {
  router.back();
};

const BRT = 'America/Sao_Paulo';

const activeTab = ref('general');
const isSidebarOpen = ref(false);
const agendaServices = ref([]);

// Modal de trocar Profissional Responsável (F-13 melhoria UX)
const showChangeResponsibleModal = ref(false);
function handleResponsibleUpdated() {
  // Atualiza o paciente após troca — o composable refetch recarrega o
  // patient.value com o novo responsible_professional_id, e o
  // useResponsibleProfessional reativo atualiza nome/avatar/badge automaticamente.
  fetchPatientSummary();
}

const {
  patient,
  fetchPatientSummary,
  fetchChangeHistory,
  handleStatusChange,
} = usePatientSummary(route.params.patientId);

const { fetchAnamnesisForTags, computedClinicalTags } = useClinicalTags(
  route.params.patientId,
  patient
);

const { fetchTreatmentPlans, activePlanSummary } = useTreatmentPlanMirror(
  route.params.patientId
);

const {
  responsibleProfName,
  responsibleProfAvatar,
  responsibleProfRoleLabel,
  responsibleProfRoleSlug,
} = useResponsibleProfessional(patient);

const {
  handleHeaderSchedule,
  handleHeaderCharge,
  handleHeaderStartService,
} = useHeaderActions({ patient, activeTab });

const fetchAgendaServices = async () => {
  try {
    const { data } = await AgendaServicesAPI.get();
    agendaServices.value = data;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Erro ao buscar serviços:', error);
  }
};

const lastAppointmentFormatted = computed(() => {
  const appt = patient.value.last_appointment;
  if (!appt?.start_time) return null;
  return {
    date: new Date(appt.start_time).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      timeZone: BRT,
    }),
    time: new Date(appt.start_time).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: BRT,
    }),
    title: appt.title || 'Consulta',
  };
});

const nextAppointmentFormatted = computed(() => {
  const appt = patient.value.next_appointment;
  if (!appt?.start_time) return null;
  return {
    date: new Date(appt.start_time).toLocaleDateString('pt-BR', {
      day: '2-digit',
      month: 'short',
      year: 'numeric',
      timeZone: BRT,
    }),
    time: new Date(appt.start_time).toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: BRT,
    }),
    title: appt.title || 'Consulta',
  };
});

onMounted(() => {
  fetchPatientSummary();
  fetchChangeHistory();
  fetchAgendaServices();
  fetchAnamnesisForTags(); // pré-carrega para `computedClinicalTags` da aba Geral
  fetchTreatmentPlans();
  store.dispatch('agents/get');

  // Abre a aba indicada pelo query param ao voltar da Agenda.
  // 'procedures' (URL antiga) → 'evolution' (aba unificada).
  if (route.query.tab === 'procedures') {
    router.replace({ query: { ...route.query, tab: 'evolution' } });
    activeTab.value = 'evolution';
  } else if (route.query.tab) {
    activeTab.value = route.query.tab;
  }
});

watch(activeTab, newVal => {
  // persiste a aba ativa na URL para sobreviver a F5
  if (route.query.tab !== newVal) {
    router.replace({ query: { ...route.query, tab: newVal } }).catch(() => {});
  }
  if (newVal === 'treatment_plan') {
    fetchTreatmentPlans();
  }
});


// All tabs — filtered by RBAC permissions before rendering
const allTabs = [
  { id: 'general', label: 'Geral', icon: 'i-lucide-layout-dashboard' },
  { id: 'registration', label: 'Cadastro', icon: 'i-lucide-user' },
  { id: 'anamnesis', label: 'Anamnese', icon: 'i-lucide-clipboard-plus' },
  {
    id: 'treatment_plan',
    label: 'Plano de Tratamento',
    icon: 'i-lucide-target',
  },
  { id: 'evolution', label: 'Evolução', icon: 'i-lucide-trending-up' },
  { id: 'exams', label: 'Exames e Imagens', icon: 'i-lucide-file-image' },
  { id: 'documents', label: 'Documentos', icon: 'i-lucide-file-text' },
  { id: 'consents', label: 'Consentimentos', icon: 'i-lucide-pen-tool' },
  {
    id: 'financial',
    label: 'Financeiro',
    icon: 'i-lucide-dollar-sign',
    permission: { module: 'financial', action: 'view_transactions' },
  },
  { id: 'schedule', label: 'Agenda e Histórico', icon: 'i-lucide-calendar' },
  { id: 'timeline', label: 'Timeline', icon: 'i-lucide-git-commit' },
  {
    id: 'audit',
    label: 'Auditoria',
    icon: 'i-lucide-shield-alert',
    permission: { module: 'patients', action: 'view_audit' },
  },
];

// Tabs visíveis para o usuário atual com base em permissões RBAC
const tabs = computed(() =>
  allTabs.filter(tab => {
    if (!tab.permission) return true;
    return can(tab.permission.module, tab.permission.action);
  })
);

</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="record-container px-4 md:px-6 lg:px-8" :class="{ 'is-archived': patient.deleted_at }">
    <PatientHeaderActions
      :can-schedule-appointment="canScheduleAppointment"
      :can-manage-exams="canManageExams"
      :can-manage-documents="canManageDocuments"
      :can-charge="canCharge"
      :can-create-clinical-notes="canCreateClinicalNotes"
      @back="goBack"
      @schedule="handleHeaderSchedule"
      @attach="activeTab = 'exams'"
      @document="activeTab = 'documents'"
      @charge="handleHeaderCharge"
      @start-service="handleHeaderStartService"
    />

    <PatientArchivedBanner
      :deleted-at="patient.deleted_at"
      :patient-id="patient.id"
      @restored="patient.deleted_at = null"
    />

    <PatientProfileBanner :patient="patient" />

    <!-- Layout Base: Abas na Esquerda e Conteúdo na Direita -->
    <div class="record-layout grid grid-cols-1 lg:grid-cols-[240px_1fr] gap-4 lg:gap-6 items-stretch">
      <PatientNavSidebar
        v-model:active-tab="activeTab"
        v-model:is-open="isSidebarOpen"
        :tabs="tabs"
      />

      <!-- Área Direita Principal: Conteúdo Dinâmico Baseada na Aba -->
      <div class="main-content">
        <div class="tab-content-area">
          <!-- ABA: GERAL — extraída em features/patient-record/components/general-tab/GeneralTab.vue -->
          <GeneralTab
            v-if="activeTab === 'general'"
            :patient="patient"
            :clinical-tags="computedClinicalTags"
            :active-plan="activePlanSummary"
            :professional="{
              name: responsibleProfName,
              avatar: responsibleProfAvatar,
              roleLabel: responsibleProfRoleLabel,
              roleSlug: responsibleProfRoleSlug,
            }"
            :last-appointment="lastAppointmentFormatted"
            :next-appointment="nextAppointmentFormatted"
            @edit-record="activeTab = 'registration'"
            @view-anamnesis="activeTab = 'anamnesis'"
            @view-plans="activeTab = 'treatment_plan'"
            @change-status="handleStatusChange"
            @change-responsible="showChangeResponsibleModal = true"
            @schedule="handleHeaderSchedule"
          />

          <!-- ABA: CADASTRO — extraída em tabs/RegistrationTab.vue -->
          <RegistrationTab
            v-else-if="activeTab === 'registration'"
            :key="`registration-${route.params.patientId}`"
            :patient="patient"
            @saved="fetchPatientSummary"
          />

          <!-- ABA: ANAMNESE — extraída em tabs/AnamnesisTab.vue -->
          <AnamnesisTab
            v-else-if="activeTab === 'anamnesis'"
            :key="`anamnesis-${route.params.patientId}`"
          />

          <!-- ABA: PLANO DE TRATAMENTO — extraída em tabs/TreatmentPlanTab.vue -->
          <TreatmentPlanTab
            v-else-if="activeTab === 'treatment_plan'"
            :key="`treatment_plan-${route.params.patientId}`"
            :agenda-services="agendaServices"
          />

          <!-- ABA: EVOLUÇÃO unificada (procedimentos + evolução clínica) -->
          <EvolutionTab
            v-else-if="activeTab === 'evolution'"
            :key="`evolution-${route.params.patientId}`"
            :patient="patient"
          />

          <!-- ABA: EXAMES E IMAGENS — extraída em tabs/ExamsTab.vue -->
          <ExamsTab
            v-else-if="activeTab === 'exams'"
            :key="`exams-${route.params.patientId}`"
          />

          <!-- ABA: DOCUMENTOS — extraída em tabs/DocumentsTab.vue -->
          <DocumentsTab
            v-else-if="activeTab === 'documents'"
            :key="`documents-${route.params.patientId}`"
          />

          <!-- ABA: CONSENTIMENTOS — extraída em tabs/ConsentsTab.vue -->
          <ConsentsTab
            v-else-if="activeTab === 'consents'"
            :key="`consents-${route.params.patientId}`"
            :patient="patient"
          />

          <!-- ABA: FINANCEIRO — extraída em tabs/FinancialTab.vue -->
          <FinancialTab
            v-else-if="activeTab === 'financial'"
            :key="`financial-${route.params.patientId}`"
            :patient="patient"
            @update-financial-status="patient.financialStatus = $event"
          />

          <!-- ABA: AGENDA E HISTÓRICO — extraída em tabs/ScheduleTab.vue -->
          <ScheduleTab
            v-else-if="activeTab === 'schedule'"
            :key="`schedule-${route.params.patientId}`"
            :patient="patient"
          />

          <!-- ABA: TIMELINE — extraída em tabs/TimelineTab.vue -->
          <TimelineTab
            v-else-if="activeTab === 'timeline'"
            :key="`timeline-${route.params.patientId}`"
          />

          <!-- ABA: AUDITORIA — extraída em tabs/AuditTab.vue -->
          <AuditTab
            v-else-if="activeTab === 'audit'"
            :key="`audit-${route.params.patientId}`"
            :patient-name="patient.name"
          />

          <div v-else class="tab-pane fade-in">
            <div class="card placeholder-card">
              <div class="placeholder-icon">
                <i class="i-lucide-hammer" />
              </div>
              <h3>Aba em Construção</h3>
              <p>
                Esta área (<strong>{{
                  tabs.find(t => t.id === activeTab)?.label
                }}</strong>
                ) receberá os componentes específicos em breve.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal de trocar Profissional Responsável (F-13 melhoria UX 2026-05-11).
         Renderizado fora da cadeia v-if/v-else-if das tabs pra não quebrar o
         flow. Usa Teleport internamente (no próprio component) pra escapar
         qualquer overflow:hidden. -->
    <ChangeResponsibleModal
      :show="showChangeResponsibleModal"
      :patient="patient"
      @close="showChangeResponsibleModal = false"
      @updated="handleResponsibleUpdated"
    />
  </div>
</template>

<style scoped>
/* Estilos locais do orquestrador Record.vue.

   Apenas regras que afetam elementos do template raiz deste arquivo:
   .record-container, .record-layout, .main-content, .tab-content-area,
   .card / .placeholder-card / .placeholder-icon (placeholder "Aba em Construção"),
   e @media print global.

   Regras dos componentes filhos (header, profile-banner, sidebar, tabs, etc.)
   vivem em plugins/patients/frontend/styles/record/*.scss global.
   .is-archived modifier também é global (ver record/_archived-banner.scss).
*/

@media print {
  .hide-on-print { display: none !important; }
  body,
  .record-container { background: white !important; color: black !important; }
  .record-header,
  .menu-sidebar { display: none !important; }
  .record-layout {
    display: block !important;
    padding: 0 !important;
    max-width: 100% !important;
  }
  .main-content {
    margin: 0 !important;
    padding: 0 !important;
    width: 100% !important;
  }
  .tab-pane { animation: none !important; }
  .card,
  .form-section {
    box-shadow: none !important;
    border: 1px solid #ccc !important;
    background: white !important;
    color: black !important;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  * { color: black !important; }
  .print-section {
    width: 100% !important;
    max-width: 100% !important;
    padding: 0 !important;
    margin: 0 !important;
  }
  .print-card {
    box-shadow: none !important;
    border: 1px solid #ccc !important;
    break-inside: avoid;
    break-after: auto;
    page-break-inside: avoid;
  }
  .page-break-inside-avoid {
    break-inside: avoid;
    page-break-inside: avoid;
  }
}

.record-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  /* max-width: 100vw garante que o container NUNCA passa do viewport. */
  max-width: 100vw;
  background: var(--color-background, #121212);
  color: #f1f5f9;
  padding: 24px 32px;
  box-sizing: border-box;
  overflow-y: auto;
  /* `overflow-x: clip` impede children propagarem scroll horizontal
     SEM criar stacking context nem containing block para `position: fixed`
     (modais continuam cobrindo toda a viewport). */
  overflow-x: clip;
  font-family: inherit;
  /* IMPORTANTE: NÃO usar `contain: layout|paint|size|inline-size|strict`
     aqui — qualquer um deles cria containing block pra `position: fixed`,
     o que limita modais (PayTransactionModal etc.) ao container em vez
     de cobrirem a viewport inteira. A contenção fica SÓ no `.fin-kpi-grid`. */
}

/* Mobile: padding lateral reduzido para maximizar área útil em telas
   estreitas. Em 360px, antes 32×2=64px (18%) era desperdiçado;
   agora 12×2=24px (6.7%). */
@media (max-width: 768px) {
  .record-container {
    padding: 16px 12px;
  }
}

.record-layout {
  display: flex;
  gap: 24px;
  align-items: flex-start;
  min-height: min-content;
}

.main-content {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
}

@media (max-width: 1024px) {
  .record-layout { flex-direction: column; }
}

.tab-content-area {
  display: flex;
  flex-direction: column;
  gap: 24px;
  /* min-width: 0 permite filhos com `overflow-x: auto` ficarem
     contidos sem propagar scroll. NÃO usar `contain` aqui —
     criaria containing block pra modais `position: fixed`. */
  min-width: 0;
  width: 100%;
}

.tab-pane {
  min-width: 0;
  width: 100%;
  /* `overflow-x: clip` é SEGURO — não cria containing block para
     `position: fixed` (modais ainda cobrem toda viewport). */
  overflow-x: clip;
}

.card {
  background: #1c1c1d;
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 16px;
  padding: 24px;
}

.placeholder-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  text-align: center;
  padding: 60px 24px;
}

.placeholder-icon {
  font-size: 48px;
  color: rgba(255, 255, 255, 0.05);
  margin-bottom: 20px;
}

.placeholder-card h3 {
  font-size: 18px;
  color: #f1f5f9;
  margin: 0 0 10px;
}

.placeholder-card p {
  color: #94a3b8;
  font-size: 14px;
  margin: 0;
  max-width: 400px;
}
</style>
