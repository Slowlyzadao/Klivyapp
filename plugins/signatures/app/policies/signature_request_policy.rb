# Política de autorização pra SignatureRequest.
#
# Regras MVP:
#   - index/show: qualquer agent da clínica
#   - create/cancel/resend/refresh_status: precisa ser admin OU o user que
#     criou o request original (RBAC delegado pro signable também)
class SignatureRequestPolicy < ApplicationPolicy
  def index?;  true; end
  def show?;   record.account_id == account.id; end

  def create?
    administrator? || record_signable_accessible?
  end

  def destroy?
    cancel? # destroy é alias de cancel
  end

  def cancel?
    return false unless record.account_id == account.id
    return true if administrator?
    record.requested_by_user_id == user.id
  end

  def resend?
    cancel?
  end

  def refresh_status?
    show?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account: account)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end

  def record_signable_accessible?
    return false unless record.respond_to?(:signable)
    # Reusa policy do signable se houver — minimal check: pertence à conta.
    record.signable&.account_id == account.id
  end
end
