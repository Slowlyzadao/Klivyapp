# Gateamento do system message da Bea por conta. Leitura: quem acessa a BEA
# (`captain.view`). Edição: `captain.manage_settings` ("Configurar BEA") — o
# system prompt é a configuração mais sensível da Bea (pode quebrar o
# atendimento), então fica na perm de configurar, não na de FAQs. Admin passa
# por cima (administrator? || beclinic_super_admin? no ApplicationPolicy).
class AiAgent::SystemPromptPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:captain, :manage_settings)
  end
end
