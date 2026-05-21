/**
 * Diretiva v-can — Controle de acesso inline via atributo de elemento.
 *
 * Remove ou esconde elementos do DOM quando o usuário não tem permissão.
 * Use PermissionGate para casos mais complexos com slots.
 *
 * Instalação em main.js:
 *   import { vCan } from 'dashboard/directives/vCan';
 *   app.directive('can', vCan);
 *
 * Uso:
 *   <!-- Remove o botão se não pode deletar pacientes -->
 *   <button v-can="['patients', 'delete']">Excluir</button>
 *
 *   <!-- Desabilita (não remove) -->
 *   <button v-can.disable="['financial', 'approve_estimate']">Aprovar</button>
 */
import store from 'dashboard/store';

const hasPermission = (moduleName, action) => {
  const currentRole = store.getters.getCurrentRole;
  if (currentRole === 'administrator') return true;

  return store.getters['beclinicPermissions/can'](moduleName, action);
};

export const vCan = {
  mounted(el, binding) {
    const [moduleName, action] = binding.value || [];
    if (!moduleName || !action) return;

    const allowed = hasPermission(moduleName, action);

    if (!allowed) {
      if (binding.modifiers.disable) {
        el.setAttribute('disabled', 'disabled');
        el.setAttribute('title', 'Você não tem permissão para esta ação');
        el.classList.add('opacity-50', 'cursor-not-allowed');
      } else {
        el.style.display = 'none';
      }
    }
  },

  updated(el, binding) {
    const [moduleName, action] = binding.value || [];
    if (!moduleName || !action) return;

    const allowed = hasPermission(moduleName, action);

    if (!allowed) {
      if (binding.modifiers.disable) {
        el.setAttribute('disabled', 'disabled');
        el.setAttribute('title', 'Você não tem permissão para esta ação');
        el.classList.add('opacity-50', 'cursor-not-allowed');
      } else {
        el.style.display = 'none';
      }
    } else if (binding.modifiers.disable) {
      el.removeAttribute('disabled');
      el.removeAttribute('title');
      el.classList.remove('opacity-50', 'cursor-not-allowed');
    } else {
      el.style.display = '';
    }
  },
};
