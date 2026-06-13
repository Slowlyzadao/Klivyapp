class CreateAiAgentParentChunks < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_parent_chunks do |t|
      t.references :document, null: false,
                              foreign_key: { to_table: :ai_agent_documents },
                              index: true
      t.integer :position, null: false
      t.text :content, null: false
      t.integer :char_count, null: false, default: 0
      t.timestamps
    end

    add_index :ai_agent_parent_chunks, [:document_id, :position], unique: true
  end
end
