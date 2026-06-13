module InternalChat
  class Message < ApplicationRecord
    self.table_name = 'internal_chat_messages'

    CONTENT_TYPES = %w[text image audio video file system sticker].freeze

    belongs_to :room, class_name: 'InternalChat::Room', foreign_key: :room_id
    belongs_to :sender, class_name: 'User', foreign_key: :sender_user_id, optional: true
    belongs_to :sticker, class_name: 'InternalChat::Sticker', optional: true

    # ARCH-14 (audit 2026-05-19): associação reservada — ReadReceipt hoje
    # não recebe writes (canon de read tracking é Membership.last_read_message_id).
    # Mantida pra que destroys cascateiem se a feature granular for ativada.
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

    # BE-17 (auditoria 2026-05-18): soft_delete agora também purga os blobs
    # dos attachments. Antes ficava no storage indefinidamente — paciente
    # apagava foto de receita médica mas o blob continuava acessível via
    # URL antiga até a Attachment row ser destruída por cascade (que só
    # acontece quando a Message é hard-deleted, raramente).
    #
    # Mantém as Attachment rows (apenas o blob é purgado) pra preservar
    # contagem no histórico e em métricas. UI já trata `deleted_at` no
    # parent: mostra "Mensagem apagada" sem renderizar attachments.
    #
    # `file.purge_later` é async via Sidekiq — não bloqueia o request do
    # user que está apagando. Em casos de Sidekiq down, blob fica até o
    # próximo restart processar a queue (BE-17 acaba sendo eventually
    # consistent, mas eventual).
    def soft_delete!
      ActiveRecord::Base.transaction do
        update!(deleted_at: Time.current, content: nil)
        attachments.find_each do |att|
          att.file.purge_later if att.file.attached?
        rescue StandardError => e
          # Não rollback do soft_delete por causa de falha de blob storage —
          # log + segue. O cron de cleanup futuro pega blobs órfãos.
          Rails.logger.warn(
            "[InternalChat::Message] purge attachment failed att=#{att.id} " \
            "msg=#{id}: #{e.class}: #{e.message}"
          )
        end
      end
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
