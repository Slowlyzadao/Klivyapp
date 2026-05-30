# Política de autorização pra DocumentTemplateFolder.
#
# Mesmas regras de DocumentTemplatePolicy: agent lê, admin escreve. Pastas
# Klivy não existem (templates Klivy ficam em seção dedicada no UI).
class DocumentTemplateFolderPolicy < ApplicationPolicy
  def index?;  true; end
  def show?;   record.account_id == account.id; end
  def create?; administrator?; end
  def update?; administrator? && record.account_id == account.id; end
  def destroy?; administrator? && record.account_id == account.id; end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account: account)
    end
  end

  private

  def administrator?
    account_user&.administrator?
  end
end
