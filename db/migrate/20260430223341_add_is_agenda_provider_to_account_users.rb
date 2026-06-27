# frozen_string_literal: true

# Adds `is_agenda_provider` to `account_users` — a per-user override that
# decides whether the user appears as a column on the agenda calendar
# (i.e., is bookable as a service provider).
#
# Resolution order in the application:
#   1. `account_users.is_agenda_provider` (NULL = inherit)
#   2. `klivy_role.permissions['agenda']['is_provider']`
#   3. `false`
#
# Backfill: every existing `account_user` is set to `true` so that current
# behaviour is preserved (everyone keeps appearing on the calendar). New
# users created after this migration default to NULL and inherit from
# their role's preset.
class AddIsAgendaProviderToAccountUsers < ActiveRecord::Migration[7.1]
  def up
    add_column :account_users, :is_agenda_provider, :boolean, null: true

    say_with_time 'Backfilling is_agenda_provider=true for existing account_users' do
      connection.exec_update(<<~SQL)
        UPDATE account_users SET is_agenda_provider = TRUE
        WHERE is_agenda_provider IS NULL
      SQL
    end

    # Roles existentes (criadas antes desta migration) não têm
    # `agenda.is_provider` no hash de permissões. Como o backfill acima
    # já garante que todos os account_users atuais sigam aparecendo na
    # agenda, NÃO mexemos no hash das roles aqui — o admin re-salva
    # cada role no editor quando precisar mudar o default para novos
    # usuários atribuídos. A UI já expõe o toggle.
  end

  def down
    remove_column :account_users, :is_agenda_provider
  end
end
