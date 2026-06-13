<script setup>
/**
 * Modal para trocar o Profissional Responsável do paciente.
 *
 * Lista TODOS os agents da conta (não filtra por `confirmed` — agents
 * pendentes de verificação ainda existem e podem ser atribuídos como
 * responsáveis). Cada opção mostra avatar + nome + badge de role.
 *
 * Salva via PATCH /api/v1/accounts/:id/patients/:patient_id enviando
 * { patient: { responsible_professional_id: N } }.
 *
 * Inclui opção "Sem profissional atribuído" (null) pra permitir desatribuir.
 */
import { ref, computed, watch, onMounted } from 'vue';
import { useStore } from 'vuex';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import BeclinicButton from '@plugins/beclinic_core/frontend/components/Button.vue';
import PatientsAPI from '@plugins/patients/frontend/api/patients';
import {
  resolveAgentRoleLabel,
  resolveAgentRoleSlug,
} from '@plugins/patients/frontend/features/patient-record/utils/professionalRoles';

const props = defineProps({
  show: { type: Boolean, default: false },
  patient: { type: Object, required: true },
});

const emit = defineEmits(['close', 'updated']);

const store = useStore();
const agents = computed(() => store.getters['agents/getAgents'] || []);

// Garante que a lista de agents foi carregada. Em algumas rotas o app não
// fetcha esse store automático, então é defensivo dispatchar aqui.
onMounted(() => {
  if (agents.value.length === 0) {
    try {
      store.dispatch('agents/get');
    } catch (_e) {
      // sem store action disponível → ignora silenciosamente; UI mostra empty.
    }
  }
});

const searchTerm = ref('');

const filteredAgents = computed(() => {
  const term = searchTerm.value.trim().toLowerCase();
  if (!term) return agents.value;
  return agents.value.filter(
    a =>
      a.name?.toLowerCase().includes(term) ||
      a.email?.toLowerCase().includes(term) ||
      a.role?.toLowerCase().includes(term)
  );
});

const selectedId = ref(null);
const saving = ref(false);
const errorMsg = ref('');

// Sincroniza o select com o estado atual do paciente quando o modal abre.
watch(
  () => [props.show, props.patient?.responsible_professional_id],
  ([show, currentId]) => {
    if (show) {
      selectedId.value = currentId || null;
      errorMsg.value = '';
      searchTerm.value = '';
    }
  },
  { immediate: true }
);

const currentName = computed(() => {
  const id = props.patient?.responsible_professional_id;
  if (!id) return 'Não atribuído';
  const a = agents.value.find(ag => ag.id === id);
  return a?.name || `Usuário #${id}`;
});

const hasChanged = computed(
  () => selectedId.value !== (props.patient?.responsible_professional_id || null)
);

function select(id) {
  selectedId.value = id;
}

async function save() {
  if (!hasChanged.value) {
    emit('close');
    return;
  }
  saving.value = true;
  errorMsg.value = '';
  try {
    const { data } = await PatientsAPI.update(props.patient.id, {
      responsible_professional_id: selectedId.value,
    });
    emit('updated', data);
    emit('close');
  } catch (e) {
    errorMsg.value =
      e?.response?.data?.message ||
      e?.message ||
      'Erro ao salvar. Tente novamente em alguns instantes.';
  } finally {
    saving.value = false;
  }
}
</script>

