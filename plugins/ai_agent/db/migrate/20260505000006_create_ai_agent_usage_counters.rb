class CreateAiAgentUsageCounters < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_usage_counters do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.date :date, null: false
      t.bigint :input_tokens, null: false, default: 0
      t.bigint :output_tokens, null: false, default: 0
      t.integer :cost_cents, null: false, default: 0
      t.integer :conversations_count, null: false, default: 0
      t.integer :tool_calls_count, null: false, default: 0
      t.timestamps
    end

    add_index :ai_agent_usage_counters, [:account_id, :date], unique: true
    add_index :ai_agent_usage_counters, :date
  end
end
