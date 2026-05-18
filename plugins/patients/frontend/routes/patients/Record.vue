<script setup>
import './record.css';

import { ref, computed, onMounted, watch, nextTick } from 'vue';
import { useStore } from 'vuex';
import { useRouter, useRoute } from 'vue-router';
import PatientsAPI from '@plugins/patients/frontend/api/patients/index';
import AnamnesisAPI from '@plugins/patients/frontend/api/patients/anamnesis';
import ClinicalNotesAPI from '@plugins/patients/frontend/api/patients/clinicalNotes';
import TreatmentPlansAPI from '@plugins/patients/frontend/api/patients/treatmentPlans';
import AgendaServicesAPI from '@plugins/agenda/frontend/api/agendaServices';
import ContactAPI from 'dashboard/api/contacts';
import { useAlert } from 'dashboard/composables';
import { usePermissions } from 'dashboard/composables/usePermissions';
import { formatDateBR } from '@plugins/beclinic_core/frontend/helpers/dateHelpers';
import EvolutionTab from './tabs/EvolutionTab.vue';
import ExamsTab from './tabs/ExamsTab.vue';
import TimelineTab from './tabs/TimelineTab.vue';
import AuditTab from './tabs/AuditTab.vue';
import AnamnesisTab from './tabs/AnamnesisTab.vue';
import DocumentsTab from './tabs/DocumentsTab.vue';
import ScheduleTab from './tabs/ScheduleTab.vue';
import ConsentsTab from './tabs/ConsentsTab.vue';
import ProceduresTab from './tabs/ProceduresTab.vue';
import TreatmentPlanTab from './tabs/TreatmentPlanTab.vue';
import FinancialTab from './tabs/FinancialTab.vue';
import RegistrationTab from './tabs/RegistrationTab.vue';

const router = useRouter();
const route = useRoute();
const store = useStore();

const { can } = usePermissions();

const currentUser = computed(() => store.getters.getCurrentUser);

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

const isLoading = ref(true);
const changeHistory = ref([]);
const isHistoryLoading = ref(false);

const BRT = 'America/Sao_Paulo';

// (Audit Log state extraído para tabs/AuditTab.vue)
// (Anamnese form extraído para tabs/AnamnesisTab.vue — `currentAnamnesis` aqui
//  é uma cópia somente-leitura usada por `computedClinicalTags` na aba Geral.
//  Se o usuário editar anamnese, F5 atualiza as tags clínicas.)
const currentAnamnesis = ref({});
const fetchAnamnesisForTags = async () => {
  try {
    const response = await AnamnesisAPI.get(route.params.patientId);
    const list = response.data?.payload || response.data || [];
    currentAnamnesis.value = list[0] || {};
  } catch (error) {
    currentAnamnesis.value = {};
  }
};

const activeTab = ref('general');
const isSidebarOpen = ref(false);
const showCriticalAlert = ref(false);
const agendaServices = ref([]);

// ── Clinical Notes State ──────────────────────────────────
const clinicalNotes = ref([]);
const currentNote = ref({
  note_template: 'Evolução Padrão',
  complaint_of_day: '',
  assessment: '',
  conduct: '',
  complications: '',
  guidance_given: '',
  return_recommended: '',
});
const isSavingNote = ref(false);
const showConfirmDeleteNote = ref(false);
const noteToDelete = ref(null);
const isDeletingNote = ref(false);


// ── Aba "Exames e Imagens" extraída para tabs/ExamsTab.vue ────────────
// Todo state e lógica de pastas/mídias/lightbox/upload vive lá agora.

const patient = ref({
  id: null,
  name: '',
  social_name: '',
  avatar_url: '',
  phone: '',
  email: '',
  cpf: '',
  rg: '',
  birthdate: '',
  age: null,
  sex: '',
  contact_id: null,
  patient_status: 'novo',
  financialStatus: 'Adimplente',
  activeTreatment: '---',
  origin: '',
  unit: '',
  notes: '',
  critical_alerts: [],
  clinicalTags: [],
  address: {
    street: '',
    number: '',
    complement: '',
    neighborhood: '',
    city: '',
    state: '',
    zip_code: '',
  },
  emergency_contact: {
    name: '',
    phone: '',
    relationship: '',
  },
  has_guardian: false,
  guardian: {
    name: '',
    cpf: '',
    phone: '',
    relationship: '',
  },
  insurance: {
    name: '',
    number: '',
    plan: '',
    validity: '',
  },
  communication_opt_ins: {
    whatsapp: false,
    email: false,
  },
  lgpd_consent: {
    accepted: false,
    image_use_accepted: false,
  },
});

const fetchPatientSummary = async () => {
  try {
    isLoading.value = true;
    const response = await PatientsAPI.summary(route.params.patientId);

    // Merge nested objects safely
    const data = response.data?.payload || {};
    patient.value = {
      ...patient.value,
      ...data,
      address: { ...patient.value.address, ...(data.address || {}) },
      emergency_contact: {
        ...patient.value.emergency_contact,
        ...(data.emergency_contact || {}),
      },
      guardian: {
        ...patient.value.guardian,
        ...(data.guardian || {}),
      },
      has_guardian: Boolean(data.has_guardian),
      insurance: { ...patient.value.insurance, ...(data.insurance || {}) },
      communication_opt_ins: {
        ...patient.value.communication_opt_ins,
        ...(data.communication_opt_ins || {}),
      },
      lgpd_consent: {
        ...patient.value.lgpd_consent,
        ...(data.lgpd_consent || {}),
      },
    };

    // (RegistrationTab faz seu próprio split de patient.name em first/last via watch)
    // (recall_dismissed_at é lido pelo ScheduleTab via prop `patient.recall_dismissed_at`)
  } catch (error) {
    // ignorar erro
  } finally {
    isLoading.value = false;
  }
};

const fetchChangeHistory = async () => {
  try {
    isHistoryLoading.value = true;
    const response = await PatientsAPI.changeHistory(route.params.patientId);
    changeHistory.value = response.data?.payload || [];
  } catch (error) {
    // ignorar erro
  } finally {
    isHistoryLoading.value = false;
  }
};


// ── Clinical Notes Actions ────────────────────────────────
const fetchClinicalNotes = async () => {
  try {
    const response = await ClinicalNotesAPI.get(route.params.patientId);
    clinicalNotes.value = response.data?.payload || response.data || [];
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error fetching clinical notes', error);
  }
};

const requestDeleteNote = noteId => {
  noteToDelete.value = noteId;
  showConfirmDeleteNote.value = true;
};

const cancelDeleteNote = () => {
  showConfirmDeleteNote.value = false;
  noteToDelete.value = null;
  isDeletingNote.value = false;
};

const confirmDeleteNote = async () => {
  if (!noteToDelete.value) return;
  isDeletingNote.value = true;
  try {
    await ClinicalNotesAPI.delete(route.params.patientId, noteToDelete.value);
    useAlert('Rascunho excluído com sucesso!');
    await fetchClinicalNotes();
    if (currentNote.value.id === noteToDelete.value) {
      currentNote.value = {
        note_template: 'Evolução Padrão',
        complaint_of_day: '',
        assessment: '',
        conduct: '',
        complications: '',
        guidance_given: '',
        return_recommended: '',
      };
    }
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Error deleting clinical note', error);
    useAlert('Erro ao excluir o rascunho.');
  } finally {
    cancelDeleteNote();
  }
};

const saveClinicalNote = async (sign = false) => {
  try {
    isSavingNote.value = true;
    const payload = { ...currentNote.value };

    // Converter número de dias para data ISO (coluna type:date no banco)
    if (
      payload.return_recommended !== '' &&
      payload.return_recommended !== null
    ) {
      const days = parseInt(payload.return_recommended, 10);
      if (!Number.isNaN(days) && days >= 0) {
        const date = new Date();
        date.setDate(date.getDate() + days);
        payload.return_recommended = date.toISOString().split('T')[0]; // YYYY-MM-DD
      } else {
        payload.return_recommended = null;
      }
    } else {
      payload.return_recommended = null;
    }

    let response;
    if (payload.id) {
      response = await ClinicalNotesAPI.update(
        route.params.patientId,
        payload.id,
        payload
      );
    } else {
      response = await ClinicalNotesAPI.create(route.params.patientId, payload);
      currentNote.value.id = response.data?.payload?.id || response.data.id;
    }

    if (sign && currentNote.value.id) {
      await ClinicalNotesAPI.sign(route.params.patientId, currentNote.value.id);
      useAlert('Evolução assinada com sucesso!');
      currentNote.value = {
        note_template: 'Evolução Padrão',
        complaint_of_day: '',
        assessment: '',
        conduct: '',
        complications: '',
        guidance_given: '',
        return_recommended: '',
      };
      await fetchClinicalNotes();
    } else {
      useAlert('Evolução salva como rascunho com sucesso!');
      await fetchClinicalNotes();
    }
  } catch (error) {
    useAlert('Erro ao salvar evolução.');
  } finally {
    isSavingNote.value = false;
  }
};

