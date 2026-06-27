class CreateInternalChatAttachments < ActiveRecord::Migration[7.1]
  def change
    create_table :internal_chat_attachments do |t|
      t.references :message,
                   null: false,
                   foreign_key: { to_table: :internal_chat_messages, on_delete: :cascade },
                   index: true
      t.string  :file_type, null: false, default: 'file' # image | audio | video | file
      t.string  :file_name
      t.string  :content_type
      t.bigint  :file_size
      t.jsonb   :meta, null: false, default: {}
      t.timestamps
    end
  end
end
