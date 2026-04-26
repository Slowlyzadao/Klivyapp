<script setup>
import { ref, computed, onMounted, watch } from 'vue';
import { useStore } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { usePermissions } from 'dashboard/composables/usePermissions';
import AgendaSettingsAPI from '@plugins/agenda/frontend/api/agendaSettings';

import SettingsTabSchedules from '../../features/settings/components/SettingsTabSchedules.vue';
import SettingsTabNotifications from '../../features/settings/components/SettingsTabNotifications.vue';
import SettingsTabOnlineBooking from '../../features/settings/components/SettingsTabOnlineBooking.vue';
import SettingsTabServices from '../../features/settings/components/SettingsTabServices.vue';
import PermissionDenied from '@plugins/custom_roles/frontend/components/PermissionDenied.vue';

const store = useStore();
const { can } = usePermissions();

const canViewSettings = computed(() => can('agenda', 'view_settings'));
const canManageSchedules = computed(() => can('agenda', 'manage_schedules'));
const canViewNotifications = computed(() => can('agenda', 'view_notifications'));
const canManageNotifications = computed(() => can('agenda', 'manage_notifications'));
const canManageOnlineBooking = computed(() => can('agenda', 'manage_online_booking'));
const canManageServices = computed(() => can('agenda', 'manage_services'));

// ─── TABS ───
const allTabs = [
  { id: 'horarios', label: 'Horários', icon: 'i-lucide-clock', allowed: canManageSchedules },
  { id: 'notificacoes', label: 'Notificações automáticas', icon: 'i-lucide-bell', allowed: computed(() => canViewNotifications.value || canManageNotifications.value) },
  { id: 'agendamento', label: 'Agendamento online', icon: 'i-lucide-calendar-plus', allowed: canManageOnlineBooking },
  { id: 'servicos', label: 'Serviços', icon: 'i-lucide-syringe', allowed: canManageServices },
];
const tabs = computed(() => allTabs.filter(tab => tab.allowed.value));
const activeTab = ref(tabs.value[0]?.id || 'horarios');
watch(tabs, list => {
  if (!list.find(t => t.id === activeTab.value)) {
    activeTab.value = list[0]?.id || '';
  }
});

const setTab = (tab, event) => {
  activeTab.value = tab;
  if (event && event.currentTarget) {
    event.currentTarget.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
  }
};

// ─── AUTH & AGENTS (usado por Agendamento) ───
const accountId = computed(() => store.getters.getCurrentAccountId);
const currentUser = computed(() => store.getters.getCurrentUser);
const isAdmin = computed(() => {
  const role = currentUser.value?.role;
  return role === 'administrator' || role === 'super_admin';
});
const agents = computed(() => {
  const all = store.getters['agents/getAgents'] || [];
  return all.filter((a) => a.id !== currentUser.value?.id);
});

// ─── SETTINGS CORE (Schedules / Global) ───
const saving = ref(false);
const blockOutsideWorkingHours = ref(false);
const blockLunchBreak = ref(false);
const agendaSettingsData = ref({ slot_interval_minutes: 60 });
const weekDays = ref([]);
const exceptions = ref([]);
const holidays = ref([]);

const persistSettings = async () => {
  const payload = {
    block_outside_working_hours: blockOutsideWorkingHours.value,
    block_lunch_break: blockLunchBreak.value,
    slot_interval_minutes: agendaSettingsData.value.slot_interval_minutes,
    week_days: weekDays.value,
    exceptions: exceptions.value,
    holidays: holidays.value,
  };
  try {
    await AgendaSettingsAPI.update(payload);
  } catch (e) {
    console.error('[AgendaSettings] Falha ao salvar no servidor:', e);
  }
};

const saveChanges = () => {
  saving.value = true;
  persistSettings().then(() => {
    useAlert('Configurações salvas com sucesso!');
  });
  setTimeout(() => {
    saving.value = false;
  }, 700);
};

