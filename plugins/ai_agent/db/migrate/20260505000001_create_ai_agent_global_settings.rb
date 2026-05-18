class CreateAiAgentGlobalSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_global_settings do |t|
      t.string :chat_provider, null: false, default: 'openai'
      t.string :chat_model
      t.integer :max_tokens_per_conversation, null: false, default: 4096
      t.integer :max_monthly_cost_per_account_cents, null: false, default: 0
      t.bigint :default_persona_id
      t.boolean :enabled_by_default_for_new_accounts, null: false, default: false
      t.jsonb :guardrails, null: false, default: {}
      t.jsonb :telemetry_config, null: false, default: {}
      t.timestamps
    end

    add_index :ai_agent_global_settings, :default_persona_id
  end
end