const editClinicalNote = note => {
  const loaded = { ...note };

  // Converter data de retorno de volta para número de dias
  if (loaded.return_recommended) {
    const returnDate = new Date(loaded.return_recommended);
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const diffMs = returnDate.getTime() - today.getTime();
    const diffDays = Math.round(diffMs / (1000 * 60 * 60 * 24));
    loaded.return_recommended = diffDays > 0 ? String(diffDays) : '';
  }

  currentNote.value = loaded;
  nextTick(() => {
    const formEl = document.querySelector('.evolution-form');
    if (formEl) {
      formEl.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }

    // Fallback: se houver container de rolagem específico, move até o topo dele
    const container = document.querySelector('.record-container');
    if (container) {
      container.scrollTo({ top: 0, behavior: 'smooth' });
    } else {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }
  });
};



// ── Treatment Plans (cópia mínima para `activePlanSummary` na aba Geral) ──
// (Aba Plano de Tratamento extraída em tabs/TreatmentPlanTab.vue, com state próprio.
// Após editar plano em TreatmentPlanTab, F5 sincroniza este mirror.)
const treatmentPlans = ref([]);
const fetchTreatmentPlans = async () => {
  try {
    const { data } = await TreatmentPlansAPI.get(route.params.patientId);
    treatmentPlans.value = data?.data || data || [];
  } catch (error) {
    // ignora — mirror de leitura
  }
};

const fetchAgendaServices = async () => {
  try {
    const { data } = await AgendaServicesAPI.get();
    agendaServices.value = data;
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error('Erro ao buscar serviços:', error);
  }
};


const handleStatusChange = async event => {
  const newStatus = event.target.value;
  const oldStatus = patient.value.patient_status;
  try {
    patient.value.patient_status = newStatus; // optimistic update
    await PatientsAPI.updateStatus(route.params.patientId, newStatus);
  } catch (error) {
    // revert on error
    patient.value.patient_status = oldStatus;
  }
};

// (Avatar/câmera/CEP/handlers do Cadastro extraídos para tabs/RegistrationTab.vue)

// ── General Tab Computeds ────────────────────────────────────
const computedClinicalTags = computed(() => {
  const tags = [];
  // Critical alerts (already objects with .title/.message from API)
  (patient.value.critical_alerts || []).forEach(alert => {
    tags.push({
      type: 'danger',
      icon: 'i-lucide-triangle-alert',
      label: alert.title || alert.message,
    });
  });
  // Anamnesis-derived tags (all these arrays are objects {name} or strings - handle both)
  if (currentAnamnesis.value?.id) {
    const getString = v =>
      typeof v === 'object' && v !== null
        ? v.name || JSON.stringify(v)
        : String(v);
    (currentAnamnesis.value.allergies || []).forEach(a => {
      tags.push({
        type: 'warning',
        icon: 'i-lucide-zap',
        label: `Alergia: ${getString(a)}`,
      });
    });
    (currentAnamnesis.value.contraindications || []).forEach(c => {
      tags.push({ type: 'danger', icon: 'i-lucide-ban', label: getString(c) });
    });
    const mh = currentAnamnesis.value.medical_history || {};
    if (mh.diabetes)
      tags.push({
        type: 'warning',
        icon: 'i-lucide-activity',
        label: 'Diabético(a)',
      });
    if (mh.hypertension)
      tags.push({
        type: 'warning',
        icon: 'i-lucide-heart-pulse',
        label: 'Hipertenso(a)',
      });
    if (mh.bleeding_disorder)
      tags.push({
        type: 'danger',
        icon: 'i-lucide-droplets',
        label: 'Distúrbio de Coagulação',
      });
    if (mh.cardiac_problems)
      tags.push({
        type: 'danger',
        icon: 'i-lucide-heart-crack',
        label: 'Cardiopatia',
      });
    if (mh.pregnancy)
      tags.push({ type: 'warning', icon: 'i-lucide-baby', label: 'Grávida' });
    if (mh.has_implants)
      tags.push({ type: 'info', icon: 'i-lucide-cpu', label: 'Implante' });
    (currentAnamnesis.value.current_medications || [])
      .slice(0, 3)
      .forEach(m => {
        tags.push({
          type: 'info',
          icon: 'i-lucide-pill',
          label: `Med: ${getString(m)}`,
        });
      });
  }
  return tags;
});

const activePlanSummary = computed(() => {
  if (!treatmentPlans.value?.length) return null;
  const found = treatmentPlans.value.find(
    p => p.status === 'in_progress' || p.status === 'approved'
  );
  return found || treatmentPlans.value[0] || null;
});

const responsibleProfName = computed(() => {
  const profId = patient.value.responsible_professional_id;
  if (profId) {
    const agents = store.getters['agents/getAgents'] || [];
    const agent = agents.find(a => a.id === profId);
    if (agent) return agent.name;
  }
  return currentUser.value?.name || '—';
});

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

  // Abre a aba indicada pelo query param ao voltar da Agenda
  if (route.query.tab) {
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
  } else if (newVal === 'evolution') {
    fetchClinicalNotes();
  }
});


