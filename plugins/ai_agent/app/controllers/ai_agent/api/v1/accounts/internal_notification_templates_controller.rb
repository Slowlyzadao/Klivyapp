module AiAgent
  module Api
    module V1
      module Accounts
        # CRUD dos templates de notificação interna da Bea. UI vive em
        # /accounts/:id/ai_agent/templates (rota Vue do plugin). Cada template
        # é único por (account, event_key) — clínica edita o body, troca o
        # destino (sala/DM) ou desativa.
        #
        # Endpoint extra `catalog` retorna o vocabulário pra UI montar o
        # dropdown de eventos + lista de salas/users disponíveis como destino.
        class InternalNotificationTemplatesController < ::Api::V1::Accounts::BaseController
          before_action :set_template, only: %i[show update destroy]

          def index
            templates = AiAgent::InternalNotificationTemplate
                        .where(account_id: Current.account.id)
                        .order(:event_key)
            render json: templates.map { |t| serialize(t) }
          end

          def show
            render json: serialize(@template)
          end

          def update
            if @template.update(template_params)
              render json: serialize(@template)
            else
              render json: { errors: @template.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # Cria um template caso a clínica adicione um event_key que ainda não
          # foi seedado (ex: novo evento adicionado em release futuro). Defaults
          # vêm do EventCatalog se não enviados no payload.
          def create
            event_key = params.dig(:internal_notification_template, :event_key) ||
                        params[:event_key]
            return render(json: { errors: ['event_key inválido'] }, status: :unprocessable_entity) unless valid_event?(event_key)

            template = AiAgent::InternalNotificationTemplate.new(
              defaults_for(event_key).merge(template_params.to_h).merge(account_id: Current.account.id)
            )

            if template.save
              render json: serialize(template), status: :created
            else
              render json: { errors: template.errors.full_messages }, status: :unprocessable_entity
            end
          end

          # Reseta UM template ao default do EventCatalog (body, name, target).
          # Útil quando a clínica fez edits e quer voltar ao padrão.
          def reset
            @template = scoped.find(params[:id])
            meta = AiAgent::InternalNotifier::EventCatalog.entry(@template.event_key)
            return render(json: { errors: ['event_key sem default no catálogo'] }, status: :unprocessable_entity) unless meta

            reception_id = ::InternalChat::Room.where(account_id: Current.account.id, system_role: 'reception').pick(:id)
            @template.update!(
              name: meta[:label],
              body: meta[:default_body].to_s.strip,
              target_type: 'room',
              target_id: reception_id,
              enabled: true
            )
            render json: serialize(@template)
          end

          def destroy
            @template.destroy
            head :no_content
          end

          # Vocabulário pra UI montar dropdowns:
          #   events: lista do EventCatalog (label, vars, status do detector)
          #   rooms:  salas do Chat Interno desta conta
          #   users:  AccountUsers ativos (pra DM)
          def catalog
            account_id = Current.account.id

            events = AiAgent::InternalNotifier::EventCatalog::EVENTS.map do |key, meta|
              {
                event_key: key,
                label: meta[:label],
                description: meta[:description],
                available_vars: meta[:available_vars],
                detector_status: meta[:detector_status],
                icon: meta[:icon],
                color: meta[:color],
                default_body: meta[:default_body].to_s.strip
              }
            end

            rooms = ::InternalChat::Room
                    .where(account_id: account_id, archived_at: nil)
                    .order(Arel.sql("system_role IS NULL, system_role, name"))
                    .map { |r| { id: r.id, name: r.name || 'Conversa', system_role: r.system_role, kind: r.kind } }

            users = ::User.joins(:account_users)
                          .where(account_users: { account_id: account_id })
                          .order(:name)
                          .map { |u| { id: u.id, name: u.available_name } }

            render json: { events: events, rooms: rooms, users: users }
          end

          private

          def scoped
            AiAgent::InternalNotificationTemplate.where(account_id: Current.account.id)
          end

          def set_template
            @template = scoped.find(params[:id])
          end

          def template_params
            params.require(:internal_notification_template).permit(
              :event_key, :name, :body, :target_type, :target_id, :enabled
            )
          end

          def valid_event?(event_key)
            AiAgent::InternalNotifier::EventCatalog.keys.include?(event_key)
          end

          def defaults_for(event_key)
            meta = AiAgent::InternalNotifier::EventCatalog.entry(event_key)
            reception_id = ::InternalChat::Room.where(account_id: Current.account.id, system_role: 'reception').pick(:id)
            {
              event_key: event_key,
              name: meta[:label],
              body: meta[:default_body].to_s.strip,
              target_type: 'room',
              target_id: reception_id,
              enabled: true
            }
          end

          def serialize(template)
            meta = AiAgent::InternalNotifier::EventCatalog.entry(template.event_key) || {}
            {
              id: template.id,
              event_key: template.event_key,
              event_label: meta[:label] || template.event_key,
              event_description: meta[:description],
              available_vars: meta[:available_vars] || [],
              detector_status: meta[:detector_status] || :planned,
              icon: meta[:icon],
              color: meta[:color],
              name: template.name,
              body: template.body,
              target_type: template.target_type,
              target_id: template.target_id,
              target_label: target_label(template),
              enabled: template.enabled,
              created_at: template.created_at,
              updated_at: template.updated_at
            }
          end

          def target_label(template)
            case template.target_type
            when 'room'
              room = ::InternalChat::Room.find_by(id: template.target_id)
              room ? "Sala: #{room.name}" : 'Sala removida'
            when 'user'
              user = ::User.find_by(id: template.target_id)
              user ? "DM: #{user.available_name}" : 'Usuário removido'
            else
              'Desativado'
            end
          end
        end
      end
    end
  end
end
