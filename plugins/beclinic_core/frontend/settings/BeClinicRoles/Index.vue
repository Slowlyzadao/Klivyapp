<script setup>
import { ref, computed, onMounted } from 'vue';
import { useAlert } from 'dashboard/composables';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import BeClinicRolesAPI from '@plugins/beclinic_core/frontend/api/beclinicRoles';
import BaseSettingsHeader from 'dashboard/routes/dashboard/settings/components/BaseSettingsHeader.vue';
import SettingsLayout from 'dashboard/routes/dashboard/settings/SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import RoleFormModal from './RoleFormModal.vue';
import AssignRoleModal from './AssignRoleModal.vue';

const store = useStore();
const getters = useStoreGetters();

// ─── State ────────────────────────────────────────────────────────────────────
const roles = ref([]);
const agents = ref([]);
const agentRoleMap = ref({}); // { agentId: teamId }
const isLoading = ref(true);
const showRoleModal = ref(false);
const roleModalMode = ref('add');
const selectedRole = ref(null);
const showAssignModal = ref(false);
const selectedAgent = ref(null);
const showDeletePopup = ref(false);
const roleToDelete = ref(null);
const deleteLoading = ref(false);
const searchQuery = ref('');

// ─── Computed ─────────────────────────────────────────────────────────────────
const filteredRoles = computed(() => {
  const q = searchQuery.value.trim().toLowerCase();
  if (!q) return roles.value;
  return roles.value.filter(
    r =>
      r.name.toLowerCase().includes(q) ||
      (r.description || '').toLowerCase().includes(q)
  );
});

const PRESET_NAMES = ['recepcionista', 'especialista', 'gerente', 'sdr'];

const isPreset = role => PRESET_NAMES.includes(role.name.toLowerCase());

const roleLabel = role => {
  const map = {
    dono: 'Dono',
    gerente: 'Gerente',
    especialista: 'Especialista',
  };
  return map[role.beclinic_role] || role.beclinic_role || '—';
};

const roleBadgeClass = role => {
  const map = {
    dono: 'role-badge-dono',
    gerente: 'role-badge-gerente',
    especialista: 'role-badge-especialista',
  };
  return map[role.beclinic_role] || 'role-badge-especialista';
};

const memberCount = role => {
  return Object.values(agentRoleMap.value).filter(teamId => teamId === role.id)
    .length;
};

const agentsForRole = roleId => {
  return agents.value.filter(a => agentRoleMap.value[a.id] === roleId);
};

const confirmText = computed(() => `Deletar ${roleToDelete.value?.name}`);
const rejectText = computed(() => `Cancelar`);
const deleteMessage = computed(() => ` ${roleToDelete.value?.name}?`);

// ─── Load Data ────────────────────────────────────────────────────────────────
const loadData = async () => {
  isLoading.value = true;
  try {
    const [rolesRes] = await Promise.all([
      BeClinicRolesAPI.getAll(),
      store.dispatch('agents/get'),
    ]);

    roles.value = rolesRes.data || [];
    agents.value = getters['agents/getAgents'].value;

    // Build agent → team map by fetching members of each team
    const memberPromises = roles.value.map(async role => {
      try {
        const membersRes = await BeClinicRolesAPI.getMembers(role.id);
        const members = membersRes.data || [];
        members.forEach(m => {
          // last team wins (in case of multiple teams per user)
          agentRoleMap.value[m.id] = role.id;
        });
      } catch {
        // ignore
      }
    });
    await Promise.all(memberPromises);
  } catch {
    useAlert('Erro ao carregar perfis.');
  } finally {
    isLoading.value = false;
  }
};

onMounted(loadData);

// ─── Role CRUD ────────────────────────────────────────────────────────────────
const openAddModal = () => {
  roleModalMode.value = 'add';
  selectedRole.value = null;
  showRoleModal.value = true;
};

const openEditModal = role => {
  roleModalMode.value = 'edit';
  selectedRole.value = role;
  showRoleModal.value = true;
};

const closeRoleModal = () => {
  showRoleModal.value = false;
};

const onRoleSaved = async () => {
  closeRoleModal();
  await loadData();
};

const openDeletePopup = role => {
  roleToDelete.value = role;
  showDeletePopup.value = true;
};

const closeDeletePopup = () => {
  showDeletePopup.value = false;
  roleToDelete.value = null;
};

const confirmDeletion = async () => {
  deleteLoading.value = true;
  try {
    await BeClinicRolesAPI.delete(roleToDelete.value.id);
    useAlert(`Perfil "${roleToDelete.value.name}" removido com sucesso.`);
    closeDeletePopup();
    await loadData();
  } catch {
    useAlert('Erro ao deletar o perfil.');
  } finally {
    deleteLoading.value = false;
  }
};

