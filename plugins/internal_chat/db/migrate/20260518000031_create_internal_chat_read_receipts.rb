class CreateInternalChatReadReceipts < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_read_receipts do |t|
      t.references :message,
                   null: false,
                   foreign_key: { to_table: :internal_chat_messages, on_delete: :cascade },
                   index: false
      t.bigint  :user_id, null: false
      t.datetime :read_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
      t.timestamps
    end

    add_index :internal_chat_read_receipts, [:message_id, :user_id], unique: true
    add_index :internal_chat_read_receipts, :user_id
  end
end