// All tabs — filtered by RBAC permissions before rendering
const allTabs = [
  { id: 'general', label: 'Geral', icon: 'i-lucide-layout-dashboard' },
  { id: 'registration', label: 'Cadastro', icon: 'i-lucide-user' },
  { id: 'anamnesis', label: 'Anamnese', icon: 'i-lucide-clipboard-plus' },
  { id: 'evolution', label: 'Evolução', icon: 'i-lucide-trending-up' },
  {
    id: 'treatment_plan',
    label: 'Plano de Tratamento',
    icon: 'i-lucide-target',
  },
  {
    id: 'procedures',
    label: 'Procedimentos',
    icon: 'i-lucide-activity',
  },
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

const getInitials = name => {
  if (!name) return '';
  return name.charAt(0).toUpperCase();
};

const formatDate = dateStr => {
  if (!dateStr) return '—';
  // Date-only strings ('YYYY-MM-DD') must not be converted through a timezone —
  // doing so shifts the day for users west of UTC. formatDateBR keeps date-only
  // values as-is and only falls back to local-time parsing for full timestamps.
  return formatDateBR(dateStr) || '—';
};

const formatPhoneDisplay = phoneStr => {
  if (!phoneStr) return '';
  let val = String(phoneStr).replace(/\D/g, '');
  if (val.startsWith('55')) val = val.slice(2);
  if (val.length === 11) {
    return val.replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3');
  }
  if (val.length === 10) {
    return val.replace(/(\d{2})(\d{4})(\d{4})/, '($1) $2-$3');
  }
  return phoneStr;
};

const formatCpfDisplay = cpfStr => {
  if (!cpfStr) return '';
  let value = String(cpfStr).replace(/\D/g, '');
  if (value.length > 11) value = value.slice(0, 11);
  if (value.length > 9) {
    return value.replace(/(\d{3})(\d{3})(\d{3})(\d{1,2})/, '$1.$2.$3-$4');
  }
  if (value.length > 6) {
    return value.replace(/(\d{3})(\d{3})(\d{1,3})/, '$1.$2.$3');
  }
  if (value.length > 3) {
    return value.replace(/(\d{3})(\d{1,3})/, '$1.$2');
  }
  return value;
};

const formatSex = sex => {
  if (!sex) return '';
  const lower = sex.toLowerCase();
  if (lower === 'masculino') return 'Masculino';
  if (lower === 'feminino') return 'Feminino';
  return sex;
};

const hasValidSex = sex => {
  if (!sex) return false;
  const s = String(sex).toLowerCase().trim();
  return ![
    '',
    'não informado',
    'nao_informado',
    'não_informado',
    'null',
  ].includes(s);
};

const formatInsuranceStr = ins => {
  if (!ins) return null;
  let parsed = ins;
  if (typeof parsed === 'string') {
    if (
      parsed === '—' ||
      parsed === '{}' ||
      parsed === 'null' ||
      parsed.includes('"name":""') ||
      parsed.includes('"name": ""')
    ) {
      return null;
    }
    try {
      parsed = JSON.parse(parsed);
    } catch (e) {
      return parsed;
    }
  }
  if (parsed && typeof parsed === 'object') {
    if (!parsed.name) return null;
    return `${parsed.name}${parsed.plan ? ' - ' + parsed.plan : ''}`;
  }
  return String(parsed);
};

// ── Header Global Shortcuts ──────────────────────────────────
const handleHeaderSchedule = () => {
  router.push({
    name: 'agenda_dashboard_index',
    params: { accountId: route.params.accountId },
    query: {
      newEvent: '1',
      contactId: patient.value.contact_id || '',
      patientName: patient.value.name || '',
      patientPhone: patient.value.phone || '',
    },
  });
};

const handleHeaderCharge = () => {
  activeTab.value = 'financial';
};

const handleHeaderStartService = async () => {
  if (!patient.value.contact_id) {
    router.push({
      name: 'home',
      params: { accountId: route.params.accountId },
    });
    return;
  }
  try {
    const response = await ContactAPI.getConversations(
      patient.value.contact_id
    );
    const conversations = response.data?.payload || [];
    if (conversations.length > 0) {
      const sorted = [...conversations].sort((a, b) => b.id - a.id);
      router.push({
        name: 'inbox_conversation',
        params: {
          accountId: route.params.accountId,
          conversation_id: sorted[0].id,
        },
      });
    } else {
      router.push({
        name: 'home',
        params: { accountId: route.params.accountId },
      });
    }
  } catch (e) {
    router.push({
      name: 'home',
      params: { accountId: route.params.accountId },
    });
  }
};
</script>

<template>
  <!-- eslint-disable @intlify/vue-i18n/no-raw-text, vue/no-bare-strings-in-template -->
  <div class="record-container px-4 md:px-6 lg:px-8" :class="{ 'is-archived': patient.deleted_at }">
    <!-- Header com Voltar -->
    <div class="header-nav flex flex-row justify-between w-full gap-2 md:gap-4 items-center">
      <button class="btn-back !px-3 md:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 rounded-md shrink-0" @click="goBack" title="Voltar para pacientes">
        <i class="i-lucide-arrow-left" />
        <span class="hidden md:inline">Voltar para pacientes</span>
      </button>
      <div class="header-actions flex flex-row gap-1 sm:gap-2 w-auto overflow-x-auto pb-1 sm:pb-0 items-center">
        <button
          v-if="canScheduleAppointment"
          class="hdr-btn hdr-btn--secondary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="handleHeaderSchedule"
          title="Agendar"
        >
          <i class="i-lucide-calendar-plus w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Agendar</span>
        </button>
        <button
          v-if="canManageExams"
          class="hdr-btn hdr-btn--secondary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="activeTab = 'exams'"
          title="Anexar arquivo"
        >
          <i class="i-lucide-paperclip w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Anexar arquivo</span>
        </button>
        <button
          v-if="canManageDocuments"
          class="hdr-btn hdr-btn--secondary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="activeTab = 'documents'"
          title="Gerar documento"
        >
          <i class="i-lucide-file-text w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Gerar documento</span>
        </button>
        <div v-if="canCharge" class="hdr-divider hidden sm:block shrink-0" />
        <button
          v-if="canCharge"
          class="hdr-btn hdr-btn--charge !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="handleHeaderCharge"
          title="Cobrar"
        >
          <i class="i-lucide-dollar-sign w-4 h-4 md:mr-1" />
          <span class="hidden lg:inline">Cobrar</span>
        </button>
        <button
          v-if="canCreateClinicalNotes"
          class="hdr-btn hdr-btn--primary !px-2.5 sm:!px-4 focus:outline-none focus-visible:ring-1 focus-visible:ring-slate-500 shrink-0"
          @click="handleHeaderStartService"
          title="Iniciar atendimento"
        >
          <i class="i-lucide-play w-3.5 h-3.5 md:mr-1" />
          <span class="hidden md:inline">Iniciar atendimento</span>
        </button>
      </div>
    </div>

    <!-- Banner: Paciente Arquivado -->
    <div v-if="patient.deleted_at" class="archived-banner">
      <div class="archived-banner-left">
        <i class="i-lucide-archive w-4 h-4" />
        <div>
          <p class="archived-banner-title">Paciente arquivado</p>
          <p class="archived-banner-sub">
            Arquivado em
            {{
              new Date(patient.deleted_at).toLocaleDateString('pt-BR', {
                timeZone: 'America/Sao_Paulo',
              })
            }}
            — apenas leitura
          </p>
        </div>
      </div>
      <button
        class="archived-banner-btn"
        title="Restaurar paciente"
        @click="
          () =>
            PatientsAPI.restore(patient.id).then(() => {
              patient.deleted_at = null;
              useAlert('Paciente restaurado com sucesso!');
            })
        "
      >
        <i class="i-lucide-archive-restore w-4 h-4" />
        Restaurar paciente
      </button>
    </div>

    <!-- Perfil do Paciente em Banner -->
    <div class="profile-banner">
      <!-- Esquerda: avatar + identidade -->
      <div class="profile-banner-left">
        <!-- Avatar com badge de status sobreposto -->
        <div class="pb-avatar-wrap">
          <img
            v-if="patient.avatar_url"
            :src="patient.avatar_url"
            alt="Avatar"
            class="pb-avatar-img"
          />
          <div v-else class="pb-avatar-placeholder">
            {{ getInitials(patient.name) }}
          </div>
          <!-- Status badge no canto inferior direito do avatar -->
          <span
            class="pb-status-dot"
            :class="'pb-dot-' + (patient.patient_status || 'novo')"
            :title="
              {
                novo: 'Novo',
                ativo: 'Ativo',
                inativo: 'Inativo',
                faltoso: 'Faltoso',
                alta: 'Alta',
                arquivado: 'Arquivado',
              }[patient.patient_status] || patient.patient_status
            "
          />
        </div>

        <!-- Identidade: nome + dados -->
        <div class="pb-identity">
          <div class="pb-name-row">
            <h2 class="pb-name">{{ patient.name }}</h2>
            <!-- Botão de alerta crítico (se houver) -->
            <div
              v-if="
                patient.critical_alerts && patient.critical_alerts.length > 0
              "
              class="critical-alert-container"
            >
              <button
                class="btn-critical-alert enhanced"
                title="Atenção Clínica"
                @click.stop="showCriticalAlert = !showCriticalAlert"
              >
                <i class="i-lucide-alert-circle" />
              </button>
              <div v-if="showCriticalAlert" class="critical-popup">
                <div class="popup-header">
                  <i class="i-lucide-alert-triangle" />
                  <span>Atenção Clínica</span>
                  <button
                    class="btn-close-popup"
                    @click="showCriticalAlert = false"
                  >
                    <i class="i-lucide-x" />
                  </button>
                </div>
                <div class="popup-body critical-popup-body">
                  <div
                    v-for="alert in patient.critical_alerts"
                    :key="alert.id"
                    class="alert-item"
                  >
                    <strong>{{ alert.severity }}:</strong> {{ alert.message }}
                  </div>
                </div>
              </div>
            </div>
          </div>

          <!-- Linha de dados demográficos + status pill -->
          <div class="pb-meta-row">
            <span
v-if="patient.age" class="pb-meta-text"
              >{{ patient.age }} anos</span
            >
            <span
              v-if="patient.age && hasValidSex(patient.sex)"
              class="pb-meta-sep"
              >•</span
            >
            <span v-if="hasValidSex(patient.sex)" class="pb-meta-text">{{
              formatSex(patient.sex)
            }}</span>
            <span class="pb-meta-sep">·</span>
            <span
              class="pb-status-pill"
              :class="'pb-pill-' + (patient.patient_status || 'novo')"
            >
              {{
                {
                  novo: 'Novo',
                  ativo: 'Ativo',
                  inativo: 'Inativo',
                  faltoso: 'Faltoso',
                  alta: 'Alta',
                  arquivado: 'Arquivado',
                }[patient.patient_status] || patient.patient_status
              }}
            </span>
          </div>

          <!-- Chips de informações -->
          <div class="pb-chips">
            <div v-if="patient.birthdate" class="pb-chip">
              <i class="i-lucide-cake w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatDate(patient.birthdate) }}</span>
            </div>
            <div v-if="patient.phone" class="pb-chip">
              <i class="i-lucide-smartphone w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatPhoneDisplay(patient.phone) || patient.phone }}</span>
            </div>
            <div v-if="patient.email" class="pb-chip hide-mobile">
              <i class="i-lucide-mail w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ patient.email }}</span>
            </div>
            <div v-if="patient.cpf" class="pb-chip hide-mobile">
              <i class="i-lucide-credit-card w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatCpfDisplay(patient.cpf) }}</span>
            </div>
            <div v-if="formatInsuranceStr(patient.insurance)" class="pb-chip">
              <i class="i-lucide-shield-plus w-3.5 h-3.5 pb-chip-icon" />
              <span>{{ formatInsuranceStr(patient.insurance) }}</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Direita: badge financeiro -->
      <div class="pb-right">
        <div
          class="pb-finance-badge"
          :class="'pb-finance-' + patient.financialStatus?.toLowerCase()"
        >
          <i class="i-lucide-wallet w-4 h-4" />
          <span>{{ patient.financialStatus }}</span>
        </div>
      </div>
    </div>

    <!-- Layout Base: Abas na Esquerda e Conteúdo na Direita -->
    <div class="record-layout grid grid-cols-1 lg:grid-cols-[240px_1fr] gap-4 lg:gap-6 items-stretch">
      <!-- Overlay para Mobile Sidebar -->
      <div
        v-if="isSidebarOpen"
        class="fixed inset-0 bg-slate-900/60 backdrop-blur-[2px] z-40 lg:hidden transition-opacity"
        @click="isSidebarOpen = false"
      />

      <!-- Coluna Fixa Esquerda: Navegação Vertical (Menu do Prontuário) -->
      <div 
        class="menu-sidebar bg-n-background border border-n-strong max-lg:!fixed max-lg:!top-0 max-lg:!left-0 max-lg:!bottom-0 max-lg:!h-[100dvh] max-lg:!w-[280px] max-lg:!max-w-[85vw] max-lg:z-50 transition-transform duration-300 transform lg:!translate-x-0 overflow-y-auto"
        :class="[isSidebarOpen ? 'translate-x-0 !shadow-2xl' : '-translate-x-full', 'flex flex-col']"
      >
        <!-- Mobile menu title (optional) -->
        <div class="lg:hidden flex items-center justify-between p-4 mb-2 border-b border-white/10">
          <span class="font-semibold text-slate-200">Prontuário</span>
          <button class="text-slate-400 hover:text-white" @click="isSidebarOpen = false">
            <i class="i-lucide-x w-5 h-5" />
          </button>
        </div>

        <nav class="vertical-tabs-nav">
          <button
            v-for="tab in tabs"
            :key="tab.id"
            class="vertical-tab-btn"
            :class="{ active: activeTab === tab.id }"
            @click="activeTab = tab.id; isSidebarOpen = false"
          >
            <i :class="tab.icon" />
            <span>{{ tab.label }}</span>
          </button>
        </nav>
      </div>

      <!-- Área Direita Principal: Conteúdo Dinâmico Baseada na Aba -->
      <div class="main-content">
        <div class="tab-content-area">
          <!-- ABA: GERAL -->
          <div v-if="activeTab === 'general'" class="tab-pane fade-in">
            <!-- Header -->
            <div class="reg-header mb-5">
              <div>
                <h3 class="text-xl font-semibold text-slate-100">
                  Visão Geral
                </h3>
                <p class="text-sm text-slate-400 mt-0.5">
                  Painel clínico rápido — informações essenciais antes do
                  atendimento.
                </p>
              </div>
              <button
                class="geral-header-btn"
                @click="activeTab = 'registration'"
              >
                <i class="i-lucide-edit-3 w-4 h-4" />
                Editar Ficha
              </button>
            </div>

            <!-- Banner: Alertas Críticos -->
            <div
              v-if="
                patient.critical_alerts && patient.critical_alerts.length > 0
              "
              class="geral-alert-banner mb-4"
            >
              <div class="geral-alert-icon">
                <i class="i-lucide-siren w-4 h-4" />
              </div>
              <div class="geral-alert-body">
                <span class="geral-alert-title">Alertas Críticos</span>
                <span class="geral-alert-text">
                  <span v-for="(a, i) in patient.critical_alerts" :key="i">
                    {{ a.title || a.message
                    }}<span v-if="i < patient.critical_alerts.length - 1">
                      ·
                    </span>
                  </span>
                </span>
              </div>
            </div>

            <!-- Nota Fixada -->
            <div v-if="patient.pinned_note" class="geral-pinned-note mb-4">
              <i class="i-lucide-pin w-4 h-4 text-amber-400 flex-shrink-0" />
              <span class="text-sm text-slate-300">{{
                patient.pinned_note
              }}</span>
            </div>

            <!-- Grid principal -->
            <div class="reg-form-grid flex flex-col gap-4">
              <!-- ── Tags Clínicas ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-purple">
                      <i class="i-lucide-tag w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title">Tags Clínicas</span>
                      <span class="reg-section-subtitle"
                        >Geradas automaticamente pela anamnese</span
                      >
                    </div>
                  </div>
                  <button
                    class="geral-action-btn"
                    @click="activeTab = 'anamnesis'"
                  >
                    <i class="i-lucide-clipboard-plus w-3.5 h-3.5" />
                    Ver Anamnese
                  </button>
                </div>
                <div class="reg-section-body">
                  <div
                    v-if="computedClinicalTags.length > 0"
                    class="geral-tags-row"
                  >
                    <div
                      v-for="(tag, index) in computedClinicalTags"
                      :key="index"
                      class="clinical-tag"
                      :class="'tag-' + tag.type"
                    >
                      <i :class="tag.icon" />
                      <span>{{ tag.label }}</span>
                    </div>
                  </div>
                  <p v-else class="text-sm text-slate-500">
                    Nenhuma tag clínica. Preencha a anamnese para gerar
                    automaticamente.
                  </p>
                </div>
              </div>

              <!-- ── Grid de 2 colunas: Tratamento + Dados da Conta ── -->
              <div class="reg-field-grid-2">
                <!-- Tratamento Ativo -->
                <div class="reg-section">
                  <div class="reg-section-toggle" style="cursor: default">
                    <div class="reg-section-toggle-left">
                      <div class="reg-section-icon reg-icon-blue">
                        <i class="i-lucide-stethoscope w-4 h-4" />
                      </div>
                      <div>
                        <span class="reg-section-title">Tratamento Ativo</span>
                        <span class="reg-section-subtitle"
                          >Plano e profissional responsável</span
                        >
                      </div>
                    </div>
                    <button
                      class="geral-action-btn"
                      @click="activeTab = 'treatment_plan'"
                    >
                      <i class="i-lucide-arrow-right w-3.5 h-3.5" />
                      Ver Planos
                    </button>
                  </div>
                  <div class="reg-section-body">
                    <div v-if="activePlanSummary">
                      <p class="geral-plan-title">
                        {{ activePlanSummary.title || 'Plano sem título' }}
                      </p>
                      <div class="flex items-center gap-2 mt-2">
                        <span
                          class="status-badge"
                          :class="
                            activePlanSummary.status === 'in_progress'
                              ? 'badge-blue'
                              : 'badge-green'
                          "
                        >
                          {{
                            activePlanSummary.status === 'in_progress'
                              ? 'Em andamento'
                              : activePlanSummary.status === 'approved'
                                ? 'Aprovado'
                                : activePlanSummary.status
                          }}
                        </span>
                        <span
                          v-if="activePlanSummary.estimated_duration"
                          class="text-slate-500 text-xs"
                        >
                          {{ activePlanSummary.estimated_duration }}
                        </span>
                      </div>
                      <p
                        v-if="activePlanSummary.description"
                        class="text-slate-400 text-xs mt-2 line-clamp-2"
                      >
                        {{ activePlanSummary.description }}
                      </p>
                    </div>
                    <p v-else class="text-sm text-slate-500">
                      Nenhum plano ativo.
                    </p>

                    <div class="geral-divider" />

                    <div class="geral-prof-row">
                      <div class="geral-prof-avatar">
                        <i class="i-lucide-user-check w-3.5 h-3.5" />
                      </div>
                      <div>
                        <span class="text-xs text-slate-500"
                          >Profissional Responsável</span
                        >
                        <p class="text-sm text-slate-200 font-medium mt-0.5">
                          {{ responsibleProfName }}
                        </p>
                      </div>
                    </div>
                  </div>
                </div>

                <!-- Dados da Conta -->
                <div class="reg-section">
                  <div class="reg-section-toggle" style="cursor: default">
                    <div class="reg-section-toggle-left">
                      <div class="reg-section-icon reg-icon-amber">
                        <i class="i-lucide-settings-2 w-4 h-4" />
                      </div>
                      <div>
                        <span class="reg-section-title">Dados da Conta</span>
                        <span class="reg-section-subtitle"
                          >Status, unidade e origem</span
                        >
                      </div>
                    </div>
                  </div>
                  <div class="reg-section-body">
                    <div class="form-group">
                      <label class="form-label">Status do Paciente</label>
                      <select
                        v-model="patient.patient_status"
                        class="form-input"
                        @change="handleStatusChange($event)"
                      >
                        <option value="novo">Novo</option>
                        <option value="ativo">Ativo</option>
                        <option value="inativo">Inativo</option>
                        <option value="faltoso">Faltoso</option>
                        <option value="alta">Alta</option>
                        <option value="arquivado">Arquivado</option>
                      </select>
                    </div>
                    <div class="geral-meta-row">
                      <div class="geral-meta-item">
                        <span class="geral-meta-label text-slate-500">Unidade / Clínica</span>
                        <span class="geral-meta-value text-slate-900 dark:text-slate-100">{{
                          patient.unit || '—'
                        }}</span>
                      </div>
                      <div class="geral-meta-item mt-4">
                        <span class="geral-meta-label text-slate-500">Origem (Lead)</span>
                        <span class="geral-meta-value text-slate-900 dark:text-slate-100">{{
                          patient.origin || '—'
                        }}</span>
                      </div>
                    </div>
                  </div>
                </div>
              </div>

              <!-- ── Jornada de Consultas ── -->
              <div class="reg-section">
                <div class="reg-section-toggle" style="cursor: default">
                  <div class="reg-section-toggle-left">
                    <div class="reg-section-icon reg-icon-green">
                      <i class="i-lucide-calendar-days w-4 h-4" />
                    </div>
                    <div>
                      <span class="reg-section-title"
                        >Jornada de Consultas</span
                      >
                      <span class="reg-section-subtitle"
                        >Última e próxima consulta agendada</span
                      >
                    </div>
                  </div>
                  <button
                    class="geral-header-btn"
                    @click="handleHeaderSchedule"
                  >
                    <i class="i-lucide-calendar-plus w-3.5 h-3.5" />
                    Agendar Consulta
                  </button>
                </div>
                <div class="reg-section-body">
                  <div class="reg-field-grid-2">
                    <!-- Última Consulta -->
                    <div class="geral-visit-card bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-sm p-4 md:p-6">
                      <div class="geral-visit-icon geral-visit-icon--past bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-400">
                        <i class="i-lucide-history w-4 h-4" />
                      </div>
                      <div class="geral-visit-info">
                        <span class="geral-visit-label text-slate-500">Última Consulta</span>
                        <template v-if="lastAppointmentFormatted">
                          <span class="geral-visit-date text-slate-900 dark:text-slate-100">{{
                            lastAppointmentFormatted.date
                          }}</span>
                          <span class="geral-visit-time">{{
                            lastAppointmentFormatted.time
                          }}</span>
                        </template>
                        <span
v-else class="geral-visit-empty"
                          >Nenhuma consulta registrada</span
                        >
                      </div>
                    </div>

                    <!-- Próxima Consulta -->
                    <div class="geral-visit-card geral-visit-card--next bg-slate-50 dark:bg-slate-800 border border-slate-200 dark:border-slate-700 rounded-xl shadow-sm p-4 md:p-6">
                      <div class="geral-visit-icon geral-visit-icon--next bg-emerald-100 dark:bg-emerald-900 text-emerald-600 dark:text-emerald-400">
                        <i class="i-lucide-calendar-clock w-4 h-4" />
                      </div>
                      <div class="geral-visit-info">
                        <span class="geral-visit-label text-slate-500">Próxima Consulta</span>
                        <template v-if="nextAppointmentFormatted">
                          <span
                            class="geral-visit-date geral-visit-date--highlight text-emerald-600 dark:text-emerald-400"
                            >{{ nextAppointmentFormatted.date }}</span
                          >
                          <span class="geral-visit-time">{{
                            nextAppointmentFormatted.time
                          }}</span>
                        </template>
                        <span
v-else class="geral-visit-empty"
                          >Nenhum agendamento futuro</span
                        >
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

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

          <!-- ABA: EVOLUÇÃO -->
          <div v-else-if="activeTab === 'evolution'" class="tab-pane fade-in">
            <div class="ev-tab-header">
              <div>
                <h3 class="ev-tab-title">Evolução / Atendimento</h3>
                <p class="ev-tab-subtitle">
                  Registro cronológico dos atendimentos. Novas entradas não
                  substituem as antigas.
                </p>
              </div>
            </div>
            <EvolutionTab
              :current-note="currentNote"
              :clinical-notes="clinicalNotes"
              :is-saving-note="isSavingNote"
              :format-date="formatDate"
              @update:current-note="currentNote = $event"
              @save="saveClinicalNote"
              @request-delete="requestDeleteNote"
              @edit-note="editClinicalNote"
            />
          </div>

          <!-- ABA: PLANO DE TRATAMENTO — extraída em tabs/TreatmentPlanTab.vue -->
          <TreatmentPlanTab
            v-else-if="activeTab === 'treatment_plan'"
            :key="`treatment_plan-${route.params.patientId}`"
            :agenda-services="agendaServices"
          />

          <!-- ABA: PROCEDIMENTOS — extraída em tabs/ProceduresTab.vue -->
          <ProceduresTab
            v-else-if="activeTab === 'procedures'"
            :key="`procedures-${route.params.patientId}`"
            :patient="patient"
            @open-exams="activeTab = 'exams'"
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

    <!-- Confirm Delete Note Modal -->
    <div
      v-if="showConfirmDeleteNote"
      class="delete-modal-overlay flex items-center justify-center fixed inset-0 backdrop-blur-sm z-[99999] bg-black/60"
      @click.self="cancelDeleteNote"
    >
      <div
        class="delete-modal-card rounded-xl shadow-xl w-full max-w-[420px] overflow-hidden bg-[var(--color-background,#1d2b3e)] border border-white/10"
      >
        <div class="p-6">
          <div class="flex items-start gap-4">
            <div
              class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-rose-500/10"
            >
              <i class="i-lucide-alert-triangle size-5 text-rose-500" />
            </div>
            <div class="flex flex-col gap-2 pt-1">
              <h3 class="font-medium text-slate-100 m-0 text-lg leading-tight">
                Excluir Rascunho?
              </h3>
              <p class="text-slate-400 m-0 text-sm leading-relaxed">
                Deseja realmente excluir este rascunho de evolução? Esta ação
                não pode ser desfeita.
              </p>
            </div>
          </div>
        </div>
        <div
          class="px-6 py-4 flex justify-end gap-3 border-t border-white/10 bg-white/5"
        >
          <button
            class="rounded-lg px-4 py-2 text-sm font-medium bg-transparent text-slate-400 hover:text-slate-100 hover:bg-slate-800 transition-colors border-0 cursor-pointer"
            @click="cancelDeleteNote"
          >
            Cancelar
          </button>
          <button
            class="flex items-center justify-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold text-rose-500 hover:text-rose-400 hover:bg-rose-500/10 bg-transparent transition-all border-0 cursor-pointer"
            @click="confirmDeleteNote"
          >
            Excluir
          </button>
        </div>
      </div>
    </div>






    <!-- FAB Mobile: Abrir Sidebar -->
    <button
      class="lg:hidden fixed bottom-6 right-6 w-14 h-14 bg-n-alpha-2 backdrop-blur-lg shadow hover:shadow-md border border-n-strong text-n-slate-12 rounded-full flex items-center justify-center z-30 transition-all duration-200 active:scale-95 hover:brightness-110"
      @click="isSidebarOpen = true"
    >
      <i class="i-lucide-menu w-6 h-6" />
    </button>
  </div>
</template>

<style scoped>
@media print {
  .hide-on-print {
    display: none !important;
  }
  body,
  .record-container {
    background: white !important;
    color: black !important;
  }
  .record-header,
  .menu-sidebar {
    display: none !important;
  }
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
  .tab-pane {
    animation: none !important;
  }
  .card,
  .form-section {
    box-shadow: none !important;
    border: 1px solid #ccc !important;
    background: white !important;
    color: black !important;
    break-inside: avoid;
    page-break-inside: avoid;
  }
  * {
    color: black !important;
  }
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

.critical-popup-body {
  display: flex;
  flex-direction: column;
  gap: 8px;
}
.status-select {
  padding: 4px 28px 4px 12px !important;
  font-size: 13px !important;
  font-weight: 500 !important;
  height: 32px !important;
  width: auto !important;
  margin-top: 4px;
}

/* Patient status badge — colored static tag in header */
.patient-status-badge {
  display: inline-flex;
  align-items: center;
  padding: 3px 12px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
  margin-top: 4px;
  letter-spacing: 0.02em;
  width: fit-content;
  max-width: fit-content;
  align-self: flex-start;
}
.patient-status-badge.status-novo {
  background: rgba(59, 130, 246, 0.15);
  color: #60a5fa;
  border: 1px solid rgba(59, 130, 246, 0.3);
}
.patient-status-badge.status-ativo {
  background: rgba(34, 197, 94, 0.15);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.3);
}
.patient-status-badge.status-inativo {
  background: rgba(100, 116, 139, 0.15);
  color: #94a3b8;
  border: 1px solid rgba(100, 116, 139, 0.3);
}
.patient-status-badge.status-faltoso {
  background: rgba(234, 179, 8, 0.15);
  color: #fde047;
  border: 1px solid rgba(234, 179, 8, 0.3);
}
.patient-status-badge.status-alta {
  background: rgba(168, 85, 247, 0.15);
  color: #c084fc;
  border: 1px solid rgba(168, 85, 247, 0.3);
}
.patient-status-badge.status-arquivado {
  background: rgba(71, 85, 105, 0.15);
  color: #64748b;
  border: 1px solid rgba(71, 85, 105, 0.3);
}

.record-container {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  background: var(--color-background, #121212);
  color: #f1f5f9;
  padding: 24px 32px;
  box-sizing: border-box;
  overflow-y: auto;
  font-family: inherit;
}

/* ====== HEADER/TOP ACTIONS ====== */
.header-nav {
  margin-bottom: 24px;
}

.btn-back {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 8px;
  background: transparent;
  border: none;
  color: #94a3b8;
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  padding: 0 16px;
  min-height: 36px;
  border-radius: 8px;
  transition: all 0.2s;
}

.btn-back:hover {
  color: #f1f5f9;
}

.btn-primary,
.btn-secondary {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 0 16px;
  height: 40px;
  border-radius: 8px;
  font-weight: 500;
  font-size: 14px;
  cursor: pointer;
  transition: all 0.2s ease;
}

.btn-primary {
  background: #3b82f6;
  color: #fff;
  border: none;
  box-shadow: none;
}
.btn-primary:hover {
  background: #2563eb;
}

.btn-secondary {
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-12));
  border: 1px solid rgb(var(--border-strong));
  box-shadow: none;
}
.btn-secondary:hover {
  background: rgb(var(--slate-4));
  border-color: rgb(var(--slate-7));
  color: rgb(var(--slate-12));
}

