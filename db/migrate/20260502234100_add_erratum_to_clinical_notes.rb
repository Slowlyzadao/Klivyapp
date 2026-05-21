class AddErratumToClinicalNotes < ActiveRecord::Migration[7.0]
  def change
    add_column :clinical_notes, :erratum_at, :datetime
    add_column :clinical_notes, :erratum_by_id, :bigint
    add_column :clinical_notes, :erratum_reason, :text

    add_index :clinical_notes, :erratum_at
    add_index :clinical_notes, :erratum_by_id
  end
end
