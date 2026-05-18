class AddDefaultCategoryToAgendaServices < ActiveRecord::Migration[7.1]
  def change
    add_reference :agenda_services, :default_category,
                  null: true,
                  index: true,
                  foreign_key: { to_table: :agenda_categories, on_delete: :nullify }
  end
end
