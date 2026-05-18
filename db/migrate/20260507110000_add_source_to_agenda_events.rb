class AddSourceToAgendaEvents < ActiveRecord::Migration[7.1]
  def change
    # Origem do evento — preservar pra que regras de follow-up possam
    # filtrar "só se a Bea agendou", "só se humano agendou", ou ambos.
    # Eventos antigos ficam como 'manual' por default (via NOT NULL).
    add_column :agenda_events, :source, :string, null: false, default: 'manual'
    add_index :agenda_events, %i[account_id source], name: 'index_agenda_events_on_account_and_source'
  end
end
