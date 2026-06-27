# Gatea listagem e download de anexos de sala do Chat Interno. Extraído do
# check inline `authorize_room_access` do AttachmentsController (auditoria
# SEC-3, 2026-05-18). Comportamento idêntico ao inline: feature gate
# `internal_chat:view` + ser membro ativo da sala; admin da conta bypassa.
#
# A presença desta classe garante que mudanças futuras no catálogo Klivy
# (ex: perm granular `internal_chat:view_attachments_only`) consigam plugar
# aqui sem refatorar o controller.
class InternalChat::AttachmentPolicy < ApplicationPolicy
  def index?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  def download?
    index?
  end

  private

  # @record é a InternalChat::Room (passada pelo controller via
  # `authorize(@room, policy_class: ...)`). Mantemos compatibilidade
  # mesmo se algum dia for substituída pela Attachment direta.
  def room
    @record.is_a?(InternalChat::Room) ? @record : @record.message.room
  end

  def can_view_feature?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  # RT-2: scope `.active` (canon) em vez de hardcoded `left_at: nil`.
  def member?
    room.memberships.active.where(user_id: @user.id).exists?
  end
end
