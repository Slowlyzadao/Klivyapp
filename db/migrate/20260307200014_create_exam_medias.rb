class CreateExamMedias < ActiveRecord::Migration[7.0]
  def change
    create_table :exam_medias do |t|
      t.bigint  :patient_id,     null: false
      t.bigint  :account_id,     null: false
      t.bigint  :uploaded_by_id                        # user que fez upload
      t.bigint  :session_log_id                        # contexto opcional (sessão)
      t.bigint  :appointment_id                        # contexto opcional (agendamento)

      t.string  :category,       null: false           # enum: rx/tomografia/foto_clinica/etc
      t.string  :file_name
      t.string  :mime_type
      t.bigint  :file_size                             # em bytes
      t.text    :description
      t.string  :tags,           default: [],          array: true   # tags livres para busca

      t.datetime :deleted_at                           # soft delete OBRIGATÓRIO

      t.timestamps
    end

    add_index :exam_medias, :patient_id
    add_index :exam_medias, :account_id
    add_index :exam_medias, :session_log_id
    add_index :exam_medias, :appointment_id
    add_index :exam_medias, :category
    add_index :exam_medias, :deleted_at
    add_index :exam_medias, [:patient_id, :category]
  end
end
