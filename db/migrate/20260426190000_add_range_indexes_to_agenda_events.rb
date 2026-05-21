class AddRangeIndexesToAgendaEvents < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :agenda_events,
              [:account_id, :starts_at],
              name: 'index_agenda_events_on_account_and_starts_at',
              algorithm: :concurrently,
              if_not_exists: true

    add_index :agenda_events,
              [:account_id, :user_id, :starts_at],
              name: 'index_agenda_events_on_account_user_starts_at',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
