class CannedResponsePolicy < ApplicationPolicy
  # Leitura aberta pra qualquer agent: respostas prontas são listadas no editor
  # de mensagem (autocomplete /comando) — restringir quebraria essa UX. Mesmo
  # padrão de LabelPolicy#show? e AgentBotPolicy#index/show. Mutations seguem
  # restritas via Klivy (auditoria A-7 + patch Lote 14 pós-validação em prod
  # com 7 agents Especialista usando o sistema).
  def index?
    @account_user.administrator? || @account_user.agent? || beclinic_can?(:settings, :canned_view)
  end

  def show?
    @account_user.administrator? || @account_user.agent? || beclinic_can?(:settings, :canned_view)
  end

  def create?
    @account_user.administrator? || beclinic_can?(:settings, :canned_create)
  end

  def update?
    @account_user.administrator? || beclinic_can?(:settings, :canned_edit)
  end

  def destroy?
    @account_user.administrator? || beclinic_can?(:settings, :canned_delete)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      scope.where(account_id: account.id)
    end
  end
end
