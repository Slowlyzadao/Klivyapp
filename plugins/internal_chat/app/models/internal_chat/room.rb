module InternalChat
  class Room < ApplicationRecord
    include Rails.application.routes.url_helpers

    self.table_name = 'internal_chat_rooms'

    KINDS = %w[direct group].freeze
    AVATAR_MAX_BYTES = 5.megabytes
    AVATAR_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze

    belongs_to :account
    belongs_to :created_by_user, class_name: 'User', optional: true

    has_many :memberships,
             class_name: 'InternalChat::Membership',
             foreign_key: :room_id,
             dependent: :destroy
    has_many :user_members, through: :memberships, source: :user
    has_many :messages,
             class_name: 'InternalChat::Message',
             foreign_key: :room_id,
             dependent: :destroy
    # Avatar (imagem do grupo) via ActiveStorage. Mantém a coluna string
    # `avatar_url` como fallback se ninguém tiver feito upload ainda.
    has_one_attached :avatar
    validate :avatar_acceptable, if: -> { avatar.attached? && avatar.changed? }

    validates :kind, presence: true, inclusion: { in: KINDS }
    validates :name, presence: true, if: -> { kind == 'group' }

    scope :not_archived, -> { where(archived_at: nil) }
    scope :recent, lambda {
      order(Arel.sql('COALESCE(internal_chat_rooms.last_message_at, internal_chat_rooms.created_at) DESC'))
    }

    def direct?
      kind == 'direct'
    end

    def group?
      kind == 'group'
    end

    def member?(user)
      memberships.where(user_id: user.id, left_at: nil).exists?
    end

    def display_name_for(user)
      return name if group?

      other = user_members.where.not(id: user.id).first
      other&.available_name || 'Conversa'
    end

    def touch_last_message!(at = Time.current)
      update_column(:last_message_at, at) # rubocop:disable Rails/SkipsModelValidations
    end

    # Override para preferir o blob anexado (ActiveStorage) à coluna string.
    def avatar_url
      return url_for(avatar) if avatar.attached?

      read_attribute(:avatar_url)
    end

    private

    def avatar_acceptable
      errors.add(:avatar, 'excede 5MB') if avatar.byte_size > AVATAR_MAX_BYTES
      errors.add(:avatar, 'tipo não suportado') unless AVATAR_TYPES.include?(avatar.content_type)
    end
  end
end
