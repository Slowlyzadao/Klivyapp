class AddAiAgentIdToInternalChatMentions < ActiveRecord::Migration[7.1]
  def change
    add_column :internal_chat_mentions, :ai_agent_id, :bigint
    add_index :internal_chat_mentions, [:account_id, :ai_agent_id, :read_at]

    # Antes: user_id era NOT NULL (definição original). Sprint 7 amplia para
    # AI: exatamente um de user_id OU ai_agent_id.
    change_column_null :internal_chat_mentions, :user_id, true

    execute <<~SQL.squish
      ALTER TABLE internal_chat_mentions
      ADD CONSTRAINT internal_chat_mentions_target_check
      CHECK ((user_id IS NOT NULL AND ai_agent_id IS NULL)
          OR (user_id IS NULL AND ai_agent_id IS NOT NULL))
    SQL
  end
end
