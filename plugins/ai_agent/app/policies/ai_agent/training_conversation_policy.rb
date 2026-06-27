# Gateamento da aba "Treinamento" da Bea. Usa a perm `manage_faqs` do módulo
# `captain` (e `view` para leitura) porque o treinamento alimenta as FAQs —
# quem treina precisa poder aprovar as FAQs geradas, gateadas pela mesma
# perm. Reusar a key evita duplicar o catálogo RBAC.
class AiAgent::TrainingConversationPolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  # Exclusão em massa (conversas ou FAQs) — mesma perm do delete unitário.
  def destroy_all?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  # Lista das FAQs sugeridas pendentes (leitura) — mesma perm do show.
  def pending_faqs?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  # Aprovação em massa das FAQs sugeridas — mesma perm do publish.
  def approve_all?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  def publish?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  def select_clinic?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  # Seleção da clínica em massa — mesma perm do select_clinic unitário.
  def select_clinic_bulk?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end
end
