# Política de autorização pra DocumentTemplate.
#
# Regras do MVP (alinhamento com plano §1.5):
#   - Qualquer agent/admin da clínica pode LISTAR e VER templates (pra
#     gerar documento dentro do paciente).
#   - SÓ administradores podem criar/editar/duplicar/arquivar/deletar.
#   - Templates Klivy globais (account_id NULL) são read-only — pra editar
#     a clínica precisa clonar (clone_to_account).
#
# Fase 2 poderá criar role custom 'document_editor' (já existe o plugin
# custom_roles), mas pro MVP usamos só o booleano administrator?.
class DocumentTemplatePolicy < ApplicationPolicy
  def index?
    true # qualquer usuário da clínica vê a lista
  end

  def show?
    record.account_id == account.id || record.klivy?
  end

  def variables?
    true # endpoint de catálogo é público pra qualquer logado da conta
  end

  def klivy_library?
    true # biblioteca Klivy é visível pra todas as clínicas
  end

  def create?
    administrator? && record_belongs_to_account?
  end

  def update?
    administrator? && record_belongs_to_account? && !record.klivy?
  end

  def destroy?
    administrator? && record_belongs_to_account? && !record.klivy?
  end

  def duplicate?
    administrator? && (record.account_id == account.id || record.klivy?)
  end

  def clone_to_account?
    administrator? && record.klivy?
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

  def administrator?
    account_user&.administrator?
  end

  def record_belongs_to_account?
    return false if record.nil?
    return true if record.is_a?(Class) # `authorize DocumentTemplate, :create?`

    record.account_id == account.id
  end
end