// ─── Assign ───────────────────────────────────────────────────────────────────
const openAssignModal = agent => {
  selectedAgent.value = agent;
  showAssignModal.value = true;
};

const closeAssignModal = () => {
  showAssignModal.value = false;
  selectedAgent.value = null;
};

const onRoleAssigned = async ({ agent, teamId }) => {
  try {
    // Remove from old team
    const oldTeamId = agentRoleMap.value[agent.id];
    if (oldTeamId && oldTeamId !== teamId) {
      await BeClinicRolesAPI.removeMember(oldTeamId, agent.id);
    }
    // Add to new team
    if (teamId) {
      await BeClinicRolesAPI.addMember(teamId, agent.id);
    }
    agentRoleMap.value[agent.id] = teamId;
    useAlert(`Perfil atribuído com sucesso.`);
    closeAssignModal();
    await loadData();
  } catch {
    useAlert('Erro ao atribuir perfil.');
  }
};

const agentRoleName = agent => {
  const teamId = agentRoleMap.value[agent.id];
  if (!teamId) return 'Sem perfil';
  const role = roles.value.find(r => r.id === teamId);
  return role ? role.name : 'Sem perfil';
};
</script>

<template>
  <SettingsLayout
    :is-loading="isLoading"
    loading-message="Carregando perfis..."
    :no-records-found="!isLoading && !roles.length"
    no-records-message="Nenhum perfil encontrado. Crie o primeiro perfil para sua clínica."
  >
    <!-- Header -->
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        title="Perfis & Permissões"
        description="Gerencie os perfis de acesso da sua clínica. Cada agente pode ter um perfil que define o que ele pode ver e fazer."
        link-text=""
        search-placeholder="Buscar perfil por nome..."
        feature-name="beclinic_roles"
      >
        <template v-if="roles.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ roles.length }} perfil{{ roles.length !== 1 ? 's' : '' }}
          </span>
        </template>
        <template #actions>
          <Button label="+ Novo Perfil" size="sm" @click="openAddModal" />
        </template>
      </BaseSettingsHeader>
    </template>

    <!-- Body -->
    <template #body>
      <div class="roles-page">
        <!-- Roles Grid -->
        <section class="roles-section">
          <div class="section-title-row">
            <h3 class="section-label">Perfis da Clínica</h3>
            <span class="section-sub">Times que atuam como perfis de acesso</span>
          </div>
          <div class="roles-grid">
            <div v-for="role in filteredRoles" :key="role.id" class="role-card">
              <!-- Card Header -->
              <div class="role-card-header">
                <div class="role-card-title-group">
                  <div class="role-name-row">
                    <span class="role-name">{{ role.name }}</span>
                    <span v-if="isPreset(role)"