.record-layout {
  display: flex;
  gap: 24px;
  align-items: flex-start;
  min-height: min-content; /* Ensure container can grow with content */
}

.menu-sidebar {
  flex: 0 0 240px;
  max-width: 240px;
  position: sticky;
  top: 132px; /* Fix the left menu underneath the header banner */
  overflow-y: auto; /* Adiciona scroll interno no menu se as abas passarem do viewport */
  border-radius: 16px;
  padding: 12px;
}

/* Esconde scrollbar do menu para manter a estética limpa */
.menu-sidebar::-webkit-scrollbar {
  width: 4px;
}
.menu-sidebar::-webkit-scrollbar-track {
  background: transparent;
}
.menu-sidebar::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.1);
  border-radius: 4px;
}
.menu-sidebar::-webkit-scrollbar-thumb:hover {
  background: rgba(255, 255, 255, 0.2);
}

.main-content {
  flex: 1;
  min-width: 0; /* Previne overlay de flex children */
  display: flex;
  flex-direction: column;
}

@media (max-width: 1024px) {
  .record-layout {
    flex-direction: column;
  }
  .profile-sidebar {
    flex: none;
    max-width: 100%;
    position: static;
  }
}

/* NAVEGAÇÃO DE ABAS VERTICAL */
.vertical-tabs-nav {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.vertical-tab-btn {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 12px 16px;
  background: transparent;
  border: none;
  border-radius: 8px;
  color: rgb(var(--slate-10));
  font-size: 14px;
  font-weight: 500;
  text-align: left;
  cursor: pointer;
  transition: all 0.2s;
}

.vertical-tab-btn i {
  font-size: 16px;
  flex-shrink: 0;
}

.vertical-tab-btn:hover {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-3));
}