<template>
  <Teleport to="body">
    <div v-if="show" class="chr-modal-overlay" @click.self="$emit('close')">
      <div class="chr-modal">
        <header class="chr-modal__header">
          <div class="chr-modal__title-group">
            <div class="chr-modal__icon">
              <i class="i-lucide-user-cog w-5 h-5" />
            </div>
            <div>
              <h3 class="chr-modal__title">Trocar Profissional Responsável</h3>
              <p class="chr-modal__subtitle">
                Atual: <strong>{{ currentName }}</strong>
              </p>
            </div>
          </div>
          <button
            type="button"
            class="chr-modal__close"
            aria-label="Fechar"
            @click="$emit('close')"
          >
            <i class="i-lucide-x w-4 h-4" />
          </button>
        </header>

        <div class="chr-modal__body">
          <div class="chr-modal__search">
            <i class="i-lucide-search w-4 h-4 chr-modal__search-icon" />
            <input
              v-model="searchTerm"
              type="text"
              class="chr-modal__search-input"
              placeholder="Buscar profissional..."
            />
          </div>

          <div class="chr-modal__list" role="radiogroup">
            <!-- Opção especial: sem profissional -->
            <button
              type="button"
              class="chr-modal__item"
              :class="{ 'chr-modal__item--selected': selectedId === null }"
              role="radio"
              :aria-checked="selectedId === null"
              @click="select(null)"
            >
              <div class="chr-modal__item-avatar chr-modal__item-avatar--empty">
                <i class="i-lucide-user-x w-5 h-5" />
              </div>
              <div class="chr-modal__item-info">
                <span class="chr-modal__item-name">Sem profissional atribuído</span>
                <span class="chr-modal__item-hint">Desvincula o responsável</span>
              </div>
              <i
                v-if="selectedId === null"
                class="i-lucide-check chr-modal__item-check"
              />
            </button>

            <!-- Lista de agents -->
            <button
              v-for="agent in filteredAgents"
              :key="agent.id"
              type="button"
              class="chr-modal__item"
              :class="{ 'chr-modal__item--selected': selectedId === agent.id }"
              role="radio"
              :aria-checked="selectedId === agent.id"
              @click="select(agent.id)"
            >
              <Avatar
                :src="agent.avatar_url || agent.thumbnail"
                :name="agent.name"
                :size="40"
                rounded-full
                class="chr-modal__item-avatar"
              />
              <div class="chr-modal__item-info">
                <span class="chr-modal__item-name">{{ agent.name }}</span>
                <span
                  v-if="resolveAgentRoleLabel(agent)"
                  class="chr-modal__item-badge"
                  :class="`chr-modal__item-badge--${resolveAgentRoleSlug(agent)}`"
                >
                  <i class="i-lucide-shield-check w-3 h-3" />
                  {{ resolveAgentRoleLabel(agent) }}
                </span>
              </div>
              <i
                v-if="selectedId === agent.id"
                class="i-lucide-check chr-modal__item-check"
              />
            </button>

            <div v-if="filteredAgents.length === 0" class="chr-modal__empty">
              <i class="i-lucide-search-x w-5 h-5" />
              <span>
                {{
                  searchTerm
                    ? `Nenhum profissional encontrado para "${searchTerm}".`
                    : 'Nenhum profissional cadastrado na conta.'
                }}
              </span>
            </div>
          </div>

          <div class="chr-modal__hint">
            <i class="i-lucide-info w-3.5 h-3.5 flex-shrink-0 mt-0.5" />
            <p>
              O profissional responsável é quem cuida regularmente do paciente.
              Esta troca <strong>não afeta</strong> agendamentos passados ou
              tratamentos em andamento — apenas o campo "Responsável" da ficha.
            </p>
          </div>

          <div v-if="errorMsg" class="chr-modal__error">{{ errorMsg }}</div>
        </div>

        <footer class="chr-modal__footer">
          <BeclinicButton
            variant="ghost"
            color="slate"
            label="Cancelar"
            size="sm"
            @click="$emit('close')"
          />
          <BeclinicButton
            variant="solid"
            color="teal"
            :label="saving ? 'Salvando...' : 'Salvar alteração'"
            size="sm"
            :disabled="saving || !hasChanged"
            @click="save"
          />
        </footer>
      </div>
    </div>
  </Teleport>
</template>

<style scoped lang="scss">
.chr-modal-overlay {
  position: fixed;
  inset: 0;
  z-index: 1000;
  background: rgba(0, 0, 0, 0.45);
  backdrop-filter: blur(2px);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 20px;
}
.chr-modal {
  width: 100%;
  max-width: 520px;
  max-height: 90vh;
  background: rgb(var(--slate-1));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 14px;
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.3);
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.chr-modal__header {
  display: flex;
  justify-content: space-between;
  align-items: flex-start;
  gap: 12px;
  padding: 18px 20px 14px;
  border-bottom: 1px solid rgb(var(--slate-4));
  flex-shrink: 0;
}
.chr-modal__title-group {
  display: flex;
  align-items: center;
  gap: 12px;
}
.chr-modal__icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  background: rgba(59, 130, 246, 0.12);
  color: #2563eb;
  border-radius: 8px;
  flex-shrink: 0;
}
.chr-modal__title {
  margin: 0;
  font-size: 15px;
  font-weight: 600;
  color: rgb(var(--slate-12));
}
.chr-modal__subtitle {
  margin: 2px 0 0;
  font-size: 12px;
  color: rgb(var(--slate-11));
  strong {
    color: rgb(var(--slate-12));
    font-weight: 600;
  }
}
.chr-modal__close {
  background: transparent;
  border: 0;
  padding: 4px;
  border-radius: 6px;
  color: rgb(var(--slate-9));
  cursor: pointer;
  &:hover {
    background: rgb(var(--slate-3));
    color: rgb(var(--slate-12));
  }
}
.chr-modal__body {
  padding: 16px 20px;
  display: flex;
  flex-direction: column;
  gap: 12px;
  overflow: hidden;
}

