class AddExamFolderDataToPatients < ActiveRecord::Migration[7.0]
  def change
    add_column :patients, :exam_folder_data, :jsonb, default: {}
  end
end
