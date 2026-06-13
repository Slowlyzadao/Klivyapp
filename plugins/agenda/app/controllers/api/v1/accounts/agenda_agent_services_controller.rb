# Gerencia quais serviços (AgendaService) um profissional (User) atende —
# popula a tabela de junção `agenda_service_users`. Exposto no modal
# "Editar Agente" (campo "Serviços que atende").
#
# Por que importa: sem nenhuma linha de vínculo, o serviço fica INVISÍVEL
# pra Bia — `clinic_info` e `search_available_slots` só consideram serviços
# com >=1 profissional vinculado. Era o elo que faltava na UI.
#
# Admin-only (gestão de agentes). `:id` no update = user_id do agente.
class Api::V1::Accounts::AgendaAgentServicesController < Api::V1::Accounts::BaseController
  before_action :check_admin
  before_action :set_agent

  # GET /agenda_agent_services?user_id=:id
  # → { services: [{id, name}], selected_ids: [Integer] }
  def index
    render json: {
      services: account_services.map { |s| { id: s.id, name: s.name } },
      selected_ids: linked_service_ids,
    }
  end

  # PUT /agenda_agent_services/:id   (body: { service_ids: [Integer] })
  # Substitui o conjunto de serviços do agente pelo enviado (atômico).
  def update
    desired = Array(params[:service_ids]).map(&:to_i).uniq
    valid = account_services.where(id: desired).pluck(:id)

    ActiveRecord::Base.transaction do
      current = linked_service_ids
      (valid - current).each do |service_id|
        ::AgendaServiceUser.create!(
          account_id: Current.account.id,
          agenda_service_id: service_id,
          user_id: @agent.id
        )
      end
      to_remove = current - valid
      if to_remove.any?
        ::AgendaServiceUser
          .where(account_id: Current.account.id, user_id: @agent.id, agenda_service_id: to_remove)
          .delete_all
      end
    end

    render json: { selected_ids: valid }
  end

  private

  def account_services
    ::AgendaService.where(account_id: Current.account.id, deleted_at: nil).order(:position, :name)
  end

  def linked_service_ids
    ::AgendaServiceUser.where(account_id: Current.account.id, user_id: @agent.id).pluck(:agenda_service_id)
  end

  def set_agent
    @agent = Current.account.users.find(params[:id] || params[:user_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Agente não encontrado nesta conta.' }, status: :not_found
  end

  def check_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Acesso negado.' }, status: :unauthorized
  end
end
