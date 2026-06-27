# Gateamento dos stickers do Chat Interno.
#
# Modelo de autorização:
#
#   - **Listar / favoritar**: precisa de `internal_chat.view` (feature gate).
#     Favoritar é preferência pessoal — desde que tenha acesso à feature,
#     pode marcar qualquer sticker visível como favorito.
#
#   - **Criar**: precisa de `internal_chat.manage_stickers`. Cria sticker
#     da conta (não system default).
#
#   - **Destruir**:
#     - admin: bypass total
#     - `manage_stickers`: pode deletar qualquer sticker da conta (não default)
#     - autor: pode deletar o próprio sticker (não default)
#     - default stickers (`kind=default`, `account_id=nil`) são imutáveis pra
#       qualquer role — só super admin via console
#
# SEC-10 (auditoria 2026-05-18): update via `update_columns` ou raw SQL no
# console BYPASSA esta policy. Aceitável porque acesso ao console exige
# super_admin Klivy + acesso ao container do app. Mesmo padrão de outros
# plugins (Patient, AgendaEvent) — Pundit é API gate, não DB gate.
class InternalChat::StickerPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:internal_chat, :manage_stickers)
  end

  def destroy?
    # Defaults da plataforma (kind='default', account_id=nil) são imutáveis
    # via API mesmo pra admin da conta — deletar quebra o seed pra TODAS as
    # contas. Manutenção rola só via console (SuperAdmin) ou rake task.
    # Este check vem ANTES do admin bypass de propósito.
    return false if @record.kind == 'default'
    return true if @account_user.administrator?

    beclinic_can?(:internal_chat, :manage_stickers) ||
      @record.created_by_user_id == @user.id
  end

  def favorite?
    @account_user.administrator? || beclinic_can?(:internal_chat, :view)
  end

  def unfavorite?
    favorite?
  end
end
