class AddPartialIndexOnAgendaEventsKept < ActiveRecord::Migration[7.0]
  # Auditoria agendamento público (item 9.16): `calculate_slots` faz query
  # EXISTS por slot:
  #   `agenda_events.kept.where(user_id:).where('starts_at < ? AND ends_at > ?')`
  # 48 slots/dia × N dias = muitas queries. Índice composto cobrindo
  # `(account_id, user_id, starts_at)` parcial em `deleted_at IS NULL` casa
  # exatamente com o scope `kept` e elimina sequential scan.
  #
  # Também acelera a query do admin (`AgendaEventsController#index` com
  # filtro de range por user) e qualquer outro consumidor que filtre por
  # profissional + período.
  #
  # CONCURRENTLY: `agenda_events` está sob tráfego — criar índice sem trava
  # de write. Requer `disable_ddl_transaction!`.

  disable_ddl_transaction!

  def up
    return if index_exists?(:agenda_events, [:account_id, :user_id, :starts_at],
                            name: 'index_agenda_events_kept_on_account_user_starts_at')

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS
        index_agenda_events_kept_on_account_user_starts_at
      ON agenda_events (account_id, user_id, starts_at)
      WHERE deleted_at IS NULL
    SQL
  end

  def down
    execute <<~SQL.squish
      DROP INDEX CONCURRENTLY IF EXISTS index_agenda_events_kept_on_account_user_starts_at
    SQL
  end
end
