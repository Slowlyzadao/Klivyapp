class CreateInternalChatMentions < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_mentions do |t|
      t.references :message,
                   null: false,
                   foreign_key: { to_table: :internal_chat_messages, on_delete: :cascade },
                   index: true
      t.bigint  :user_id, null: false
      t.bigint  :account_id, null: false
      t.datetime :read_at
      t.timestamps
    end

    add_index :internal_chat_mentions, [:message_id, :user_id], unique: true
    add_index :internal_chat_mentions, [:account_id, :user_id, :read_at]
  end
end
