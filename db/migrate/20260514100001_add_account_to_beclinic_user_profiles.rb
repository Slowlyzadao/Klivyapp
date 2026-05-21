class AddAccountToBeclinicUserProfiles < ActiveRecord::Migration[7.0]
  # Auditoria agendamento público (docs/03-engineering/auditoria-agendamento-publico.md
  # item 9.4): o controller público resolvia `@account = @user.accounts.first`,
  # vazando agenda entre contas quando o user pertence a mais de uma. O profile
  # passa a carregar `account_id` explicitamente — fonte única de verdade para
  # qual conta o link público `/agenda/:agenda_public_id` representa.
  def up
    add_reference :beclinic_user_profiles, :account, null: true, foreign_key: true

    # Backfill: cada profile herda a PRIMEIRA conta a que o user está vinculado.
    # Mantém comportamento atual (`@user.accounts.first`) — então qualquer profile
    # que hoje funciona em produção continua resolvendo a mesma conta. A diferença
    # é que a escolha vira persistente e explícita, e pode ser corrigida via
    # UPDATE direto se vier a haver caso multi-conta no futuro.
    execute <<~SQL.squish
      UPDATE beclinic_user_profiles p
         SET account_id = au.account_id
        FROM (
          SELECT DISTINCT ON (user_id) user_id, account_id
            FROM account_users
        ORDER BY user_id, id ASC
        ) au
       WHERE au.user_id = p.user_id
         AND p.account_id IS NULL
    SQL

    # Profiles órfãos (user sem nenhum account_user) não podem ser usados pelo
    # link público — sem conta não há agenda. Removidos no backfill em vez de
    # carregar lixo permanente; se o user voltar a ser vinculado a uma conta,
    # o callback `ensure_agenda_public_id` (plugins/agenda/lib/agenda/engine.rb)
    # recria o profile com `account_id` correto.
    execute <<~SQL.squish
      DELETE FROM beclinic_user_profiles WHERE account_id IS NULL
    SQL

    change_column_null :beclinic_user_profiles, :account_id, false

    # Garante 1 profile por (user, conta) — futuramente um user em N contas
    # terá N profiles, cada um com seu próprio `agenda_public_id`.
    add_index :beclinic_user_profiles, [:user_id, :account_id], unique: true,
              name: 'index_beclinic_user_profiles_on_user_and_account'
  end

  def down
    remove_index :beclinic_user_profiles, name: 'index_beclinic_user_profiles_on_user_and_account'
    remove_reference :beclinic_user_profiles, :account, foreign_key: true
  end
end
