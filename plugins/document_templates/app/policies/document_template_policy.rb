# Política de autorização pra DocumentTemplate.
#
# RBAC: alinhado ao sistema Klivy (BeclinicPermissible) — o ÚNICO sistema de
# permissões do projeto. Reusa o módulo `patients` (mesmas chaves do
# DocumentPolicy do paciente):
#   - LISTAR / VER / variáveis / biblioteca  → `patients.view_documents`.
#   - CRIAR / EDITAR / DUPLICAR / CLONAR / ARQUIVAR / DELETAR → `patients.manage_documents`.
# Templates Klivy globais (account_id NULL) são read-only — pra editar a
# clínica precisa clonar (clone_to_account).
class DocumentTemplatePolicy < ApplicationPolicy
  # Listagem read-only de modelos. Serve aos DOIS seletores do prontuário
  # ("Gerar a partir de modelo" nas abas Documentos e Consentimentos), por
  # isso aceita tanto `view_documents` quanto `view_consents` — um usuário que
  # só gerencia consentimentos precisa enxergar os modelos de consentimento.
  def index?
    beclinic_can?(:patients, :view_documents) ||
      beclinic_can?(:patients, :view_consents)
  end

  def show?
    beclinic_can?(:patients, :view_documents) && (record.account_id == account.id || record.klivy?)
  end

  def variables?
    beclinic_can?(:patients, :view_documents)
  end

  def klivy_library?
    beclinic_can?(:patients, :view_documents)
  end

  def create?
    can_manage? && record_belongs_to_account?
  end

  def update?
    can_manage? && record_belongs_to_account? && !record.klivy?
  end

  def destroy?
    can_manage? && record_belongs_to_account? && !record.klivy?
  end

  def duplicate?
    can_manage? && (record.account_id == account.id || record.klivy?)
  end

  def clone_to_account?
    can_manage? && record.klivy?
  end

  def archive?
    update?
  end

  def unarchive?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    # Templates visíveis: os da clínica + os Klivy globais.
    def resolve
      scope.for_account(account)
    end
  end

  private

  # Escrita gateada pelo módulo `patients` do RBAC Klivy.
  def can_manage?
    beclinic_can?(:patients, :manage_documents)
  end

  def record_belongs_to_account?
    return false if record.nil?
    return true if record.is_a?(Class) # `authorize DocumentTemplate, :create?`

    record.account_id == account.id
  end
end
