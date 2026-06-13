class CreateAiAgentChildChunks < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_child_chunks do |t|
      t.references :parent_chunk, null: false,
                                  foreign_key: { to_table: :ai_agent_parent_chunks },
                                  index: true
      t.references :document, null: false,
                              foreign_key: { to_table: :ai_agent_documents },
                              index: true
      t.references :account, null: false,
                             foreign_key: { to_table: :accounts },
                             index: true
      t.integer :position, null: false
      t.text :content, null: false
      t.column :embedding, 'vector(1536)'
      t.integer :char_count, null: false, default: 0
      t.timestamps
    end

    add_index :ai_agent_child_chunks, [:parent_chunk_id, :position], unique: true

    # IVFFlat index for cosine similarity search. Lists tuned for ~100k rows;
    # rebuild with higher `lists` once corpus grows past 1M chunks.
    execute <<~SQL.squish
      CREATE INDEX ai_agent_child_chunks_embedding_idx
      ON ai_agent_child_chunks
      USING ivfflat (embedding vector_cosine_ops)
      WITH (lists = 100)
    SQL
  end
end
