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

  # Sprint K — admin-side: entrar na sala LiveKit como profissional.
  # Strict por design: APENAS o usuário responsável pelo evento pode entrar
  # — mesmo Admin com beclinic_scope='all' não passa, porque a identity da
  # sala precisa ser o dentista real (paciente vê quem está atendendo).
  # Se a clínica quiser que outra pessoa cubra, precisa reatribuir o evento.
  def telemedicine_join?
    return false unless beclinic_can?(:agenda, :view)

    record.user_id == user.id
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