.vertical-tab-btn.active {
  color: #3b82f6;
  background: rgba(59, 130, 246, 0.1);
}

/* CONTEÚDO DAS ABAS */
.tab-content-area {
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.fade-in {
  animation: fadeIn 0.3s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(5px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

/* CARDS PADRÃO */
.card {
  background: #1c1c1d;
  border: 1px solid rgba(255, 255, 255, 0.05);
  border-radius: 16px;
  padding: 24px;
}

.card-title {
  margin: 0 0 16px;
  font-size: 16px;
  font-weight: 600;
  color: #f1f5f9;
}


.form-section {
  padding: 24px;
}

.form-section-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 20px;
  padding-bottom: 12px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
}

.form-section-header i {
  color: #3b82f6;
  font-size: 20px;
}

.form-section-header h4 {
  font-size: 16px;
  font-weight: 600;
  color: #f1f5f9;
  margin: 0;
}


/* Required asterisk */
.reg-required {
  color: #f87171;
  margin-left: 2px;
}


.form-row-1,
.form-row-2,
.form-row-3,
.form-row-cep {
  display: grid;
  gap: 16px;
  margin-bottom: 16px;
}

.form-row-2 {
  grid-template-columns: repeat(2, 1fr);
}
.form-row-3 {
  grid-template-columns: repeat(3, 1fr);
}
.form-row-cep {
  grid-template-columns: 1fr 2fr;
}

@media (max-width: 768px) {
  .form-row-2,
  .form-row-3,
  .form-row-cep {
    grid-template-columns: 1fr;
  }
}

.form-group {
  display: flex;
  flex-direction: column;
  gap: 6px;
}

.form-group label {
  font-size: 13px;
  font-weight: 500;
  color: #cbd5e1;
}

.form-input {
  background: rgba(0, 0, 0, 0.2);
  border: 1px solid rgba(255, 255, 255, 0.1);
  color: #f1f5f9;
  border-radius: 8px;
  padding: 10px 14px;
  font-size: 14px;
  font-family: inherit;
  transition: border-color 0.2s;
  width: 100%;
}

.form-textarea {
  resize: vertical;
  min-height: 80px;
}

.form-input:focus {
  outline: none;
  border-color: #3b82f6;
  background: rgba(0, 0, 0, 0.3);
}

.form-input::placeholder {
  color: #475569;
}

select.form-input {
  appearance: none;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' viewBox='0 0 24 24' fill='none' stroke='%2394a3b8' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Cpolyline points='6 9 12 15 18 9'%3E%3C/polyline%3E%3C/svg%3E");
  background-repeat: no-repeat;
  background-position: right 12px center;
  padding-right: 40px;
}

.input-with-action {
  position: relative;
  display: flex;
  align-items: center;
}

.btn-icon-inside {
  position: absolute;
  right: 8px;
  background: transparent;
  border: none;
  color: #94a3b8;
  cursor: pointer;
  padding: 4px;
  border-radius: 4px;
}

.btn-icon-inside:hover {
  background: rgba(255, 255, 255, 0.1);
  color: #f1f5f9;
}

.checkbox-group {
  gap: 12px;
}

.checkbox-label {
  display: flex;
  align-items: center;
  gap: 10px;
  cursor: pointer;
  font-size: 13px !important;
  color: #cbd5e1 !important;
  font-weight: 400 !important;
}

.checkbox-label input[type='checkbox'] {
  margin-top: 2px;
  accent-color: #3b82f6;
  width: 16px;
  height: 16px;
  cursor: pointer;
}

.avatar-wrapper-small {
  position: relative;
  width: 56px;
  height: 56px;
  display: flex;
  justify-content: center;
}

.avatar-img-small,
.avatar-placeholder-small {
  width: 56px;
  height: 56px;
  border-radius: 50%;
  border: 2px solid rgba(255, 255, 255, 0.05);
  object-fit: cover;
}

.avatar-placeholder-small {
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #3b82f6, #8b5cf6);
  font-size: 20px;
  font-weight: 600;
  color: #fff;
}

.status-badge-small {
  position: absolute;
  bottom: -6px;
  left: 50%;
  transform: translateX(-50%);
  padding: 2px 8px;
  border-radius: 12px;
  font-size: 9px;
  font-weight: 700;
  text-transform: uppercase;
  white-space: nowrap;
  border: 2px solid #1c1c1d;
  z-index: 2;
}

.status-em-tratamento {
  background: #fbbf24;
  color: #78350f;
}
.status-novo {
  background: #3b82f6;
  color: #eff6ff;
}
.status-em-avaliação {
  background: #a855f7;
  color: #faf5ff;
}
.status-ativo {
  background: #22c55e;
  color: #022c22;
}
.status-inativo {
  background: #94a3b8;
  color: #0f172a;
}
.status-alta {
  background: #14b8a6;
  color: #042f2e;
}
.status-abandonou {
  background: #ef4444;
  color: #450a0a;
}
.status-faltoso {
  background: #f97316;
  color: #431407;
}

/* ── Header Buttons (hdr-*) ────────────────────────────────── */
.hdr-btn {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 0 13px;
  height: 36px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition:
    background 0.15s,
    border-color 0.15s,
    color 0.15s;
  white-space: nowrap;
  flex-shrink: 0;
  border: 1px solid transparent;
}

.hdr-btn--secondary {
  background: rgba(255, 255, 255, 0.04);
  border-color: rgba(255, 255, 255, 0.09);
  color: #94a3b8;
}
.hdr-btn--secondary:hover {
  background: rgba(255, 255, 255, 0.08);
  border-color: rgba(255, 255, 255, 0.14);
  color: #e2e8f0;
}

.hdr-btn--charge {
  background: rgba(34, 197, 94, 0.07);
  border-color: rgba(34, 197, 94, 0.18);
  color: #4ade80;
}
.hdr-btn--charge:hover {
  background: rgba(34, 197, 94, 0.13);
  border-color: rgba(34, 197, 94, 0.28);
}

.hdr-btn--primary {
  background: #3b82f6;
  border-color: #3b82f6;
  color: #fff;
}
.hdr-btn--primary:hover {
  background: #2563eb;
  border-color: #2563eb;
}

.hdr-divider {
  width: 1px;
  height: 22px;
  background: rgba(255, 255, 255, 0.08);
  flex-shrink: 0;
}

/* ── Profile Banner ────────────────────────────────────────── */
.profile-banner {
  display: flex;
  justify-content: space-between;
  align-items: center;
  background: #1c1c1d;
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px;
  padding: 16px 20px;
  margin-bottom: 20px;
  position: sticky;
  top: 0;
  z-index: 10;
  gap: 16px;
}

.profile-banner-left {
  display: flex;
  align-items: center;
  gap: 14px;
  min-width: 0;
  flex: 1;
}

/* ── Avatar ── */
.pb-avatar-wrap {
  position: relative;
  flex-shrink: 0;
}

.pb-avatar-img,
.pb-avatar-placeholder {
  width: 52px;
  height: 52px;
  border-radius: 12px;
  object-fit: cover;
  display: flex;
  align-items: center;
  justify-content: center;
}

.pb-avatar-img {
  border: 1px solid rgba(255, 255, 255, 0.1);
}

.pb-avatar-placeholder {
  background: rgba(59, 130, 246, 0.15);
  border: 1px solid rgba(59, 130, 246, 0.2);
  color: #60a5fa;
  font-size: 20px;
  font-weight: 600;
}

.pb-status-dot {
  position: absolute;
  bottom: -3px;
  right: -3px;
  width: 13px;
  height: 13px;
  border-radius: 50%;
  border: 2px solid #0e1016;
}
.pb-dot-novo {
  background: #60a5fa;
}
.pb-dot-ativo {
  background: #4ade80;
}
.pb-dot-inativo {
  background: #94a3b8;
}
.pb-dot-faltoso {
  background: #fbbf24;
}
.pb-dot-alta {
  background: #c084fc;
}
.pb-dot-arquivado {
  background: #64748b;
}

/* ── Identity ── */
.pb-identity {
  display: flex;
  flex-direction: column;
  gap: 5px;
  min-width: 0;
}

.pb-name-row {
  display: flex;
  align-items: center;
  gap: 8px;
}

.pb-name {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: #f1f5f9;
  line-height: 1.2;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* ── Meta row ── */
.pb-meta-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

.pb-meta-text {
  font-size: 13px;
  color: #64748b;
}

.pb-meta-sep {
  font-size: 12px;
  color: #334155;
}

/* Status pill */
.pb-status-pill {
  display: inline-flex;
  align-items: center;
  padding: 2px 8px;
  border-radius: 99px;
  font-size: 10px;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border: 1px solid transparent;
}
.pb-pill-novo {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.2);
}
.pb-pill-ativo {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.2);
}
.pb-pill-inativo {
  background: rgba(100, 116, 139, 0.12);
  color: #94a3b8;
  border-color: rgba(100, 116, 139, 0.2);
}
.pb-pill-faltoso {
  background: rgba(251, 191, 36, 0.1);
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.2);
}
.pb-pill-alta {
  background: rgba(168, 85, 247, 0.1);
  color: #c084fc;
  border-color: rgba(168, 85, 247, 0.2);
}
.pb-pill-arquivado {
  background: rgba(71, 85, 105, 0.1);
  color: #64748b;
  border-color: rgba(71, 85, 105, 0.2);
}

