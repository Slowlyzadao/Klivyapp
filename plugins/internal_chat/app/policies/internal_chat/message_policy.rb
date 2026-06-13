# Gateamento das mensagens do Chat Interno.
#
# Membership na room é a fonte canônica de autorização — só quem está na sala
# pode ler/escrever mensagens. A perm Klivy `internal_chat.view` é apenas o
# feature gate (sem ela nenhuma rota do plugin responde, mesmo que o usuário
# fosse membro de alguma sala — proteção contra role demitida).
#
# Update/destroy de mensagem alheia bloqueado mesmo pra admin de sala
# (owner/admin do grupo). Só o autor pode editar/deletar a própria mensagem,
# ou o administrator da conta no nível Chatwoot.
class InternalChat::MessagePolicy < ApplicationPolicy
  # SEC-9 (auditoria 2026-05-18): janela de 5min movida pro nível da
  # policy. Antes o check só vivia no controller; qualquer outro entry
  # point (job, console direto, futura action) ignoraria. Policy é a
  # última linha de defesa — controller mantém checks específicos pra
  # mensagens de UX (`:unprocessable_entity` com texto humano).
  EDIT_WINDOW = 5.minutes

  def index?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  def create?
    return true if @account_user.administrator?
    return false unless can_view_feature?

    member?
  end

  # SEC-8 + SEC-9: editar exige (a) ser autor, (b) ainda ser membro
  # ativo da sala, (c) mensagem não deletada, (d) dentro da janela.
  def update?
    return true if @account_user.administrator?
    return false unless can_view_feature?
    return false unless own_message?
    return false unless member?
    return false if @record.is_a?(InternalChat::Message) && @record.deleted_at?
    return false if @record.is_a?(InternalChat::Message) && @record.created_at < EDIT_WINDOW.ago

    true
  end

  # SEC-8: destruir exige (a) ser autor, (b) ainda ser membro ativo.
  # Sem janela de tempo (soft_delete sempre permitido pelo autor).
  def destroy?
    return true if @account_user.administrator?
    return false unless can_view_feature?
    return false unless own_message?

    member?
  end

  private

  def can_view_feature?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  def member?
    return false if @record.respond_to?(:room) && @record.room.nil?

    room = @record.is_a?(InternalChat::Message) ? @record.room : @record
    # RT-2: scope `.active` (canon) em vez de hardcoded `left_at: nil`.
    room.memberships.active.where(user_id: @user.id).exists?
  end

  def own_message?
    @record.is_a?(InternalChat::Message) && @record.sender_user_id == @user.id
  end
end
