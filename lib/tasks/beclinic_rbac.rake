# lib/tasks/beclinic_rbac.rake
#
# Rake tasks for BeClinic RBAC maintenance.
#
# Usage:
#   bundle exec rake beclinic:rbac:ensure_default_profiles      # Creates preset teams for all accounts that don't have them
#   bundle exec rake beclinic:rbac:assign_missing_users          # Assigns users without a team to the 'especialista' default team
#   bundle exec rake beclinic:rbac:status                        # Print a summary of RBAC coverage per account
#

beclinic_preset_profiles = [
  {
    name: 'recepcionista',
    beclinic_role: 'gerente',
    is_preset: true,
    permissions: {
      patients: { scope: 'all', view: true, create: true, edit: true, delete: false,
                  view_clinical_notes: false, create_clinical_notes: false, sign_clinical_notes: false,
                  delete_clinical_notes: false, view_treatment_plans: true, manage_treatment_plans: false,
                  view_consents: true, manage_consents: false, view_documents: true, manage_documents: false,
                  view_exams: true, manage_exams: false, view_audit: false, view_timeline: true },
      agenda: { scope: 'all', view: true, create_event: true, edit_event: true, cancel_event: true,
                drag_and_drop: true, manage_blocks: false, view_notifications: true, manage_notifications: false },
      financial: { view_transactions: true, create_transaction: true, delete_transaction: false,
                   view_estimates: true, create_estimate: false, edit_estimate: false,
                   approve_estimate: false, delete_estimate: false, view_cashflow: false, export_cashflow: false },
      chat: { view_all: true, view_unassigned: true, reply: true, assign_conversation: true,
              transfer_inbox: true, delete_message: false, send_broadcast: false },
      settings: { manage_users: false, manage_roles: false, manage_agenda_config: false,
                  manage_inboxes: false, view_reports: false }
    }
  },
  {
    name: 'especialista',
    beclinic_role: 'especialista',
    is_preset: true,
    permissions: {
      patients: { scope: 'own', view: true, create: true, edit: true, delete: false,
                  view_clinical_notes: true, create_clinical_notes: true, sign_clinical_notes: true,
                  delete_clinical_notes: true, view_treatment_plans: true, manage_treatment_plans: true,
                  view_consents: true, manage_consents: true, view_documents: true, manage_documents: true,
                  view_exams: true, manage_exams: true, view_audit: true, view_timeline: true },
      agenda: { scope: 'own', view: true, create_event: true, edit_event: true, cancel_event: true,
                drag_and_drop: true, manage_blocks: true, view_notifications: true, manage_notifications: false },
      financial: { view_transactions: true, create_transaction: true, delete_transaction: false,
                   view_estimates: true, create_estimate: true, edit_estimate: true,
                   approve_estimate: false, delete_estimate: false, view_cashflow: false, export_cashflow: false },
      chat: { view_all: false, view_unassigned: false, reply: true, assign_conversation: false,
              transfer_inbox: false, delete_message: false, send_broadcast: false },
      settings: { manage_users: false, manage_roles: false, manage_agenda_config: false,
                  manage_inboxes: false, view_reports: false }
    }
  },
  {
    name: 'gerente',
    beclinic_role: 'gerente',
    is_preset: true,
    permissions: {
      patients: { scope: 'all', view: true, create: true, edit: true, delete: true,
                  view_clinical_notes: true, create_clinical_notes: true, sign_clinical_notes: true,
                  delete_clinical_notes: true, view_treatment_plans: true, manage_treatment_plans: true,
                  view_consents: true, manage_consents: true, view_documents: true, manage_documents: true,
                  view_exams: true, manage_exams: true, view_audit: true, view_timeline: true },
      agenda: { scope: 'all', view: true, create_event: true, edit_event: true, cancel_event: true,
                drag_and_drop: true, manage_blocks: true, view_notifications: true, manage_notifications: true },
      financial: { view_transactions: true, create_transaction: true, delete_transaction: true,
                   view_estimates: true, create_estimate: true, edit_estimate: true,
                   approve_estimate: true, delete_estimate: true, view_cashflow: true, export_cashflow: true },
      chat: { view_all: true, view_unassigned: true, reply: true, assign_conversation: true,
              transfer_inbox: true, delete_message: true, send_broadcast: true },
      settings: { manage_users: true, manage_roles: true, manage_agenda_config: true,
                  manage_inboxes: false, view_reports: true }
    }
  },
  {
    name: 'sdr',
    beclinic_role: 'especialista',
    is_preset: true,
    permissions: {
      patients: { scope: 'all', view: true, create: true, edit: false, delete: false,
                  view_clinical_notes: false, create_clinical_notes: false, sign_clinical_notes: false,
                  delete_clinical_notes: false, view_treatment_plans: false, manage_treatment_plans: false,
                  view_consents: false, manage_consents: false, view_documents: false, manage_documents: false,
                  view_exams: false, manage_exams: false, view_audit: false, view_timeline: true },
      agenda: { scope: 'all', view: true, create_event: true, edit_event: true, cancel_event: true,
                drag_and_drop: false, manage_blocks: false, view_notifications: false, manage_notifications: false },
      financial: { view_transactions: false, create_transaction: false, delete_transaction: false,
                   view_estimates: true, create_estimate: true, edit_estimate: true,
                   approve_estimate: false, delete_estimate: false, view_cashflow: false, export_cashflow: false },
      chat: { view_all: true, view_unassigned: true, reply: true, assign_conversation: true,
              transfer_inbox: false, delete_message: false, send_broadcast: true },
      settings: { manage_users: false, manage_roles: false, manage_agenda_config: false,
                  manage_inboxes: false, view_reports: false }
    }
  }
].freeze