/* Busca */
.chr-modal__search {
  position: relative;
  flex-shrink: 0;
}
.chr-modal__search-icon {
  position: absolute;
  left: 10px;
  top: 50%;
  transform: translateY(-50%);
  color: rgb(var(--slate-9));
  pointer-events: none;
}
.chr-modal__search-input {
  width: 100%;
  padding: 8px 12px 8px 32px;
  font-size: 13px;
  background: rgb(var(--slate-2));
  border: 1px solid rgb(var(--slate-4));
  border-radius: 8px;
  color: rgb(var(--slate-12));
  &:focus {
    outline: none;
    border-color: var(--w-500, #1f93ff);
    box-shadow: 0 0 0 3px rgba(31, 147, 255, 0.12);
  }
  &::placeholder { color: rgb(var(--slate-9)); }
}

/* Lista de agents — scrollável */
.chr-modal__list {
  display: flex;
  flex-direction: column;
  gap: 4px;
  max-height: 360px;
  overflow-y: auto;
  padding: 2px;
  margin: -2px;
}
.chr-modal__item {
  display: flex;
  align-items: center;
  gap: 12px;
  padding: 10px 12px;
  background: transparent;
  border: 1px solid transparent;
  border-radius: 10px;
  cursor: pointer;
  text-align: left;
  transition: background 0.12s ease, border-color 0.12s ease;
  &:hover {
    background: rgb(var(--slate-2));
    border-color: rgb(var(--slate-4));
  }
}
.chr-modal__item--selected {
  background: rgba(31, 147, 255, 0.08) !important;
  border-color: var(--w-500, #1f93ff) !important;
}
:root.dark .chr-modal__item--selected {
  background: rgba(31, 147, 255, 0.12) !important;
}
.chr-modal__item-avatar {
  flex-shrink: 0;
}
.chr-modal__item-avatar--empty {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 40px;
  height: 40px;
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-9));
  border-radius: 50%;
}
.chr-modal__item-info {
  flex: 1;
  min-width: 0;
  display: flex;
  flex-direction: column;
  gap: 2px;
}
.chr-modal__item-name {
  font-size: 13.5px;
  font-weight: 500;
  color: rgb(var(--slate-12));
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.chr-modal__item-hint {
  font-size: 11.5px;
  color: rgb(var(--slate-9));
}
.chr-modal__item-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 10px;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  align-self: flex-start;
  /* Default — fallback caso role não bata em nenhuma variant abaixo */
  background: rgb(var(--slate-3));
  color: rgb(var(--slate-11));

  /* Cores por role real (Klivy + Chatwoot bypass) — espelham a lógica de
     `resolveAgentRoleSlug`. Tom semântico: admin violet (alto poder),
     gerente teal (gestão), especialista azul (clínico), recepcionista amber
     (operacional), proprietário rose (raríssimo). */
  &--administrador {
    background: rgba(168, 85, 247, 0.14);
    color: #7c3aed;
  }
  &--gerente {
    background: rgba(20, 184, 166, 0.14);
    color: #0d9488;
  }
  &--especialista {
    background: rgba(59, 130, 246, 0.12);
    color: #1d4ed8;
  }
  &--recepcionista {
    background: rgba(245, 158, 11, 0.14);
    color: #b45309;
  }
  &--proprietario,
  &--super_admin {
    background: rgba(244, 63, 94, 0.14);
    color: #be123c;
  }
  &--profissional {
    background: rgba(34, 197, 94, 0.12);
    color: #16a34a;
  }
}
:root.dark .chr-modal__item-badge {
  background: rgba(255, 255, 255, 0.04);
  color: rgb(var(--slate-11));
  &--administrador {
    background: rgba(168, 85, 247, 0.18);
    color: #c4b5fd;
  }
  &--gerente {
    background: rgba(20, 184, 166, 0.18);
    color: #5eead4;
  }
  &--especialista {
    background: rgba(59, 130, 246, 0.18);
    color: #93c5fd;
  }
  &--recepcionista {
    background: rgba(245, 158, 11, 0.18);
    color: #fcd34d;
  }
  &--proprietario,
  &--super_admin {
    background: rgba(244, 63, 94, 0.18);
    color: #fda4af;
  }
  &--profissional {
    background: rgba(34, 197, 94, 0.18);
    color: #86efac;
  }
}
.chr-modal__item-check {
  flex-shrink: 0;
  width: 18px;
  height: 18px;
  color: var(--w-500, #1f93ff);
}
.chr-modal__empty {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 20px 12px;
  justify-content: center;
  color: rgb(var(--slate-9));
  font-size: 13px;
}

.chr-modal__hint {
  display: flex;
  gap: 8px;
  padding: 10px 12px;
  background: rgba(59, 130, 246, 0.08);
  border-left: 3px solid #3b82f6;
  border-radius: 6px;
  font-size: 12px;
  color: rgb(var(--slate-11));
  line-height: 1.5;
  flex-shrink: 0;
  i {
    color: #3b82f6;
  }
  p {
    margin: 0;
  }
  strong {
    color: rgb(var(--slate-12));
    font-weight: 600;
  }
}
.chr-modal__error {
  padding: 10px 12px;
  background: rgba(220, 38, 38, 0.08);
  border-left: 3px solid #dc2626;
  border-radius: 6px;
  font-size: 12.5px;
  color: #b91c1c;
  flex-shrink: 0;
}
.chr-modal__footer {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  padding: 14px 20px 18px;
  border-top: 1px solid rgb(var(--slate-4));
  flex-shrink: 0;
}
</style>
