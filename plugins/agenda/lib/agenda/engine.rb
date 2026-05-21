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
        # 9.7 da auditoria 2026-05-14 — vínculo serviço↔profissional.
        # Permite que UI futura liste/edite "quais serviços esse pro oferece".
        has_many :agenda_service_users, dependent: :destroy
        has_many :agenda_services, through: :agenda_service_users

        after_create :ensure_agenda_public_id

        def ensure_agenda_public_id
          # Bail OUT antes de tocar em `beclinic_profile`. O association em
          # `BeclinicCore::Engine` é `has_one :beclinic_profile, autosave: true`,
          # e `beclinic_profile` (método sobrescrito) faz `super || build_beclinic_profile`.
          # Se o User ainda não tem AccountUser (caso do AgentBuilder, que cria
          # User e AccountUser na MESMA transaction — User vem primeiro), a instância
          # em memória é anexada com `account_id=nil`, e o `autosave` força o INSERT
          # mesmo se NÃO chamarmos `profile.save!` aqui — explodindo na constraint
          # NOT NULL de `beclinic_user_profiles.account_id` (migration 20260514100001).
          # O fluxo do AgentBuilder volta a funcionar via `AccountUser.after_create_commit`
          # (abaixo), que retenta este método quando o vínculo já existe. (bug-AddAgent)
          return unless account_users.exists?

          profile = beclinic_profile
          return if profile.agenda_public_id.present?

          profile.account_id ||= account_users.order(:id).first&.account_id
          return if profile.account_id.blank?

          loop do
            profile.agenda_public_id = SecureRandom.alphanumeric(8).downcase
            break unless BeclinicCore::UserProfile.exists?(agenda_public_id: profile.agenda_public_id)
          end
          profile.save!
        end
      end

      AccountUser.class_eval do
        # Backstop do `User#ensure_agenda_public_id` para o fluxo `AgentBuilder`:
        # User é criado ANTES de AccountUser na mesma transaction, então o
        # `after_create :ensure_agenda_public_id` no User dispara enquanto
        # `account_users` ainda está vazio e faz early return. Aqui, depois do
        # commit do AccountUser, retentamos — agora `account_users.exists?`
        # é true e o profile é criado com `account_id` correto.
        after_create_commit :ensure_user_agenda_public_id

        def ensure_user_agenda_public_id
          user&.ensure_agenda_public_id
        end
      end

      Contact.class_eval do
        has_many :agenda_events, dependent: :nullify, class_name: 'AgendaEvent'
      end
    end
  end
end
