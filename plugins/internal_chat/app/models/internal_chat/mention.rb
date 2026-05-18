module InternalChat
  class Mention < ApplicationRecord
    self.table_name = 'internal_chat_mentions'

    belongs_to :message,
               class_name: 'InternalChat::Message',
               foreign_key: :message_id,
               inverse_of: :mentions
    belongs_to :user, optional: true
    belongs_to :account

    validates :user_id, uniqueness: { scope: :message_id }, allow_nil: true
    validates :ai_agent_id, uniqueness: { scope: :message_id }, allow_nil: true
    validate  :exactly_one_target

    scope :unread, -> { where(read_at: nil) }
    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :for_ai_agent, ->(id) { where(ai_agent_id: id) }
    scope :recent, -> { order(created_at: :desc) }

    private

    def exactly_one_target
      return if user_id.present? ^ ai_agent_id.present?

      errors.add(:base, 'mention requires exactly one of user_id or ai_agent_id')
    end
  end
end
