class AccountPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def cache_keys?
    show?
  end

  def limits?
    show?
  end

  def update?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :account_manage)
  end

  def update_active_at?
    true
  end

  def subscription?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :billing_manage)
  end

  def checkout?
    subscription?
  end

  def toggle_deletion?
    return true if @account_user.administrator?

    beclinic_can?(:settings, :account_manage)
  end

  def topup_checkout?
    subscription?
  end
end
