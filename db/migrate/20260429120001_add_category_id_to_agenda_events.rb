class AddCategoryIdToAgendaEvents < ActiveRecord::Migration[7.1]
  def change
    add_reference :agenda_events,
                  :category,
                  null: true,
                  foreign_key: { to_table: :agenda_categories },
                  index: true
  end
end
