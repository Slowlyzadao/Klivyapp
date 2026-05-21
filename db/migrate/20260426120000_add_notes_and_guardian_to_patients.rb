class AddNotesAndGuardianToPatients < ActiveRecord::Migration[7.1]
  def change
    add_column :patients, :notes, :text
    add_column :patients, :has_guardian, :boolean, default: false, null: false
    add_column :patients, :guardian, :jsonb, default: {}, null: false
  end
end