const loadSettings = async () => {
  try {
    const { data } = await AgendaSettingsAPI.get();
    if (data.block_outside_working_hours !== undefined)
      blockOutsideWorkingHours.value = data.block_outside_working_hours;
    if (data.block_lunch_break !== undefined)
      blockLunchBreak.value = data.block_lunch_break;
    if (data.slot_interval_minutes !== undefined)
      agendaSettingsData.value.slot_interval_minutes = data.slot_interval_minutes;
    if (data.week_days && data.week_days.length) weekDays.value = data.week_days;
    if (data.exceptions && data.exceptions.length) exceptions.value = data.exceptions;
    if (data.holidays && data.holidays.length) holidays.value = data.holidays;
  } catch (e) {
    console.error('[AgendaSettings] Falha ao carregar do servidor:', e);
  }
};

watch(blockOutsideWorkingHours, () => persistSettings());
watch(blockLunchBreak, () => persistSettings());

const addException = () => {
  exceptions.value.unshift({
    title: 'Nova Exceção',
    type: 'Folga / Outros',
    icon: 'i-lucide-sun',
    color: 'yellow',
    start: '',
    end: '',
  });
};

const removeException = (index) => {
  exceptions.value.splice(index, 1);
};

onMounted(() => {
  loadSettings();
  store.dispatch('agendaNotificationRules/fetch');
  store.dispatch('agendaServices/fetch');
  
  const inboxes = store.getters['inboxes/getInboxes'];
  if (!inboxes || inboxes.length === 0) {
    store.dispatch('inboxes/get');
  }
  
  store.dispatch('agents/get');
});
</script>

<template>
  <div
    class="settings-root"
  >
    <PermissionDenied
      v-if="!canViewSettings"
      title="Configurações da agenda restritas"
      message="Você não tem permissão para acessar as configurações da agenda. Fale com o administrador da conta caso precise de acesso."
    />
    <template v-else-if="!tabs.length">
      <PermissionDenied
        title="Sem permissões disponíveis"
        message="Seu perfil pode visualizar as configurações, mas não tem permissão para gerenciar nenhuma das abas. Solicite acesso ao administrador."
      />
    </template>
    <template v-else>
    <!-- ═══════════════ TOP TABS ═══════════════ -->
    <div class="tabs-bar">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        class="tab-btn"
        :class="{ active: activeTab === tab.id }"
        @click="setTab(tab.id, $event)"
      >
        <i class="tab-icon" :class="[tab.icon]" />
        <span>{{ tab.label }}</span>
      </button>
    </div>

    <!-- ═══════════════ HORÁRIOS TAB ═══════════════ -->
    <SettingsTabSchedules
      v-if="activeTab === 'horarios'"
      :week-days="weekDays"
      :exceptions="exceptions"
      :holidays="holidays"
      :block-outside-working-hours="blockOutsideWorkingHours"
      :block-lunch-break="blockLunchBreak"
      :saving="saving"
      @update:blockOutsideWorkingHours="val => blockOutsideWorkingHours = val"
      @update:blockLunchBreak="val => blockLunchBreak = val"
      @save-changes="saveChanges"
      @add-exception="addException"
      @remove-exception="removeException"
    />

    <!-- ═══════════════ NOTIFICAÇÕES AUTOMÁTICAS ═══════════════ -->
    <SettingsTabNotifications v-else-if="activeTab === 'notificacoes'" />

    <!-- ═══════════════ AGENDAMENTO ONLINE ═══════════════ -->
    <SettingsTabOnlineBooking
      v-else-if="activeTab === 'agendamento'"
      :account-id="accountId"
      :current-user="currentUser"
      :is-admin="isAdmin"
      :agents="agents"
      :agenda-settings-data="agendaSettingsData"
      @persist-settings="persistSettings"
    />

    <!-- ═══════════════ SERVIÇOS E TIPOS ═══════════════ -->
    <SettingsTabServices v-else-if="activeTab === 'servicos'" />

    <!-- ═══════════════ OUTRAS ABAS ═══════════════ -->
    <div v-else class="empty-tab">
      <i class="i-lucide-hammer empty-icon" />
      <h3 class="empty-title">Em desenvolvimento</h3>
      <p class="empty-sub">A seção será implementada nas próximas fases.</p>
    </div>

    <!-- Spacer final para garantir o respiro no fundo da página -->
    <div class="page-footer-spacer" />
    </template>
  </div>
