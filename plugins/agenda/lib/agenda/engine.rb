module Agenda
  class Engine < ::Rails::Engine
    # Define an isolated namespace if needed, but not doing isolate_namespace Agenda 
    # right now to avoid renaming all models to Agenda::Event, etc.
    engine_name 'agenda'



    config.to_prepare do
      # Injeção segura nos models do core — sem editar nenhum arquivo do Chatwoot
      Account.class_eval do
        has_many :agenda_events,            dependent: :destroy_async, class_name: 'AgendaEvent'
        has_many :waiting_list_entries,     dependent: :destroy_async, class_name: 'WaitingListEntry'
        has_many :agenda_notification_rules, dependent: :destroy_async, class_name: 'AgendaNotificationRule'
        has_many :agenda_notification_logs,  dependent: :destroy_async, class_name: 'AgendaNotificationLog'
        has_many :agenda_services,          dependent: :destroy_async, class_name: 'AgendaService'
        has_one  :agenda_online_config,     dependent: :destroy,       class_name: 'AgendaOnlineConfig'
        has_one  :agenda_setting,           dependent: :destroy,       class_name: 'AgendaSetting'
        has_many :agenda_custom_attributes, dependent: :destroy_async, class_name: 'AgendaCustomAttribute'
        has_many :agenda_categories,        dependent: :destroy_async, class_name: 'Agenda::Category'
      end

      User.class_eval do
        after_create :ensure_agenda_public_id

        # HABTM: which procedures this specialist offers. Bea filters
        # eligible professionals by this list when a patient asks for a
        # specific service. No link = not considered for that service.
        has_many :agenda_service_users, dependent: :destroy, class_name: 'AgendaServiceUser'
        has_many :agenda_services, through: :agenda_service_users

        def ensure_agenda_public_id
          profile = beclinic_profile
          return if profile.agenda_public_id.present?

          loop do
            profile.agenda_public_id = SecureRandom.alphanumeric(8).downcase
            break unless BeclinicCore::UserProfile.exists?(agenda_public_id: profile.agenda_public_id)
          end
          profile.save!
        end
      end

      AgendaService.class_eval do
        has_many :agenda_service_users, dependent: :destroy
        has_many :users, through: :agenda_service_users
      end

      Contact.class_eval do
        has_many :agenda_events, dependent: :nullify, class_name: 'AgendaEvent'
      end

      # Extends Chatwoot's AgentsController so /api/v1/accounts/:id/agents/:agent_id
      # update accepts agenda_service_ids without editing the core file.
      # Runs AFTER the original update — Chatwoot's standard fields persist
      # first, then we sync the service mapping. No-op if param absent =
      # fully backwards compatible with the existing form.
      if defined?(::Api::V1::Accounts::AgentsController)
        ::Api::V1::Accounts::AgentsController.prepend(Agenda::AgentsControllerExtension)
      end
    end
  end

  # Lives outside the to_prepare block: the module body needs to be defined
  # before the prepend tries to reference it. Zeitwerk autoloads
  # `plugins/agenda/lib/agenda/agents_controller_extension.rb` if extracted —
  # we keep it inline because it's tiny and tied to the engine's lifecycle.
  module AgentsControllerExtension
    def update
      super

      ids_param = params.dig(:agent, :agenda_service_ids)
      return if ids_param.nil?

      ids = Array(ids_param).map(&:to_i).reject(&:zero?)
      valid_ids = Current.account.agenda_services.where(id: ids).pluck(:id)
      @agent.update!(agenda_service_ids: valid_ids)
    end

    private

    def allowed_agent_params
      super + [{ agenda_service_ids: [] }]
    end
  end
end
