module BeclinicCore
  class Engine < ::Rails::Engine
    isolate_namespace BeclinicCore

    initializer 'beclinic_core.devise_mailer', after: :load_config_initializers do
      Devise.mailer = 'KlivyMailer'
    end

    config.after_initialize do
      plugin_locales = Dir[BeclinicCore::Engine.root.join('config/locales/**/*.yml').to_s]
      I18n.load_path -= plugin_locales
      I18n.load_path += plugin_locales
      I18n.backend.reload! if I18n.backend.respond_to?(:reload!)
    end

    config.to_prepare do
      Account.class_eval do
        has_one :beclinic_profile, class_name: 'BeclinicCore::AccountProfile', dependent: :destroy, autosave: true

        def beclinic_profile
          super || build_beclinic_profile
        end

        delegate :monthly_goal, :monthly_goal=,
                 :quarterly_goal, :quarterly_goal=,
                 :annual_goal, :annual_goal=,
                 to: :beclinic_profile

        after_create_commit :setup_beclinic_owner

        # Promotes the first AccountUser of this account to Owner (beclinic_role: 'dono').
        # Fires once on account creation (e.g. after a plan purchase via AccountBuilder).
        # Skips gracefully if there is no linked user yet (e.g. test factories creating
        # an account without users), and never raises — failure here must not break the
        # account creation transaction.
        def setup_beclinic_owner
          first_account_user = account_users.order(:created_at).first
          return unless first_account_user&.user
          # Never auto-promote a SaaS SuperAdmin (they already bypass all checks).
          return if first_account_user.user.is_a?(SuperAdmin)

          BeclinicCore::AccountSetup.promote_to_owner!(account: self, user: first_account_user.user)
        rescue StandardError => e
          Rails.logger.warn("[BeclinicCore] Auto-promote owner failed for account #{id}: #{e.class}: #{e.message}")
        end
      end

      User.class_eval do
        include BeclinicPermissible
        has_one :beclinic_profile, class_name: 'BeclinicCore::UserProfile', dependent: :destroy, autosave: true

        def beclinic_profile
          super || build_beclinic_profile
        end

        delegate :agenda_public_id, :agenda_public_id=, to: :beclinic_profile
      end

      Team.class_eval do
        has_one :beclinic_profile, class_name: 'BeclinicCore::TeamProfile', dependent: :destroy, autosave: true

        def beclinic_profile
          super || build_beclinic_profile
        end

        delegate :beclinic_role, :beclinic_role=,
                 :permissions, :permissions=,
                 :can?, :scope_for, :dono?,
                 to: :beclinic_profile
      end

      # Hide the internal "owner" team from the clinic-facing Teams listing
      # (sidebar + Settings → Times). It is infrastructure for the Owner
      # permission scheme (beclinic_role: 'dono'), not a team the clinic owner
      # manages directly. Individual team operations (show/update/destroy) are
      # unaffected and still validate via authorization if ever targeted.
      Api::V1::Accounts::TeamsController.class_eval do
        def index
          @teams = Current.account.teams.where.not(name: BeclinicCore::AccountSetup::OWNER_TEAM_NAME)
        end
      end
    end
  end
end
