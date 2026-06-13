module InternalChat
  # ARCH-14 (audit 2026-05-19): tabela e model RESERVADOS pra futura
  # granularização (recibo por mensagem, estilo "Visto às 14:32 por Maria
  # no balão #123"). HOJE não é usada — `InternalChat::Membership#last_read_message_id`
  # é o canônico de read tracking (cursor por sala, broadcast em
  # `internal_chat.read_receipt.updated`).
  #
  # Mantida com associação `Message#has_many :read_receipts, dependent: :destroy`
  # pra que, se futuramente passarmos a inserir registros, deletes em
  # cascade já funcionem sem migration extra.
  #
  # Documentado em `docs/01-product/modules/PRD-chat-interno.md:180`.
  # NÃO ADICIONE writes neste model sem alinhar com o PRD primeiro.
  class ReadReceipt < ApplicationRecord
    self.table_name = 'internal_chat_read_receipts'

    belongs_to :message, class_name: 'InternalChat::Message', foreign_key: :message_id
    belongs_to :user

    validates :user_id, uniqueness: { scope: :message_id }
  end
end
