class DropExamFolderDataFromPatients < ActiveRecord::Migration[7.1]
  # Remove o JSONB que era usado como source-of-truth temporário das pastas.
  # A verdade agora vive em `exam_folders` (modelo relacional) + `exam_medias.exam_folder_id`.
  # Seguro porque o módulo está em fase de testes (sem arquivos reais de pacientes).
  def up
    remove_column :patients, :exam_folder_data
  end

  def down
    add_column :patients, :exam_folder_data, :jsonb, default: {}
  end
end
