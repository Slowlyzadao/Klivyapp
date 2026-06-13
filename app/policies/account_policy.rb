class AccountPolicy < ApplicationPolicy
  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def cache_keys?
    @account_user.administrator? || @account_user.agent?
  end

  def limits?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    # Auditoria M-3: roles Klivy com `settings.account_manage=true` agora
    # também podem editar settings da conta. Admin nativo continua passando.
    @account_user.administrator? || beclinic_can?(:settings, :account_manage)
  end

  def update_active_at?
    true
  end

  def subscription?
    @account_user.administrator?
  end

  def checkout?
    @account_user.administrator?
  end

  def toggle_deletion?
    @account_user.administrator?
  end

  def topup_checkout?
    @account_user.administrator?
  end
end
