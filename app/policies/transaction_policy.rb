class TransactionPolicy < ApplicationPolicy
  # Mesma lógica do AccountTransactionPolicy: index/show passam se o usuário
  # tiver qualquer perm de visualização financeira; ações específicas usam
  # as suas próprias keys.
  FINANCIAL_VIEW_PERMS = %i[
    view_dashboard
    view_cashflow
    view_receivables
    view_payables
    view_dre
    view_reports
    view_cash_register
  ].freeze

  def index?
    FINANCIAL_VIEW_PERMS.any? { |perm| beclinic_can?(:financial, perm) }
  end

  def show?
    index?
  end

  def create?
    beclinic_can?(:financial, :create_transaction)
  end

  def update?
    beclinic_can?(:financial, :edit_transaction)
  end

  def destroy?
    beclinic_can?(:financial, :delete_transaction)
  end

  def approve?
    beclinic_can?(:financial, :approve_estimate)
  end

  def cancel?
    beclinic_can?(:financial, :edit_transaction)
  end

  def pay?
    beclinic_can?(:financial, :create_transaction)
  end

  def refund?
    beclinic_can?(:financial, :delete_transaction)
  end

  def financial_summary?
    index?
  end
end