class="badge badge-preset"
                      >Padrão</span>
                    <span v-else class="badge badge-custom">Customizado</span>
                  </div>
                  <div class="role-base-badge" :class="[roleBadgeClass(role)]">
                    {{ roleLabel(role) }}
                  </div>
                </div>
                <div class="role-card-actions">
                  <Button
                    v-tooltip.top="'Editar perfil'"
                    icon="i-woot-edit-pen"
                    slate
                    sm
                    @click="openEditModal(role)"
                  />
                  <Button
                    v-tooltip.top="'Deletar perfil'"
                    icon="i-woot-bin"
                    slate
                    sm
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    @click="openDeletePopup(role)"
                  />
                </div>
              </div>

              <!-- Permissions Summary -->
              <div class="role-permissions-summary">
                <div
                  v-for="(moduleKey, idx) in [
                    'patients',
                    'agenda',
                    'financial',
                    'chat',
                    'settings',
                  ]"
                  :key="idx"
                  class="perm-module"
                >
                  <span class="perm-module-name">{{
                    {
                      patients: 'Pacientes',
                      agenda: 'Agenda',
                      financial: 'Financeiro',
                      chat: 'Chat',
                      settings: 'Settings',
                    }[moduleKey]
                  }}</span>
                  <span
                    class="perm-dot"
                    :class="
                      role.permissions && role.permissions[moduleKey]
                        ? 'perm-dot-on'
                        : 'perm-dot-off'
                    "
                  />
                </div>
              </div>

              <!-- Members -->
              <div class="role-members">
                <span class="members-count">{{ memberCount(role) }} membro{{
                    memberCount(role) !== 1 ? 's' : ''
                  }}</span>
                <div v-if="agentsForRole(role.id).length" class="avatars-row">
                  <div
                    v-for="agent in agentsForRole(role.id).slice(0, 5)"
                    :key="agent.id"
                    class="mini-avatar"
                    :title="agent.name"
                  >
                    <img
                      v-if="agent.thumbnail"
                      :src="agent.thumbnail"
                      :alt="agent.name"
                      class="mini-avatar-img"
                    />
                    <span v-else class="mini-avatar-initial">{{
                      agent.name?.[0]?.toUpperCase()
                    }}</span>
                  </div>
                  <span
                    v-if="agentsForRole(role.id).length > 5"
                    class="avatars-more"
                  >
                    +{{ agentsForRole(role.id).length - 5 }}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </section>

        <!-- Agents & Role Assignment -->
        <section class="agents-section">
          <div class="section-title-row">
            <h3 class="section-label">Agentes & Perfis Atribuídos</h3>
            <span class="section-sub">Atribua um perfil a cada membro da clínica</span>
          </div>
          <div class="agents-table">
            <div class="agents-table-head">
              <span>Agente</span>
              <span>Perfil Atual</span>
              <span class="text-right">Ação</span>
            </div>
            <div
              v-for="agent in agents"
              :key="agent.id"
              class="agents-table-row"
            >
              <div class="agent-info">
                <div class="agent-avatar">
                  <img
                    v-if="agent.thumbnail"
                    :src="agent.thumbnail"
                    :alt="agent.name"
                  />
                  <span v-else>{{ agent.name?.[0]?.toUpperCase() }}</span>
                </div>
                <div class="agent-details">
                  <span class="agent-name">{{ agent.name }}</span>
                  <span class="agent-email">{{ agent.email }}</span>
                </div>
              </div>
              <div class="agent-role-cell">
                <span
                  class="agent-current-role"
                  :class="
                    agentRoleMap[agent.id] ? 'role-assigned' : 'role-unassigned'
                  "
                >
                  {{ agentRoleName(agent) }}
                </span>
              </div>
              <div class="agent-actions">
                <Button
                  label="Atribuir Perfil"
                  size="sm"
                  slate
                  @click="openAssignModal(agent)"
                />
              </div>
            </div>
          </div>
        </section>
      </div>
    </template>
  </SettingsLayout>

  <!-- Role Form Modal -->
  <woot-modal v-model:show="showRoleModal" :on-close="closeRoleModal">
    <RoleFormModal
      v-if="showRoleModal"
      :mode="roleModalMode"
      :role="selectedRole"
      @close="closeRoleModal"
      @saved="onRoleSaved"
    />
  </woot-modal>

  <!-- Assign Role Modal -->
  <woot-modal v-model:show="showAssignModal" :on-close="closeAssignModal">
    <AssignRoleModal
      v-if="showAssignModal"
      :agent="selectedAgent"
      :roles="roles"
      :current-team-id="agentRoleMap[selectedAgent?.id]"
      @close="closeAssignModal"
      @assigned="onRoleAssigned"
    />
  </woot-modal>

  <!-- Delete Confirm -->
  <woot-delete-modal
    v-model:show="showDeletePopup"
    :on-close="closeDeletePopup"
    :on-confirm="confirmDeletion"
    title="Deletar Perfil"
    message="Esta ação é irreversível. Todos os agentes com este perfil ficarão sem perfil atribuído. Deseja deletar o perfil"
    :message-value="deleteMessage"
    :confirm-text="confirmText"
    :reject-text="rejectText"
  />
</template>

<style scoped>
.roles-page {
  display: flex;
  flex-direction: column;
  gap: 2.5rem;
  padding: 0.5rem 0;
}

/* Section headers */
.section-title-row {
  display: flex;
  align-items: baseline;
  gap: 0.75rem;
  margin-bottom: 1rem;
}
.section-label {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-woot);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin: 0;
}
.section-sub {
  font-size: 0.8125rem;
  color: var(--color-body);
  opacity: 0.7;
}

/* Roles grid */
.roles-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: 1rem;
}

.role-card {
  background: var(--color-bg-1);
  border: 1px solid var(--color-border-light);
  border-radius: 12px;
  padding: 1.125rem 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.875rem;
  transition:
    box-shadow 0.18s ease,
    border-color 0.18s ease;
}
.role-card:hover {
  border-color: var(--color-woot-400);
  box-shadow: 0 4px 16px rgba(99, 102, 241, 0.08);
}

