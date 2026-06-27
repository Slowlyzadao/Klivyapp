# Gateamento do tom de voz da Bea (projeto de estilo). Mesma perm do
# Treinamento (`captain` view/manage_faqs) porque o perfil de estilo é
# destilado das conversas do Treinamento e faz parte da mesma superfície —
# quem treina a Bea gerencia o tom. Reusar a key evita duplicar o catálogo RBAC.
class AiAgent::StyleProfilePolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def generate?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  # Aprovar/ativar (promover o rascunho para o perfil ativo) + toggle enabled.
  def update?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end
end
