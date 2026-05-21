class AddSoftDeleteToAgendaEvents < ActiveRecord::Migration[7.0]
  def change
    add_column :agenda_events, :deleted_at, :datetime
    add_column :agenda_events, :deleted_by_id, :bigint
    add_column :agenda_events, :deletion_reason, :string
    add_column :agenda_events, :deletion_note, :text

    add_index :agenda_events, :deleted_at
    add_index :agenda_events, :deleted_by_id
  end
end
