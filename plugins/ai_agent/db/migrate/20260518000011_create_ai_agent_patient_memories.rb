class CreateAiAgentPatientMemories < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_patient_memories do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.bigint :contact_id, null: false
      t.jsonb :preferences, null: false, default: {}
      t.jsonb :history, null: false, default: []
      t.text :notes
      t.timestamps
    end

    add_index :ai_agent_patient_memories, [:account_id, :contact_id], unique: true, name: 'idx_ai_agent_memory_on_account_contact'
  end
end
