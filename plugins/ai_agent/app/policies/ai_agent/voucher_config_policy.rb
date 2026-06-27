# Gateamento da config de voucher. Mesma perm do Treinamento/tom de voz
# (`captain` view/manage_faqs) — é uma config da Bea na mesma superfície; admin
# bypassa. Reusar a key evita mexer no catálogo RBAC.
class AiAgent::VoucherConfigPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || beclinic_can?(:captain, :view)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:captain, :manage_faqs)
  end
end
