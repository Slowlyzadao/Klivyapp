class BankAccountPolicy < ApplicationPolicy
  # Listagem usada pelos modais de pagamento (Receivables/Payables).
  # Qualquer perm de view financeira basta; CRUD exige `manage_settings`.
  def index?
    AccountTransactionPolicy::FINANCIAL_VIEW_PERMS.any? { |perm| beclinic_can?(:financial, perm) }
  end

  def show?
    index?
  end

  def create?
    beclinic_can?(:financial, :manage_settings)
  end

  def update?
    create?
  end

  def destroy?
    create?
  end
end
