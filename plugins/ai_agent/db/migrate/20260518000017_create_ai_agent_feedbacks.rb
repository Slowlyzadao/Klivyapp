class CreateAiAgentFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_feedbacks do |t|
      t.references :account, null: false, foreign_key: { to_table: :accounts }
      t.references :trace, null: true,
                           foreign_key: { to_table: :ai_agent_traces },
                           index: true
      t.bigint :conversation_id
      t.bigint :message_id
      t.bigint :contact_id

      t.integer :rating, null: false   # +1 (thumbs up) | -1 (thumbs down)
      t.text :comment

      t.timestamps
    end

    add_index :ai_agent_feedbacks, [:account_id, :created_at]
    add_index :ai_agent_feedbacks, :rating
  end
end
