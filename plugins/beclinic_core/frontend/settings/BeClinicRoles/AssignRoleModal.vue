<script setup>
import { ref, computed } from 'vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  agent: { type: Object, required: true },
  roles: { type: Array, default: () => [] },
  currentTeamId: { type: Number, default: null },
});

const emit = defineEmits(['close', 'assigned']);

const selectedTeamId = ref(props.currentTeamId || null);

const ROLE_LABELS = {
  dono: 'Dono',
  gerente: 'Gerente',
  especialista: 'Especialista',
};

const ROLE_BADGE_CLASS = {
  dono: 'badge-dono',
  gerente: 'badge-gerente',
  especialista: 'badge-especialista',
};

const PRESET_NAMES = ['recepcionista', 'especialista', 'gerente', 'sdr'];
const isPreset = role => PRESET_NAMES.includes(role.name?.toLowerCase());

const currentRole = computed(() =>
  props.roles.find(r => r.id === props.currentTeamId)
);

const confirm = () => {
  emit('assigned', { agent: props.agent, teamId: selectedTeamId.value });
};
</script>

<template>
  <div class="assign-modal">
    <!-- Header -->
    <div class="assign-header">
      <div class="assign-agent-info">
        <div class="assign-avatar">
          <img
            v-if="agent.thumbnail"
            :src="agent.thumbnail"
            :alt="agent.name"
          />
          <span v-else>{{ agent.name?.[0]?.toUpperCase() }}</span>
        </div>
        <div class="assign-agent-details">
          <span class="assign-agent-name">{{ agent.name }}</span>
          <span class="assign-agent-email">{{ agent.email }}</span>
        </div>
      </div>
      <div v-if="currentRole" class="assign-current">
        <span class="assign-current-label">Perfil atual:</span>
        <span class="assign-current-value">{{ currentRole.name }}</span>
      </div>
    </div>

    <!-- Role list -->
    <div class="assign-body">
      <p class="assign-instructions">
        Selecione o perfil que deseja atribuir a este agente:
      </p>
      <div class="roles-list">
        <div
          v-for="role in roles"
          :key="role.id"
          class="role-option"
          :class="{ selected: selectedTeamId === role.id }"
          @click="selectedTeamId = role.id"
        >
          <div class="role-option-left">
            <div class="role-option-radio">
              <div v-if="selectedTeamId === role.id" class="radio-dot" />
            </div>
            <div class="role-option-info">
              <span class="role-option-name">{{ role.name }}</span>
              <div class="role-option-meta">
                <span
                  class="role-meta-badge"
                  :class="
                    ROLE_BADGE_CLASS[role.beclinic_role] || 'badge-especialista'
                  "
                >
                  {{ ROLE_LABELS[role.beclinic_role] || role.beclinic_role }}
                </span>
                <span v-if="isPreset(role)" class="preset-tag">Padrão</span>
              </div>
            </div>
          </div>
          <div class="role-option-perms">
            <span
              v-for="mod in ['patients', 'agenda', 'financial', 'chat']"
              :key="mod"
              class="perm-dot-sm"
              :class="role.permissions?.[mod] ? 'dot-on' : 'dot-off'"
              :title="
                {
                  patients: 'Pacientes',
                  agenda: 'Agenda',
                  financial: 'Financeiro',
                  chat: 'Chat',
                }[mod]
              "
            />
          </div>
        </div>

        <!-- Option: remove from all roles -->
        <div
          class="role-option role-option-none"
          :class="{ selected: selectedTeamId === null }"
          @click="selectedTeamId = null"
        >
          <div class="role-option-left">
            <div class="role-option-radio">
              <div v-if="selectedTeamId === null" class="radio-dot" />
            </div>
            <div class="role-option-info">
              <span class="role-option-name">Sem perfil</span>
              <span class="role-option-none-desc">Remove o agente de todos os perfis</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- Footer -->
    <div class="assign-footer">
      <Button label="Cancelar" slate @click="emit('close')" />
      <Button label="Confirmar" @click="confirm" />
    </div>
  </div>
