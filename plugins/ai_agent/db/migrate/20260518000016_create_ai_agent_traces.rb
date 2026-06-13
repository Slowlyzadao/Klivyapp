class CreateAiAgentTraces < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_traces do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.bigint :conversation_id
      t.bigint :message_id
      t.bigint :contact_id

      t.string :model
      t.string :provider

      t.integer :latency_ms
      t.bigint :input_tokens, default: 0
      t.bigint :output_tokens, default: 0
      t.integer :cost_cents, default: 0

      t.jsonb :tool_calls, null: false, default: []
      t.string :sentiment_label
      t.decimal :sentiment_score, precision: 4, scale: 3

      t.boolean :escalated, null: false, default: false
      t.string :escalation_reason
      t.jsonb :guardrail_violations, null: false, default: []

      t.boolean :short_circuited, null: false, default: false
      t.text :error_message

      t.datetime :created_at, null: false
    end

    add_index :ai_agent_traces, :conversation_id
    add_index :ai_agent_traces, :message_id
    add_index :ai_agent_traces, [:account_id, :created_at]
    add_index :ai_agent_traces, :escalated
  end
end