/* ── Info chips ── */
.pb-chips {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 6px;
  margin-top: 2px;
}

.pb-chip {
  display: flex;
  align-items: center;
  gap: 5px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.07);
  border-radius: 6px;
  padding: 3px 8px;
  font-size: 12px;
  color: #94a3b8;
  white-space: nowrap;
  transition:
    background 0.15s,
    border-color 0.15s;
}

.pb-chip-icon {
  color: #475569;
  flex-shrink: 0;
}

/* ── Right side: finance badge ── */
.pb-right {
  flex-shrink: 0;
  display: flex;
  align-items: center;
}

.pb-finance-badge {
  display: flex;
  align-items: center;
  gap: 7px;
  padding: 7px 14px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 600;
  border: 1px solid transparent;
}

.pb-finance-adimplente {
  background: rgba(34, 197, 94, 0.08);
  color: #4ade80;
  border-color: rgba(34, 197, 94, 0.18);
}
.pb-finance-inadimplente {
  background: rgba(239, 68, 68, 0.08);
  color: #f87171;
  border-color: rgba(239, 68, 68, 0.18);
}
.pb-finance-crédito,
.pb-finance-credito {
  background: rgba(59, 130, 246, 0.08);
  color: #60a5fa;
  border-color: rgba(59, 130, 246, 0.18);
}
.pb-finance-em.pb-finance-aberto {
  background: rgba(251, 191, 36, 0.08);
  color: #fbbf24;
  border-color: rgba(251, 191, 36, 0.18);
}