</template>

<style scoped>
.assign-modal {
  padding: 1.5rem;
  display: flex;
  flex-direction: column;
  gap: 1.25rem;
  min-width: 460px;
  max-width: 540px;
  max-height: 80vh;
  overflow-y: auto;
}

/* Header */
.assign-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 1rem;
}
.assign-agent-info {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}
.assign-avatar {
  width: 40px;
  height: 40px;
  border-radius: 50%;
  background: #818cf8;
  display: flex;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  flex-shrink: 0;
}
.assign-avatar img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}
.assign-avatar span {
  font-size: 1rem;
  font-weight: 700;
  color: #fff;
}
.assign-agent-details {
  display: flex;
  flex-direction: column;
  gap: 0.125rem;
}
.assign-agent-name {
  font-size: 0.9375rem;
  font-weight: 600;
  color: var(--color-heading);
  text-transform: capitalize;
}
.assign-agent-email {
  font-size: 0.75rem;
  color: var(--color-body);
  opacity: 0.8;
}
.assign-current {
  display: flex;
  align-items: center;
  gap: 0.375rem;
}
.assign-current-label {
  font-size: 0.75rem;
  color: var(--color-body);
}
.assign-current-value {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--color-woot);
  background: #ede9fe;
  padding: 0.15rem 0.5rem;
  border-radius: 6px;
  text-transform: capitalize;
}

/* Body */
.assign-body {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
}
.assign-instructions {
  font-size: 0.8125rem;
  color: var(--color-body);
  margin: 0;
}
.roles-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}
.role-option {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding: 0.75rem 1rem;
  border: 2px solid var(--color-border-light);
  border-radius: 10px;
  cursor: pointer;
  transition: all 0.15s ease;
  background: var(--color-bg-1);
}
.role-option:hover {
  border-color: var(--color-woot-400);
  background: #f5f3ff;
}
.role-option.selected {
  border-color: var(--color-woot);
  background: #ede9fe;
}

.role-option-left {
  display: flex;
  align-items: center;
  gap: 0.75rem;
}
.role-option-radio {
  width: 18px;
  height: 18px;
  border-radius: 50%;
  border: 2px solid var(--color-border-light);
  display: flex;
  align-items: center;
  justify-content: center;
  flex-shrink: 0;
  transition: border-color 0.15s;
}
.role-option.selected .role-option-radio {
  border-color: var(--color-woot);
}
.radio-dot {
  width: 8px;
  height: 8px;
  border-radius: 50%;
  background: var(--color-woot);
}
.role-option-info {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
}
.role-option-name {
  font-size: 0.875rem;
  font-weight: 600;
  color: var(--color-heading);
  text-transform: capitalize;
}
.role-option-meta {
  display: flex;
  align-items: center;
  gap: 0.375rem;
}
.role-meta-badge {
  font-size: 0.65rem;
  font-weight: 600;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}
.badge-dono {
  background: #fef9c3;
  color: #713f12;
}
.badge-gerente {
  background: #dbeafe;
  color: #1e3a8a;
}
.badge-especialista {
  background: #e0f2fe;
  color: #0c4a6e;
}
.preset-tag {
  font-size: 0.65rem;
  font-weight: 500;
  color: #5b21b6;
  background: transparent;
  border: 1px solid #c4b5fd;
  padding: 0.1rem 0.4rem;
  border-radius: 4px;
}
.role-option-perms {
  display: flex;
  gap: 4px;
  align-items: center;
}
.perm-dot-sm {
  width: 7px;
  height: 7px;
  border-radius: 50%;
}
.dot-on {
  background: #22c55e;
}
.dot-off {
  background: #e5e7eb;
}

.role-option-none-desc {
  font-size: 0.75rem;
  color: var(--color-body);
  opacity: 0.7;
}

/* Footer */
.assign-footer {
  display: flex;
  justify-content: flex-end;
  gap: 0.75rem;
  padding-top: 0.75rem;
  border-top: 1px solid var(--color-border-light);
}
</style>
