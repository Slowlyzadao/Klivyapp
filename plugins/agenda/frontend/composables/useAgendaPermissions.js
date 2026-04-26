import { computed } from 'vue';
import { usePermissions } from 'dashboard/composables/usePermissions';
import { useAlert } from 'dashboard/composables';

const MODULE = 'agenda';

const DENY_MESSAGES = {
  create_event: 'Você não tem permissão para criar eventos.',
  edit_event: 'Você não tem permissão para editar eventos.',
  cancel_event: 'Você não tem permissão para cancelar eventos.',
  drag_and_drop: 'Você não tem permissão para reorganizar eventos.',
  manage_blocks: 'Você não tem permissão para gerenciar bloqueios.',
  manage_notifications: 'Você não tem permissão para gerenciar notificações.',
};

export function useAgendaPermissions() {
  const { can } = usePermissions();

  const canCreate = computed(() => can(MODULE, 'create_event'));
  const canEdit = computed(() => can(MODULE, 'edit_event'));
  const canCancel = computed(() => can(MODULE, 'cancel_event'));
  const canDrag = computed(() => can(MODULE, 'drag_and_drop'));
  const canManageBlocks = computed(() => can(MODULE, 'manage_blocks'));
  const canManageNotifications = computed(() =>
    can(MODULE, 'manage_notifications')
  );

  const guard = (action, fn) => {
    if (!can(MODULE, action)) {
      const msg = DENY_MESSAGES[action] || 'Você não tem permissão.';
      useAlert(msg);
      return undefined;
    }
    return fn();
  };

  return {
    canCreate,
    canEdit,
    canCancel,
    canDrag,
    canManageBlocks,
    canManageNotifications,
    guard,
  };
}
