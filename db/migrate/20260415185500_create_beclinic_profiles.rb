class CreateBeclinicProfiles < ActiveRecord::Migration[7.0]
  def up
    # 1. Tabela de Profile de Contas
    create_table :beclinic_account_profiles do |t|
      t.references :account, null: false, foreign_key: true
      t.decimal :monthly_goal, precision: 15, scale: 2
      t.decimal :quarterly_goal, precision: 15, scale: 2
      t.decimal :annual_goal, precision: 15, scale: 2
      t.timestamps
    end

    # Migrar Dados Accounts
    execute <<-SQL
      INSERT INTO beclinic_account_profiles (account_id, monthly_goal, quarterly_goal, annual_goal, created_at, updated_at)
      SELECT id, monthly_goal, quarterly_goal, annual_goal, NOW(), NOW()
      FROM accounts
      WHERE monthly_goal IS NOT NULL OR quarterly_goal IS NOT NULL OR annual_goal IS NOT NULL;
    SQL

    # 2. Tabela de Profile de Usuarios
    create_table :beclinic_user_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.string :agenda_public_id
      t.timestamps
    end

    # Migrar Dados Users
    execute <<-SQL
      INSERT INTO beclinic_user_profiles (user_id, agenda_public_id, created_at, updated_at)
      SELECT id, agenda_public_id, NOW(), NOW()
      FROM users
      WHERE agenda_public_id IS NOT NULL;
    SQL

    # 3. Tabela de Profile de Times
    create_table :beclinic_team_profiles do |t|
      t.references :team, null: false, foreign_key: true
      t.string :beclinic_role
      t.jsonb :permissions, default: {}
      t.timestamps
    end

    # Migrar Dados Teams
    execute <<-SQL
      INSERT INTO beclinic_team_profiles (team_id, beclinic_role, permissions, created_at, updated_at)
      SELECT id, beclinic_role, COALESCE(permissions, '{}'::jsonb), NOW(), NOW()
      FROM teams
      WHERE beclinic_role IS NOT NULL OR permissions IS NOT NULL;
    SQL

    # Drop colunas originais do Chatwoot
    remove_column :accounts, :monthly_goal
    remove_column :accounts, :quarterly_goal
    remove_column :accounts, :annual_goal
    remove_column :users, :agenda_public_id
    remove_column :teams, :beclinic_role
    remove_column :teams, :permissions
  end

  def down
    # Rollback - re-add columns
    add_column :accounts, :monthly_goal, :decimal, precision: 15, scale: 2
    add_column :accounts, :quarterly_goal, :decimal, precision: 15, scale: 2
    add_column :accounts, :annual_goal, :decimal, precision: 15, scale: 2
    add_column :users, :agenda_public_id, :string
    add_column :teams, :beclinic_role, :string
    add_column :teams, :permissions, :jsonb, default: {}

    # Restore data
    execute <<-SQL
      UPDATE accounts a
      SET monthly_goal = p.monthly_goal,
          quarterly_goal = p.quarterly_goal,
          annual_goal = p.annual_goal
      FROM beclinic_account_profiles p
      WHERE a.id = p.account_id;
    SQL

    execute <<-SQL
      UPDATE users u
      SET agenda_public_id = p.agenda_public_id
      FROM beclinic_user_profiles p
      WHERE u.id = p.user_id;
    SQL

    execute <<-SQL
      UPDATE teams t
      SET beclinic_role = p.beclinic_role,
          permissions = p.permissions
      FROM beclinic_team_profiles p
      WHERE t.id = p.team_id;
    SQL

    drop_table :beclinic_team_profiles
    drop_table :beclinic_user_profiles
    drop_table :beclinic_account_profiles
  end
end