@media (max-width: 1280px) {
  .hide-mobile {
    display: none;
  }
}

@media (max-width: 1024px) {
  .profile-banner {
    flex-direction: column;
    align-items: flex-start;
    gap: 14px;
    position: static;
  }
  .hide-mobile {
    display: flex;
  }
}

/* POPUP E ÍCONE CLÍNICO */
.critical-alert-container {
  position: relative;
  display: flex;
  align-items: center;
}

.btn-critical-alert {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 32px;
  border-radius: 50%;
  background: rgba(239, 68, 68, 0.15);
  border: 1px solid rgba(239, 68, 68, 0.3);
  color: #ef4444;
  font-size: 20px;
  cursor: pointer;
  transition: all 0.2s;
}

.btn-critical-alert:hover {
  background: rgba(239, 68, 68, 0.25);
  transform: scale(1.05);
}

.critical-popup {
  position: absolute;
  top: calc(100% + 12px);
  left: -3px;
  width: 320px;
  background: #1c1c1d;
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 12px;
  box-shadow: 0 10px 30px rgba(0, 0, 0, 0.6);
  z-index: 100;
  animation: fadeIn 0.2s ease-out;
  text-align: left;
}

/* Seta pro balãozinho */
.critical-popup::before {
  content: '';
  position: absolute;
  top: -6px;
  left: 14px;
  transform: rotate(45deg);
  width: 10px;
  height: 10px;
  background: #1c1c1d;
  border-top: 1px solid rgba(239, 68, 68, 0.3);
  border-left: 1px solid rgba(239, 68, 68, 0.3);
}

.popup-header {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 16px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.05);
  color: #ef4444;
  font-size: 13px;
  font-weight: 600;
}

.popup-header i {
  font-size: 16px;
}

.btn-close-popup {
  margin-left: auto;
  background: transparent;
  border: none;
  color: #94a3b8;
  cursor: pointer;
  font-size: 16px;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0;
}

.btn-close-popup:hover {
  color: #f1f5f9;
}

.popup-body {
  padding: 12px 16px;
  font-size: 13px;
  color: #cbd5e1;
  line-height: 1.5;
}

.finance-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
}
.finance-adimplente {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
}
.finance-inadimplente {
  background: rgba(239, 68, 68, 0.1);
  color: #f87171;
}
.finance-crédito {
  background: rgba(59, 130, 246, 0.1);
  color: #60a5fa;
}

.divider {
  width: 100%;
  height: 1px;
  background: rgba(255, 255, 255, 0.05);
  margin: 24px 0;
}

.info-list {
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 16px;
  text-align: left;
}

.info-item {
  display: flex;
  align-items: flex-start;
  gap: 12px;
}

.info-item i {
  color: #64748b;
  font-size: 18px;
  margin-top: 2px;
  flex-shrink: 0;
}

.info-data {
  display: flex;
  flex-direction: column;
  overflow: hidden; /* Avoid text expanding the card */
}

.info-label {
  font-size: 12px;
  color: #94a3b8;
  margin-bottom: 2px;
}

.info-value {
  font-size: 14px;
  color: #e2e8f0;
  font-weight: 500;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* PLACEHOLDER / STATES */
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

/* TAGS */
.tags-container {
  display: flex;
  flex-wrap: wrap;
  gap: 8px;
}

.clinical-tag {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 500;
}

.tag-danger {
  background: rgba(239, 68, 68, 0.15);
  color: #fca5a5;
  border: 1px solid rgba(239, 68, 68, 0.3);
}
.tag-warning {
  background: rgba(245, 158, 11, 0.15);
  color: #fcd34d;
  border: 1px solid rgba(245, 158, 11, 0.3);
}
.tag-info {
  background: rgba(59, 130, 246, 0.15);
  color: #93c5fd;
  border: 1px solid rgba(59, 130, 246, 0.3);
}

.btn-add-tag {
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: 1px dashed rgba(255, 255, 255, 0.2);
  color: #94a3b8;
  padding: 6px 12px;
  border-radius: 8px;
  cursor: pointer;
  transition: all 0.2s;
}
.btn-add-tag:hover {
  background: rgba(255, 255, 255, 0.05);
  color: #fff;
}

/* 2 COLS ROW */
.row-2-cols {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 24px;
  margin-bottom: 24px;
}

@media (max-width: 768px) {
  .row-2-cols {
    grid-template-columns: 1fr;
  }
}

.detail-group {
  display: flex;
  flex-direction: column;
  margin-bottom: 12px;
}
.detail-group:last-child {
  margin-bottom: 0;
}

.detail-label {
  font-size: 12px;
  color: #94a3b8;
  margin-bottom: 4px;
}

.detail-value {
  font-size: 15px;
  color: #e2e8f0;
}

.detail-value.highlight {
  color: #3b82f6;
  font-weight: 500;
}

.mt-2 {
  margin-top: 16px;
}

.prof-badge {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgba(255, 255, 255, 0.05);
  padding: 6px 12px;
  border-radius: 8px;
  font-size: 13px;
  color: #cbd5e1;
  width: fit-content;
}

.status-chip {
  padding: 4px 10px;
  border-radius: 6px;
  font-size: 11px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.02em;
}

.status-approved {
  background: rgba(34, 197, 94, 0.1);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.2);
}

