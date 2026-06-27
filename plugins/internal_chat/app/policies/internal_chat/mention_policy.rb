# Gatea acesso ao inbox de menções do Chat Interno (auditoria SEC-6,
# 2026-05-18). Mentions são sempre per-user — o controller já scopa pelo
# `Current.user.id`. Esta policy adiciona o feature gate `internal_chat:view`
# pra impedir que usuários sem acesso ao módulo possam mesmo assim consultar
# o inbox de menções (caminho lateral pra info sensível: "alguém me chamou
# em sala X que eu não posso entrar").
class InternalChat::MentionPolicy < ApplicationPolicy
  def index?
    can_view_feature?
  end

  def mark_read?
    can_view_feature?
  end

  def unread_count?
    can_view_feature?
  end

  private

  def can_view_feature?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end
end
