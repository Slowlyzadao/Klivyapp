class CreateAiAgentDocuments < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_documents do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.string :name, null: false
      t.string :source_type, null: false, default: 'pdf'
      t.string :external_link
      t.integer :status, null: false, default: 0
      t.text :error_message
      t.string :checksum
      t.integer :char_count, default: 0
      t.integer :parent_chunk_count, default: 0
      t.integer :child_chunk_count, default: 0
      t.datetime :processed_at
      t.timestamps
    end

    add_index :ai_agent_documents, :status
    add_index :ai_agent_documents, [:account_id, :checksum]
  end
end