.status-pending {
  background: rgba(245, 158, 11, 0.1);
  color: #fbbf24;
  border: 1px solid rgba(245, 158, 11, 0.2);
}

/* TIMELINE E EVOLUÇÃO */
.align-end {
  align-items: flex-end;
}

.timeline-container {
  margin-top: 32px;
  padding-top: 16px;
}

.timeline-wrapper {
  position: relative;
  padding-left: 18px; /* Espaço para o eixo da timeline centralizado com o marcador */
}

/* Linha da timeline conectando os pontos */
.timeline-wrapper::before {
  content: '';
  position: absolute;
  top: 10px;
  bottom: 0;
  left: 18px; /* centraliza a linha exatamente no meio do marcador que tem 36px e fica com `left: 0` */
  width: 2px;
  background: rgba(255, 255, 255, 0.05); /* soft line */
  z-index: 0;
}

.timeline-item {
  position: relative;
  display: flex;
  align-items: stretch;
  z-index: 1; /* z-index maior q a linha para cobrir com bg-color */
}

.timeline-marker {
  position: absolute;
  left: 0;
  top: 0; /* Alinha com o inicio do card */
  width: 36px;
  height: 36px;
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 16px;
  z-index: 2; /* Importante p sobrepor a linha fina da borda esquerda */
}

.timeline-content {
  flex: 1;
  margin-left: 56px; /* espaço pro icone (36px + 20px gap) */
  margin-bottom: 24px;
}
.timeline-content:hover {
  border-color: rgba(255, 255, 255, 0.15);
}

.visits-grid-2 {
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 16px;
}

@media (max-width: 640px) {
  .visits-grid-2 {
    grid-template-columns: 1fr;
  }
}

.visit-box {
  display: flex;
  align-items: center;
  gap: 12px;
  background: rgba(0, 0, 0, 0.2);
  padding: 16px;
  border-radius: 12px;
  border: 1px solid rgba(255, 255, 255, 0.03);
}

.visit-box.highlight-box {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgba(59, 130, 246, 0.2);
}

.visit-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border-radius: 8px;
  font-size: 18px;
}
.prev {
  background: rgba(148, 163, 184, 0.2);
  color: #cbd5e1;
}
.next {
  background: rgba(59, 130, 246, 0.2);
  color: #60a5fa;
}

.visit-info {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.v-label {
  font-size: 12px;
  color: #94a3b8;
}

.v-date {
  font-size: 14px;
  color: #e2e8f0;
}
.v-date.font-bold {
  font-weight: 600;
  color: #fff;
}

/* compact appointment layout */
.visit-compact-row {
  display: flex;
  align-items: baseline;
  gap: 6px;
  flex-wrap: wrap;
}

.v-time-inline {
  font-size: 12px;
  color: #64748b;
}

.v-title-compact {
  font-size: 12px;
  color: #60a5fa;
  margin-top: 2px;
  display: block;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  max-width: 200px;
}

/* keep legacy .v-time/.v-title for any other use */
.v-time {
  font-size: 12px;
  color: #94a3b8;
}

.v-title {
  font-size: 13px;
  color: #60a5fa;
  font-weight: 500;
}

/* card-header-row: title + action button side-by-side */
.card-header-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 12px;
}
.card-header-row .card-title {
  margin-bottom: 0;
}

/* btn-xs: small ghost button */
.btn-xs {
  font-size: 11px;
  padding: 3px 10px;
  border-radius: 6px;
  border: 1px solid rgb(var(--border-strong));
  background: rgb(var(--slate-2));
  color: rgb(var(--slate-11));
  cursor: pointer;
  transition: all 0.15s;
  white-space: nowrap;
}
.btn-xs:hover {
  background: rgb(var(--slate-4));
  border-color: rgb(var(--slate-7));
  color: rgb(var(--slate-12));
}

/* critical-banner */
.critical-banner {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  padding: 14px 18px;
  background: rgba(239, 68, 68, 0.12);
  border: 1px solid rgba(239, 68, 68, 0.35);
  border-radius: 12px;
  color: #fca5a5;
  font-size: 14px;
}
.critical-banner i {
  font-size: 20px;
  flex-shrink: 0;
  margin-top: 2px;
}

/* pinned-note-card */
.pinned-note-card {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 12px 16px;
  background: rgba(234, 179, 8, 0.1);
  border: 1px solid rgba(234, 179, 8, 0.25);
  border-radius: 12px;
  color: #fde68a;
  font-size: 14px;
}
.pinned-note-card i {
  font-size: 16px;
  flex-shrink: 0;
}

/* status-badge variants */
.status-badge {
  display: inline-flex;
  align-items: center;
  padding: 2px 10px;
  border-radius: 20px;
  font-size: 12px;
  font-weight: 600;
}
.badge-green {
  background: rgba(34, 197, 94, 0.15);
  color: #4ade80;
  border: 1px solid rgba(34, 197, 94, 0.25);
}
.badge-blue {
  background: rgba(59, 130, 246, 0.15);
  color: #60a5fa;
  border: 1px solid rgba(59, 130, 246, 0.25);
}
.badge-yellow {
  background: rgba(234, 179, 8, 0.15);
  color: #fde047;
  border: 1px solid rgba(234, 179, 8, 0.25);
}
.badge-red {
  background: rgba(239, 68, 68, 0.15);
  color: #f87171;
  border: 1px solid rgba(239, 68, 68, 0.25);
}

/* treatment-meta */
.treatment-meta {
  display: flex;
  align-items: center;
  gap: 8px;
}

/* quick-nav-row */
.quick-nav-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.quick-nav-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 12px 16px;
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px;
  color: #94a3b8;
  cursor: pointer;
  font-size: 12px;
  transition: all 0.15s;
  flex: 1;
  min-width: 70px;
}
.quick-nav-btn i {
  font-size: 18px;
  color: #60a5fa;
}
.quick-nav-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgba(59, 130, 246, 0.25);
  color: #e2e8f0;
}

/* macOS-style drag animation for exam cards */
.exam-card-dragging {
  transform: scale(0.82) rotate(-2deg) !important;
  opacity: 0.55 !important;
  box-shadow: 0 16px 40px rgba(0, 0, 0, 0.6) !important;
  z-index: 50;
  transition:
    transform 0.18s cubic-bezier(0.4, 0, 0.2, 1),
    opacity 0.18s ease,
    box-shadow 0.18s ease !important;
}


/* ── Archived Patient Banner ────────────────────── */
.archived-banner {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  background: rgba(245, 158, 11, 0.08);
  border: 1px solid rgba(245, 158, 11, 0.28);
  border-radius: 12px;
  padding: 14px 20px;
  margin-bottom: 16px;
}

.archived-banner-left {
  display: flex;
  align-items: center;
  gap: 12px;
  color: #fbbf24;
}

.archived-banner-title {
  font-size: 13px;
  font-weight: 600;
  color: #fbbf24;
  margin: 0;
  line-height: 1.3;
}

.archived-banner-sub {
  font-size: 12px;
  color: #d97706;
  margin: 2px 0 0;
  line-height: 1.3;
}

.archived-banner-btn {
  display: flex;
  align-items: center;
  gap: 7px;
  background: rgba(245, 158, 11, 0.12);
  border: 1px solid rgba(245, 158, 11, 0.3);
  border-radius: 7px;
  color: #fbbf24;
  font-size: 13px;
  font-weight: 500;
  padding: 7px 14px;
  cursor: pointer;
  transition: all 0.15s;
  white-space: nowrap;
  flex-shrink: 0;
}

.archived-banner-btn:hover {
  background: rgba(245, 158, 11, 0.2);
  border-color: rgba(245, 158, 11, 0.45);
}

/* ── Archived Read-Only Mode ─────────────────────── */
.is-archived .record-layout,
.is-archived .profile-banner {
  opacity: 0.75;
}

.is-archived .record-layout input,
.is-archived .record-layout textarea,
.is-archived .record-layout select,
.is-archived .record-layout .reg-toggle,
.is-archived .record-layout .reg-avatar-wrapper,
.is-archived .record-layout .tab-content-area button:not(.archived-banner-btn),
.is-archived .record-layout button:not(.vertical-tab-btn):not(.btn-back) {
  pointer-events: none;
  opacity: 0.5;
  cursor: not-allowed;
  filter: grayscale(0.4);
}

.is-archived .record-layout input,
.is-archived .record-layout textarea,
.is-archived .record-layout select {
  background: rgba(30, 30, 35, 0.6) !important;
  border-color: rgba(100, 116, 139, 0.2) !important;
  color: #64748b !important;
}

.is-archived .record-layout label,
.is-archived .record-layout .form-label {
  color: #475569;
}

.is-archived .archived-banner-btn {
  pointer-events: all;
  opacity: 1;
  cursor: pointer;
  filter: none;
}
</style>
