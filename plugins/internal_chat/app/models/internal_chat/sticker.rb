module InternalChat
  class Sticker < ApplicationRecord
    include Rails.application.routes.url_helpers

    self.table_name = 'internal_chat_stickers'

    KINDS = %w[account default].freeze
    # Categorias para figurinhas padrão da Klivy. NULL para figurinhas criadas
    # pelas clínicas (não são categorizadas).
    CATEGORIES = %w[dentista bem_estar estetica].freeze
    # Após processamento client-side: WebP 512x512 fica em torno de 30-100KB.
    # 300KB cobre stickers PNG/GIF mais pesados sem virar tijolo no banco.
    MAX_BYTES = 300.kilobytes
    ALLOWED_TYPES = %w[image/webp image/png image/gif].freeze

    # Defaults da Klivy têm account_id NULL (visíveis a todas as contas).
    belongs_to :account, optional: true
    belongs_to :created_by_user, class_name: 'User', optional: true

    has_one_attached :image
    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :category, inclusion: { in: CATEGORIES, allow_nil: true }
    validate :image_acceptable, if: -> { image.attached? && image.changed? }

    has_many :favorites,
             class_name: 'InternalChat::StickerFavorite',
             foreign_key: :sticker_id,
             dependent: :destroy

    scope :for_account, ->(account_id) { where(account_id: account_id) }
    scope :recent, -> { order(created_at: :desc) }

    # BE-16: serve via SecureBlobsController. Defaults (account_id NULL) usam
    # Current.account.id no token — qualquer conta logada pode visualizar
    # defaults, mas o link continua scoped pra evitar leak para anon/account
    # diferente. Stickers custom usam o próprio account_id.
    def image_url
      return nil unless image.attached?

      effective_account_id = account_id || ::Current.account&.id
      return nil if effective_account_id.blank?

      token = ::Patients::SecureBlobTokenService.encode(
        blob_id: image.blob.id,
        account_id: effective_account_id,
        expires_in: 1.hour
      )
      Rails.application.routes.url_helpers.secure_blob_url(token: token)
    rescue StandardError
      nil
    end

    def favorited_by?(user)
      favorites.exists?(user_id: user.id)
    end

    private

    def image_acceptable
      errors.add(:image, 'excede 300KB') if image.byte_size > MAX_BYTES
      errors.add(:image, 'tipo não suportado') unless ALLOWED_TYPES.include?(image.content_type)
    end
  end
end
