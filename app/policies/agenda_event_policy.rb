class AgendaEventPolicy < ApplicationPolicy
  def index?
    beclinic_can?(:agenda, :view)
  end

  def show?
    return false unless beclinic_can?(:agenda, :view)
    return true if beclinic_scope(:agenda) == 'all'

    # scope=own: só vê eventos onde é o usuário/dentista responsável
    record.user_id == user.id
  end

  def create?
    beclinic_can?(:agenda, :create_event)
  end

  def update?
    beclinic_can?(:agenda, :edit_event)
  end

  def destroy?
    beclinic_can?(:agenda, :cancel_event)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.where(account_id: account.id)
      return base if user.beclinic_scope(account, :agenda) == 'all'

      # scope=own: filtra apenas eventos do dentista/usuário atual
      base.where(user_id: user.id)
    end
  end
end
