# Política de autorização pra SignatureRequest.
#
# RBAC Klivy (BeclinicPermissible) — o ÚNICO sistema de permissões. Reusa o
# módulo `patients` (assinatura é uma operação sobre Document/ConsentRecord
# do paciente):
#   - LISTAR / VER / refresh   → `patients.view_documents`
#   - CRIAR / CANCELAR / REENVIAR → `patients.manage_documents`
# Refinamento de "só o criador cancela": quem tem escopo `all` no módulo
# patients (visão total = admin de fato) cancela qualquer request; quem tem
# escopo `own` só cancela os que ele mesmo criou.
class SignatureRequestPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:patients, :view_documents)
  end

  def show?
    beclinic_can?(:patients, :view_documents) && record.account_id == account.id
  end

  def create?
    can_manage? && record_signable_accessible?
  end

  def destroy?
    cancel? # destroy é alias de cancel
  end

  def cancel?
    return false unless record.account_id == account.id
    return false unless can_manage?

    full_scope? || record.requested_by_user_id == user.id
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

  # Escrita gateada pelo módulo `patients` do RBAC Klivy.
  def can_manage?
    beclinic_can?(:patients, :manage_documents)
  end

  # Visão total no módulo patients (equivalente a "admin" no fluxo legado).
  def full_scope?
    beclinic_scope(:patients) == 'all'
  end

  def record_signable_accessible?
    return false unless record.respond_to?(:signable)
    # Minimal check: o signable (Document/ConsentRecord) pertence à conta.
    record.signable&.account_id == account.id
  end
end
