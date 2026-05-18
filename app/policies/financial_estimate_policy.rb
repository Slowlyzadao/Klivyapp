class FinancialEstimatePolicy < ApplicationPolicy
  FINANCIAL_VIEW_PERMS = %i[
    view_dashboard view_cashflow view_receivables view_payables view_dre
    view_reports view_cash_register
  ].freeze

  def index?
    administrator? || any_view_perm?
  end

  def show?
    administrator? || any_view_perm?
  end

  def create?
    administrator? || beclinic_can?(:financial, :manage_estimates)
  end

  def update?
    administrator? || beclinic_can?(:financial, :manage_estimates)
  end

  def destroy?
    administrator? || beclinic_can?(:financial, :manage_estimates)
  end

  def approve?
    administrator? || beclinic_can?(:financial, :approve_estimate)
  end

  def cancel?
    administrator? || beclinic_can?(:financial, :manage_estimates)
  end

  def pay?
    administrator? || beclinic_can?(:financial, :manage_estimates)
  end

  def refund?
    administrator? || beclinic_can?(:financial, :manage_estimates)
  end

  private

  def administrator?
    @account_user&.administrator?
  end

  def any_view_perm?
    FINANCIAL_VIEW_PERMS.any? { |perm| beclinic_can?(:financial, perm) }
  end
end
