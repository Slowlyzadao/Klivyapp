module InternalChat
  class ReadReceipt < ApplicationRecord
    self.table_name = 'internal_chat_read_receipts'

    belongs_to :message, class_name: 'InternalChat::Message', foreign_key: :message_id
    belongs_to :user

    validates :user_id, uniqueness: { scope: :message_id }
  end
end
