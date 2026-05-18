module InternalChat
  class Message < ApplicationRecord
    self.table_name = 'internal_chat_messages'

    CONTENT_TYPES = %w[text image audio video file system sticker].freeze

    belongs_to :room, class_name: 'InternalChat::Room', foreign_key: :room_id
    belongs_to :sender, class_name: 'User', foreign_key: :sender_user_id, optional: true
    belongs_to :sticker, class_name: 'InternalChat::Sticker', optional: true

    has_many :read_receipts,
             class_name: 'InternalChat::ReadReceipt',
             foreign_key: :message_id,
             dependent: :destroy
    has_many :attachments,
             class_name: 'InternalChat::Attachment',
             foreign_key: :message_id,
             inverse_of: :message,
             autosave: true,
             dependent: :destroy
    has_many :mentions,
             class_name: 'InternalChat::Mention',
             foreign_key: :message_id,
             inverse_of: :message,
             dependent: :destroy
    has_many :favorites,
             class_name: 'InternalChat::MessageFavorite',
             foreign_key: :message_id,
             dependent: :destroy
    has_many :reactions,
             class_name: 'InternalChat::MessageReaction',
             foreign_key: :message_id,
             dependent: :destroy

    validates :content_type, presence: true, inclusion: { in: CONTENT_TYPES }
    validate  :content_or_attachments_present, unless: :deleted_at?

    scope :visible, -> { where(deleted_at: nil) }
    scope :chronological, -> { order(:id) }

    def in_reply_to_id
      content_attributes['in_reply_to']
    end

    def soft_delete!
      update!(deleted_at: Time.current, content: nil)
    end

    def system?
      content_type == 'system'
    end

    private

    def content_or_attachments_present
      return if content_type != 'text'
      return if content.present?
      return if attachments.any?
      return if sticker_id.present?

      errors.add(:base, 'mensagem precisa de conteúdo ou anexo')
    end
  end
end
