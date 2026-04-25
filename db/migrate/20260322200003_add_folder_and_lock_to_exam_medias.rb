class AddFolderAndLockToExamMedias < ActiveRecord::Migration[7.1]
  def change
    # Exam folders — hierarchical folder structure per patient
    create_table :exam_folders do |t|
      t.bigint :patient_id, null: false
      t.bigint :account_id, null: false
      t.string :name, null: false
      t.string :color, default: '#60a5fa'
      t.bigint :parent_id
      t.integer :position, default: 0, null: false
      t.timestamps
    end

    add_index :exam_folders, [:patient_id, :position], name: 'idx_exam_folders_patient_position'
    add_index :exam_folders, :account_id
    add_index :exam_folders, :parent_id

    # Add folder_id and locked flag to exam_medias
    add_column :exam_medias, :exam_folder_id, :bigint
    add_column :exam_medias, :locked, :boolean, default: false, null: false

    add_index :exam_medias, :exam_folder_id
  end
end
