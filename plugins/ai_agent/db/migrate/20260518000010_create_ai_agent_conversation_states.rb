class CreateAiAgentConversationStates < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_conversation_states do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.bigint :conversation_id, null: false
      t.string :status, null: false, default: 'active'
      t.string :last_intent
      t.text :summary
      t.jsonb :working_memory, null: false, default: {}
      t.datetime :last_message_at
      t.timestamps
    end

    add_index :ai_agent_conversation_states, [:account_id, :conversation_id], unique: true, name: 'idx_ai_agent_state_on_account_conv'
    add_index :ai_agent_conversation_states, :status
  end
end