namespace :beclinic do
  namespace :rbac do
    desc 'Create the 4 preset RBAC profiles for every account that does not have them yet'
    task ensure_default_profiles: :environment do
      accounts = Account.all
      puts "Processing #{accounts.count} accounts..."

      accounts.each do |account|
        beclinic_preset_profiles.each do |profile|
          next if account.teams.exists?(name: profile[:name])

          account.teams.create!(
            name: profile[:name],
            beclinic_role: profile[:beclinic_role],
            is_preset: profile[:is_preset],
            permissions: profile[:permissions]
          )
          puts "  [#{account.id}] Created preset profile '#{profile[:name]}'"
        end
      end

      puts 'Done.'
    end

    desc 'Assign users without any RBAC team to the especialista preset team in their account'
    task assign_missing_users: :environment do
      puts 'Looking for users without RBAC team assignment...'
      assigned = 0

      AccountUser.includes(:user, :account).find_each do |au|
        user = au.user
        account = au.account

        # Skip if user already belongs to a team in this account
        next if user.teams.where(account_id: account.id).exists?

        # Find the 'especialista' preset team for this account
        fallback_team = account.teams.find_by(name: 'especialista', is_preset: true)

        unless fallback_team
          puts "  [account #{account.id}] No 'especialista' preset team found. Run ensure_default_profiles first."
          next
        end

        fallback_team.team_members.find_or_create_by!(user: user)
        assigned += 1
        puts "  Assigned user #{user.id} (#{user.email}) → 'especialista' in account #{account.id}"
      end

      puts "Done. Assigned #{assigned} user(s)."
    end

    desc 'Print RBAC coverage status for all accounts'
    task status: :environment do
      Account.find_each do |account|
        teams_count = account.teams.count
        users_count = AccountUser.where(account: account).count
        users_with_team = AccountUser.where(account: account).joins(user: :team_members)
                                     .where(team_members: { team_id: account.teams.select(:id) })
                                     .distinct.count

        puts "[Account #{account.id}] #{account.name}"
        puts "  Teams/Profiles: #{teams_count}"
        puts "  Users: #{users_count} total | #{users_with_team} with team | #{users_count - users_with_team} WITHOUT team"
        account.teams.each do |team|
          member_count = team.team_members.count
          puts "    - #{team.name} (#{team.beclinic_role}) #{team.is_preset? ? '[preset]' : '[custom]'} — #{member_count} members"
        end
      end
    end
  end
end
