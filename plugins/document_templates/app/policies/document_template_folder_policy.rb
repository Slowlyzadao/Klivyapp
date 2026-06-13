# Política de autorização pra DocumentTemplateFolder.
#
# RBAC Klivy (BeclinicPermissible), módulo `patients` — mesmas chaves do
# DocumentTemplatePolicy: `view_documents` lê, `manage_documents` escreve.
# Pastas Klivy não existem (templates Klivy ficam em seção dedicada no UI).
class DocumentTemplateFolderPolicy < ApplicationPolicy
  def index?;  beclinic_can?(:patients, :view_documents); end
  def show?;   beclinic_can?(:patients, :view_documents) && record.account_id == account.id; end
  def create?; can_manage?; end
  def update?; can_manage? && record.account_id == account.id; end
  def destroy?; can_manage? && record.account_id == account.id; end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account: account)
    end
  end

  private

  def can_manage?
    beclinic_can?(:patients, :manage_documents)
  end
end
