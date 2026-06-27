import { computed } from 'vue';
import { useStore } from 'vuex';
import {
  resolveAgentRoleLabel,
  resolveAgentRoleSlug,
} from '@plugins/patients/frontend/features/patient-record/utils/professionalRoles';

/**
 * Resolve o "Profissional Responsável" de um paciente.
 *
 * IMPORTANTE: Se `patient.responsible_professional_id` não está setado
 * (ex: pacientes importados do Clinicorp — F-08 não traz essa info), o
 * composable retorna `null` e a UI mostra "Não atribuído".
 *
 * Versão anterior fazia fallback pro `currentUser` logado, o que era
 * enganoso — cada user que abrisse a ficha via um nome diferente como se
 * fosse o responsável real. Bug reportado 2026-05-11 (conta Mamedes #31:
 * todos os 2.407 pacientes importados mostravam "Danilo Mamedes" só
 * porque ele estava logado).
 */
export function useResponsibleProfessional(patient) {
  const store = useStore();
  const currentUser = computed(() => store.getters.getCurrentUser);

  const responsibleProfAgent = computed(() => {
    const profId = patient.value?.responsible_professional_id;
    if (!profId) return null;

    const agents = store.getters['agents/getAgents'] || [];
    return agents.find(a => a.id === profId) || null;
  });

  // `hasResponsible` é verdadeiro só quando o paciente TEM um profissional
  // atribuído explicitamente — UI usa pra decidir entre exibir o card normal
  // ou um CTA "Atribuir profissional".
  const hasResponsible = computed(() => responsibleProfAgent.value !== null);

  const responsibleProfName = computed(
    () => responsibleProfAgent.value?.name || 'Não atribuído'
  );

  const responsibleProfAvatar = computed(
    () =>
      responsibleProfAgent.value?.avatar_url ||
      responsibleProfAgent.value?.thumbnail ||
      ''
  );

  // Label do role real (Klivy role > Chatwoot role) pra badge.
  // Mesma lógica que /settings/agents/list — espelha "Atribuir Função".
  const responsibleProfRoleLabel = computed(() =>
    resolveAgentRoleLabel(responsibleProfAgent.value)
  );

  // Slug normalizado pra usar como modifier de classe CSS (cor da badge).
  const responsibleProfRoleSlug = computed(() =>
    resolveAgentRoleSlug(responsibleProfAgent.value)
  );

  return {
    currentUser,
    responsibleProfAgent,
    hasResponsible,
    responsibleProfName,
    responsibleProfAvatar,
    responsibleProfRoleLabel,
    responsibleProfRoleSlug,
  };
}
