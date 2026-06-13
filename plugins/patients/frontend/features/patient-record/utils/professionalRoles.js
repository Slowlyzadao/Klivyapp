export const PROF_ROLE_LABELS = {
  administrator: 'Administrador',
  agent: 'Profissional',
  super_admin: 'Super Admin',
  owner: 'Proprietário',
};

export const formatProfRole = role =>
  PROF_ROLE_LABELS[role?.toLowerCase()] || role;

/**
 * Retorna o label do role real do agent — espelha lógica do
 * `dashboard/settings/agents/Index.vue` (admin bypass + klivy_role.name).
 *
 * Hierarquia:
 *   1. Se for `administrator` (Chatwoot role) → "Administrador" (bypass total,
 *      ignora klivy_role mesmo se setado por legado).
 *   2. Se tem `klivy_role.name` → usa o nome do role Klivy ("Especialista",
 *      "Gerente", "Recepcionista", etc).
 *   3. Fallback: "Profissional" (agent Chatwoot sem klivy_role).
 */
export const resolveAgentRoleLabel = (agent) => {
  if (!agent) return '';
  if (agent.role === 'administrator') return 'Administrador';
  if (agent.klivy_role?.name) return agent.klivy_role.name;
  if (agent.role === 'agent') return 'Profissional';
  return '';
};

/**
 * Slug do role pra usar como modifier de classe CSS (cor da badge).
 * Normaliza acentos + lowercase + sem espaços.
 *
 * Exemplos:
 *   "Especialista"   → "especialista"
 *   "Administrador"  → "administrador"
 *   "Recepcionista"  → "recepcionista"
 *   "Gerente"        → "gerente"
 */
export const resolveAgentRoleSlug = (agent) => {
  const label = resolveAgentRoleLabel(agent);
  if (!label) return '';
  return label
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/\s+/g, '_');
};
