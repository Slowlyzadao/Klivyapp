module InternalChat
  class MessageFavorite < ApplicationRecord
    self.table_name = 'internal_chat_message_favorites'

    belongs_to :user
    belongs_to :account
    belongs_to :message, class_name: 'InternalChat::Message'

    validates :user_id, uniqueness: { scope: :message_id }
    validate  :denormalized_fields_match_message

    private

    # MT-13 (auditoria 2026-05-18): `account_id` e `room_id` denormalizados
    # por performance. Cliente craftado pode tentar gravar com room/account
    # de outra sala — corrompe agregados (lista de favoritos por sala vira
    # ghost). Validação fail-fast em qualquer divergência.
    def denormalized_fields_match_message
      return if message.nil?

      expected_room_id = message.room_id
      expected_account_id = message.room.account_id

      errors.add(:room_id, 'must match message.room_id') if room_id != expected_room_id
      errors.add(:account_id, 'must match message.room.account_id') if account_id != expected_account_id
    end
  end
end
