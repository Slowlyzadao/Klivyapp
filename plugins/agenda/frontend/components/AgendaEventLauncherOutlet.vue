<script setup>
import { computed } from 'vue';
import { useStore } from 'vuex';
import AgendaEventModal from './AgendaEventModal.vue';
import AgendaDeleteModal from './AgendaDeleteModal.vue';
import { useAgendaEventLauncher } from '../composables/useAgendaEventLauncher.js';
import { usePermissions } from 'dashboard/composables/usePermissions';

// Outlet único do modal de agenda — montado em Dashboard.vue. Vincula o
// AgendaEventModal ao launcher singleton, então abrir do botão "Agendar
// consulta" em ContactInfo.vue ou do "+ Novo Evento" em AgendaDashboard.vue
// usa exatamente a mesma instância (sem duplicar Teleport / state).
const store = useStore();
const launcher = useAgendaEventLauncher();
const agenda = launcher.agenda;
const newEvent = launcher.newEvent;
const autoCreatePatient = launcher.autoCreatePatient;
const hideBlockTab = launcher.hideBlockTab;

const { can: klivyCan, scope: klivyScope } = usePermissions();
const currentUser = computed(() => store.getters['getCurrentUser']);
const currentUserId = computed(() => currentUser.value?.id);
const isAdmin = computed(() => {
  const role = currentUser.value?.role;
  return role === 'administrator' || role === 'supervisor';
});

// Mesma regra que AgendaDashboard usa para o seletor de agente do modal:
// não-providers (recepção/gerência com `agenda.view` + scope='all') e
// administradores enxergam todos; provider comum vê apenas a própria coluna.
const canViewAllAgenda = computed(() => {
  if (isAdmin.value) return true;
  return klivyCan('agenda', 'view') && klivyScope('agenda') === 'all';
});

const allAgents = computed(() => {
  const list = store.getters['agents/getAgents'] || [];
  return agenda.buildAgentList(list);
});

const visibleAgentList = computed(() =>
  agenda.getVisibleAgentList(
    allAgents.value,
    canViewAllAgenda.value,
    currentUserId.value
  )
);

const treatmentOptions = computed(() => {
  const services = store.getters['agendaServices/allServices'] || [];
  if (services.length) return services;
  return agenda.state.agendaSettingsData?.treatments || [];
});

const categoryOptions = computed(
  () => store.getters['agendaCategories/activeCategories'] || []
);
</script>

<template>
  <AgendaEventModal
    :show="agenda.state.showNewEventModal"
    :is-editing="agenda.state.isEditing"
    :editing-event-id="agenda.state.editingEventId"
    :new-event="newEvent"
    :custom-attributes-config="agenda.state.customAttributesConfig"
    :agents="visibleAgentList"
    :treatment-options="treatmentOptions"
    :category-options="categoryOptions"
    :agenda-settings="agenda.state.agendaSettingsData"
    :is-slot-blocked="agenda.isHourBlocked"
    :is-saving="agenda.state.isSaving"
    :is-deleting="agenda.state.isDeleting"
    :auto-create-patient="autoCreatePatient"
    :hide-block-tab="hideBlockTab"
    @close="launcher.closeEventModal"
    @save="launcher.saveEvent"
    @delete="launcher.deleteEvent"
    @update:new-event="v => (newEvent = v)"
  />
  <AgendaDeleteModal
    :show="agenda.state.showConfirmDelete"
    :is-deleting="agenda.state.isDeleting"
    @cancel="launcher.cancelDelete"
    @confirm="launcher.confirmDelete"
  />
</template>