.role-card-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 0.5rem;
}
.role-card-title-group {
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
  flex: 1;
}
.role-name-row {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  flex-wrap: wrap;
}
.role-name {
  font-size: 0.9375rem;
  font-weight: 600;
  color: var(--color-heading);
  text-transform: capitalize;
}
.role-card-actions {
  display: flex;
  gap: 0.25rem;
  flex-shrink: 0;
}

/* Badges */
.badge {
  font-size: 0.6875rem;
  font-weight: 600;
  padding: 0.15rem 0.5rem;
  border-radius: 99px;
  letter-spacing: 0.03em;
  text-transform: uppercase;
}
.badge-preset {
  background: #ede9fe;
  color: #5b21b6;
}
.badge-custom {
  background: #d1fae5;
  color: #065f46;
}

.role-base-badge {
  font-size: 0.75rem;
  font-weight: 500;
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
  width: fit-content;
}
.role-badge-dono {
  background: #fef9c3;
  color: #713f12;
}
.role-badge-gerente {
  background: #dbeafe;
  color: #1e3a8a;
}
.role-badge-especialista {
  background: #e0f2fe;
  color: #0c4a6e;
}

/* Permissions summary */
.role-permissions-summary {
  display: flex;
  gap: 0.625rem;
  flex-wrap: wrap;
}
.perm-module {
  display: flex;
  align-items: center;
  gap: 0.3rem;
  font-size: 0.75rem;
  color: var(--color-body);
}
.perm-module-name {
  opacity: 0.8;
}
.perm-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  flex-shrink: 0;
}
.perm-dot-on {
  background: #22c55e;
}
.perm-dot-off {
  background: #e5e7eb;
}

/* Members */
.role-members {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding-top: 0.625rem;
  border-top: 1px solid var(--color-border-light);
}
.members-count {
  font-size: 0.8125rem;
  color: var(--color-body);
  opacity: 0.8;
  flex-shrink: 0;
}
.avatars-row {
  display: flex;
  align-items: center;
  gap: -4px;
}
.mini-avatar {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: #818cf8;
  border: 2px solid var(--color-bg-1);
  display: flex;
  align-items: center;
  justify-content: center;
  margin-left: -4px;
  overflow: hidden;
  flex-shrink: 0;
}
.mini-avatar:first-child {
  margin-left: 0;
}
.mini-avatar-img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.mini-avatar-initial {
  font-size: 0.625rem;
  font-weight: 700;
  color: #fff;
}
.avatars-more {
  font-size: 0.75rem;
  color: var(--color-body);
  margin-left: 4px;
}

/* Agents Table */
.agents-section {
  margin-top: 0.5rem;
}
.agents-table {
  border: 1px solid var(--color-border-light);
  border-radius: 12px;
  overflow: hidden;
}
.agents-table-head {
  display: grid;
  grid-template-columns: 1fr 1fr 140px;
  gap: 1rem;
  padding: 0.75rem 1.25rem;
  background: var(--color-bg-2);
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--color-body);
  text-transform: uppercase;
  letter-spacing: 0.05em;
  border-bottom: 1px solid var(--color-border-light);
}
.agents-table-row {
  display: grid;
  grid-template-columns: 1fr 1fr 140px;
  gap: 1rem;
  align-items: center;
  padding: 0.875rem 1.25rem;
  border-bottom: 1px solid var(--color-border-light);
  transition: background 0.12s ease;
}
.agents-table-row:last-child {
  border-bottom: none;
}
.agents-table-row:hover {
  background: var(--color-bg-2);
}

.agent-info {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}
.agent-avatar {
  width: 36px;
  height: 36px;
  border-radius: 50%;
  background: #818cf8;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}
.agent-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.agent-avatar span {
  font-size: 0.875rem;
  font-weight: 700;
  color: #fff;
}
.agent-details {
  display: flex;
  flex-direction: column;
  gap: 0.125rem;
}
.agent-name {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-heading);
  text-transform: capitalize;
}
.agent-email {
  font-size: 0.75rem;
  color: var(--color-body);
  opacity: 0.8;
}

.agent-role-cell {
  display: flex;
  align-items: center;
}
.agent-current-role {
  font-size: 0.8125rem;
  font-weight: 500;
  padding: 0.2rem 0.625rem;
  border-radius: 6px;
  text-transform: capitalize;
}
.role-assigned {
  background: #ede9fe;
  color: #5b21b6;
}
.role-unassigned {
  background: var(--color-bg-2);
  color: var(--color-body);
  opacity: 0.7;
}

.agent-actions {
  display: flex;
  justify-content: flex-end;
}
</style>