</template>

<style>
/* ───────── ROOT ───────── */
.settings-root {
  display: flex;
  flex-direction: column;
  height: 100%;
  width: 100%;
  overflow-y: auto;
  overflow-x: hidden;
  padding: 24px 28px 120px; /* Aumentei para 120px para um respiro maior */
  color: rgb(var(--slate-12));
  box-sizing: border-box;
}

/* ───────── TABS BAR ───────── */
.tabs-bar {
  display: flex;
  align-items: center;
  gap: 2px;
  border-bottom: 1px solid rgb(var(--slate-5));
  padding-bottom: 0;
  margin-bottom: 24px;
  flex-shrink: 0;
  overflow-x: auto;
  flex-wrap: nowrap;
  -webkit-overflow-scrolling: touch;
  scrollbar-width: none; /* Firefox */
}
.tabs-bar::-webkit-scrollbar {
  display: none; /* Safari and Chrome */
}
.tab-btn {
  display: flex;
  align-items: center;
  flex-shrink: 0;
  gap: 6px;
  padding: 8px 14px;
  background: transparent;
  border: none;
  border-bottom: 2px solid transparent;
  cursor: pointer;
  @apply text-sm;
  font-weight: 500;
  color: rgb(var(--slate-10));
  transition:
    color 0.15s,
    border-color 0.15s;
  white-space: nowrap;
  margin-bottom: -1px;
  border-radius: 6px 6px 0 0;
}
.tab-btn:hover {
  color: rgb(var(--slate-12));
  background: rgb(var(--slate-3));
}
.tab-btn.active {
  color: rgb(var(--slate-12));
  border-bottom-color: rgb(var(--blue-9));
}
.tab-icon {
  width: 16px;
  height: 16px;
  flex-shrink: 0;
  font-size: 16px;
}

/* ───────── TAB CONTENT ───────── */
.tab-content {
  display: flex;
  flex-direction: column; /* Mobile first */
  gap: 28px;
  flex: 1;
  min-height: 0;
}
@media (min-width: 1024px) {
  .tab-content {
    flex-direction: row;
  }
}

.col-left {
  flex: 1 1 0;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 24px;
}

.col-right {
  width: 100%; /* Mobile first */
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  gap: 24px;
}
@media (min-width: 1024px) {
  .col-right {
    width: 320px;
  }
}

/* ───────── HEADINGS ───────── */
.section-title {
  font-size: 16px;
  font-weight: 600;
  color: rgb(var(--slate-12));
  margin: 0 0 14px 0;
}
.section-sub-title {
  @apply text-sm;
  color: rgb(var(--slate-9));
  margin: 0;
  line-height: 1.5;
  max-width: 800px;
}

/* ───────── SHARED BUTTONS ───────── */
.add-exception-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: transparent;
  color: rgb(var(--blue-9));
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 8px;
  padding: 6px 14px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s ease;
  white-space: nowrap;
  flex-shrink: 0;
}
.add-exception-btn:hover {
  background: rgba(59, 130, 246, 0.1);
  border-color: rgb(var(--blue-8));
  color: rgb(var(--blue-10));
}

/* ───────── EMPTY TABS ───────── */
.empty-tab {
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 120px 24px;
  text-align: center;
  opacity: 0.8;
}
.empty-icon {
  font-size: 32px;
  color: rgb(var(--slate-8));
  margin-bottom: 16px;
}
.empty-title {
  font-size: 18px;
  font-weight: 600;
  color: rgb(var(--slate-11));
  margin: 0 0 8px 0;
}
.empty-sub {
  @apply text-sm;
  color: rgb(var(--slate-9));
  max-width: 400px;
  line-height: 1.5;
  margin: 0;
}

.page-footer-spacer {
  height: 200px; /* Aumentado para 200px para garantir o respiro visual total */
  width: 100%;
  flex-shrink: 0;
  pointer-events: none;
}

