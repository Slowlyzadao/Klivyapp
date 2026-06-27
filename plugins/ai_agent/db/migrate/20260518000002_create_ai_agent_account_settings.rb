class CreateAiAgentAccountSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_account_settings do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }, index: { unique: true }
      t.boolean :enabled, null: false, default: false
      t.string :chat_model
      t.integer :monthly_token_budget
      t.integer :max_tokens_per_conversation
      t.bigint :persona_id
      t.jsonb :enabled_tools, null: false, default: []
      t.text :system_prompt_prefix
      t.timestamps
    end

    add_index :ai_agent_account_settings, :persona_id
  end
end
