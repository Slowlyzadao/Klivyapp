module InternalChat
  class Membership < ApplicationRecord
    self.table_name = 'internal_chat_memberships'

    ROLES = %w[owner admin member].freeze

    belongs_to :room, class_name: 'InternalChat::Room', foreign_key: :room_id
    belongs_to :user, optional: true

    validates :role, presence: true, inclusion: { in: ROLES }
    validate  :exactly_one_member

    scope :active, -> { where(left_at: nil) }
    scope :for_user, ->(user) { where(user_id: user.id) }

    def unread_count
      base = room.messages.where('id > COALESCE(?, 0)', last_read_message_id || 0)
      base = base.where.not(sender_user_id: user_id) if user_id.present?
      base.count
    end

    private

    def exactly_one_member
      return if user_id.present? ^ ai_agent_id.present?

      errors.add(:base, 'membership requires exactly one of user_id or ai_agent_id')
    end
  end
end