/* ───────── SAVE BUTTON ───────── */
.save-btn {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgb(var(--blue-9));
  color: white;
  padding: 6px 14px;
  border-radius: 5px;
  border: none;
  cursor: pointer;
  @apply text-sm;
  font-weight: 500;
  transition: background 0.15s, transform 0.1s;
  white-space: nowrap;
  flex-shrink: 0;
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.05);
}
.save-btn:hover {
  background: rgb(var(--blue-10));
}
.save-btn:active {
  transform: translateY(0);
}
.save-btn.saving {
  opacity: 0.7;
  cursor: wait;
}

/* ─── Modals globais ─── */
.modal-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.6);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 10000;
  backdrop-filter: blur(3px);
}
.modal-box {
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 16px;
  width: 520px;
  max-width: 95vw;
  max-height: 90vh;
  display: flex;
  flex-direction: column;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.6);
  overflow: hidden;
}
.modal-box-preview {
  width: 420px;
}
.modal-box-ai {
  width: 480px;
}
.modal-box-new {
  width: 560px;
}

.modal-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 16px 20px;
  border-bottom: 1px solid rgb(var(--slate-5));
  flex-shrink: 0;
}
.modal-title {
  @apply text-sm;
  font-weight: 700;
  color: rgb(var(--slate-12));
  display: flex;
  align-items: center;
}
.modal-close,
.modal-close-btn {
  width: 28px;
  height: 28px;
  border-radius: 6px;
  border: none;
  background: transparent;
  color: rgb(var(--slate-9));
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: all 0.15s;
  padding: 0;
}
.modal-close:hover,
.modal-close-btn:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}

.modal-body {
  padding: 20px;
  overflow-y: auto;
  flex: 1;
  display: flex;
  flex-direction: column;
}
.modal-label {
  @apply text-sm;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: rgb(var(--slate-9));
  margin-bottom: 6px;
  display: block;
}
.modal-input {
  width: 100%;
  box-sizing: border-box;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 500;
  padding: 8px 12px;
  outline: none;
  transition:
    border-color 0.15s,
    background 0.15s;
}
.modal-input:focus {
  border-color: rgb(var(--blue-9));
  background: rgb(var(--slate-1));
}
.modal-textarea {
  width: 100%;
  box-sizing: border-box;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-5));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  @apply text-sm;
  font-weight: 500;
  padding: 10px 12px;
  outline: none;
  resize: vertical;
  line-height: 1.6;
  transition:
    border-color 0.15s,
    background 0.15s;
  font-family: inherit;
}
.modal-textarea:focus {
  border-color: rgb(var(--blue-9));
  background: rgb(var(--slate-1));
}

.modal-vars {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}
.var-chip {
  background: rgba(99, 102, 241, 0.1);
  color: #4338ca;
  border: 1px solid rgba(99, 102, 241, 0.25);
  border-radius: 6px;
  padding: 4px 9px;
  @apply text-sm;
  font-weight: 600;
  font-family: monospace;
  cursor: pointer;
  transition: all 0.15s;
}
.var-chip:hover {
  background: rgba(99, 102, 241, 0.18);
  border-color: rgba(99, 102, 241, 0.5);
  color: #3730a3;
}

.modal-footer {
  display: flex;
  align-items: center;
  justify-content: flex-end;
  gap: 10px;
  padding: 14px 20px;
  border-top: 1px solid rgb(var(--slate-5));
  flex-shrink: 0;
}
.modal-btn-cancel {
  background: transparent;
  border: 1px solid rgb(var(--slate-6));
  color: rgb(var(--slate-10));
  border-radius: 8px;
  padding: 7px 16px;
  @apply text-sm;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.15s;
}
.modal-btn-cancel:hover {
  background: rgb(var(--slate-4));
  color: rgb(var(--slate-12));
}
.modal-btn-save {
  display: inline-flex;
  align-items: center;
  gap: 6px;
  background: rgb(var(--blue-9));
  color: white;
  border: none;
  border-radius: 8px;
  padding: 7px 16px;
  @apply text-sm;
  font-weight: 700;
  cursor: pointer;
  transition: background 0.15s;
}
.modal-btn-save:hover {
  background: rgb(var(--blue-10));
}
.modal-btn-save:disabled {
  opacity: 0.4;
  cursor: not-allowed;
}
</style>
