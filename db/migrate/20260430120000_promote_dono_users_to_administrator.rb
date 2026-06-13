# Promove a `account_user.role = administrator` qualquer usuário que ainda
# era "dono" via `beclinic_team_profiles.beclinic_role = 'dono'` e estava no
# time `owner` invisível. Em seguida remove o time `owner` (não é mais usado
# pelo BeclinicPermissible — Fase 2 desta refatoração já tirou a leitura).
#
# Idempotente: usuário que já é `administrator` é ignorado; se não houver mais
# time `owner`, a migration sai sem fazer nada.
#
# Usa SQL puro (sem AR models) porque na Fase 3 o `Team.class_eval` que
# definia `has_one :beclinic_profile` foi removido — então `Team.joins(:beclinic_profile)`
# levantaria `ConfigurationError` se este script dependesse do model.
#
# Veja docs/03-engineering/implementation-plan-remove-legacy-team-rbac.md (Fase 3).
class PromoteDonoUsersToAdministrator < ActiveRecord::Migration[7.1]
  ADMINISTRATOR_ROLE = 1 # AccountUser.roles[:administrator]

  def up
    # Se a tabela legada não existir, nada a fazer.
    return unless connection.table_exists?(:beclinic_team_profiles)

    promoted = connection.exec_update(<<~SQL)
      UPDATE account_users
      SET role = #{ADMINISTRATOR_ROLE}
      WHERE id IN (
        SELECT au.id
        FROM account_users au
        JOIN team_members tm ON tm.user_id = au.user_id
        JOIN teams t ON t.id = tm.team_id AND t.account_id = au.account_id
        JOIN beclinic_team_profiles btp ON btp.team_id = t.id
        JOIN users u ON u.id = au.user_id
        WHERE btp.beclinic_role = 'dono'
          AND au.role <> #{ADMINISTRATOR_ROLE}
          AND (u.type IS NULL OR u.type <> 'SuperAdmin')
      )
    SQL
    say "Promoted #{promoted} account_user(s) to administrator."

    legacy_team_ids = connection.exec_query(<<~SQL).rows.flatten
      SELECT t.id
      FROM teams t
      JOIN beclinic_team_profiles btp ON btp.team_id = t.id
      WHERE btp.beclinic_role = 'dono'
    SQL

    if legacy_team_ids.any?
      placeholders = legacy_team_ids.join(',')
      connection.execute("DELETE FROM team_members WHERE team_id IN (#{placeholders})")
      connection.execute("DELETE FROM beclinic_team_profiles WHERE team_id IN (#{placeholders})")
      connection.execute("DELETE FROM teams WHERE id IN (#{placeholders})")
      say "Removed #{legacy_team_ids.size} legacy 'owner' team(s)."
    else
      say "No legacy 'owner' team found — nothing to remove."
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
