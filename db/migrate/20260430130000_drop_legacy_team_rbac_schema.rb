# Drop final do RBAC legado de Times. Pré-requisito: a migration
# 20260430120000_promote_dono_users_to_administrator.rb já rodou e zerou
# os times `owner` + promoveu os "donos" remanescentes a administrator.
#
# Esta migration:
#   - Dropa a tabela `beclinic_team_profiles` (campos `beclinic_role` + `permissions`).
#   - Remove a coluna `teams.is_preset` (marcador de "time fixo do sistema").
#
# Veja docs/03-engineering/implementation-plan-remove-legacy-team-rbac.md (Fase 5).
class DropLegacyTeamRbacSchema < ActiveRecord::Migration[7.1]
  def up
    if connection.table_exists?(:beclinic_team_profiles)
      leftover = connection.exec_query(
        "SELECT COUNT(*) AS n FROM teams WHERE name = 'owner'"
      ).rows.flatten.first.to_i

      if leftover.positive?
        raise "Ainda há #{leftover} time(s) 'owner' — rode 20260430120000 antes."
      end

      drop_table :beclinic_team_profiles
    end

    remove_column :teams, :is_preset if column_exists?(:teams, :is_preset)
  end

  def down
    add_column :teams, :is_preset, :boolean, default: false, null: false

    create_table :beclinic_team_profiles do |t|
      t.references :team, null: false, foreign_key: true
      t.string :beclinic_role
      t.jsonb :permissions, default: {}
      t.timestamps
    end
  end
end
