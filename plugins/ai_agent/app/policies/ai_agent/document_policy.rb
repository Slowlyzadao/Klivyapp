# Gateamento dos endpoints da base de conhecimento da Bea (substitui o
# Captain::Document legado — ver `documents_controller.rb` no plugin).
#
# Usa o módulo `captain` do catálogo Klivy (perm `manage_documents`) porque
# conceitualmente é a mesma feature do antigo "Documentos da BEA" — só que
# armazenada na pgvector via `AiAgent::Document` em vez de `Captain::Document`.
# Reusar o mesmo módulo/perm evita criar uma key duplicada no catálogo e
# preserva semântica pra clínicas que já configuraram roles com essa perm.
class AiAgent::DocumentPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:captain, :manage_documents)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:captain, :manage_documents)
  end
end
