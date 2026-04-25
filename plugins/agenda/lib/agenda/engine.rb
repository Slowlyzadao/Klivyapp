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
      end

      User.class_eval do
        after_create :ensure_agenda_public_id

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

      Contact.class_eval do
        has_many :agenda_events, dependent: :nullify, class_name: 'AgendaEvent'
      end
    end
  end
end
