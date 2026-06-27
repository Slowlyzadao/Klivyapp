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
    validate  :account_matches_message_room

    scope :unread, -> { where(read_at: nil) }
    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :for_ai_agent, ->(id) { where(ai_agent_id: id) }
    scope :recent, -> { order(created_at: :desc) }

    private

    def exactly_one_target
      return if user_id.present? ^ ai_agent_id.present?

      errors.add(:base, 'mention requires exactly one of user_id or ai_agent_id')
    end

    # MT-12 (auditoria 2026-05-18): account_id é denormalizado por
    # performance (consulta por user inbox de mentions sem JOIN). Mas se
    # gravado fora-de-sync com message.room.account_id, mention some pra
    # quem deveria ver e aparece pra ninguém — corrompe inbox da feature.
    # Validação fail-fast em qualquer divergência.
    def account_matches_message_room
      return if message.nil?
      return if account_id == message.room.account_id

      errors.add(:account_id, 'must match message.room.account_id')
    end
  end
end
