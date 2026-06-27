module InternalChat
  class Attachment < ApplicationRecord
    include Rails.application.routes.url_helpers

    self.table_name = 'internal_chat_attachments'

    FILE_TYPES = %w[image audio video file].freeze
    MAX_SIZE_BYTES = 40.megabytes
    ACCEPTABLE_DOC_TYPES = %w[
      text/csv text/plain text/rtf
      application/json application/pdf
      application/zip application/x-7z-compressed application/vnd.rar application/x-tar
      application/msword application/vnd.ms-excel application/vnd.ms-powerpoint application/rtf
      application/vnd.oasis.opendocument.text
      application/vnd.openxmlformats-officedocument.presentationml.presentation
      application/vnd.openxmlformats-officedocument.spreadsheetml.sheet
      application/vnd.openxmlformats-officedocument.wordprocessingml.document
    ].freeze

    belongs_to :message,
               class_name: 'InternalChat::Message',
               foreign_key: :message_id,
               inverse_of: :attachments
    has_one_attached :file

    validates :file_type, presence: true, inclusion: { in: FILE_TYPES }
    validate  :acceptable_file

    # BE-16 (auditoria 2026-05-18): URLs de blobs SEMPRE passam por
    # SecureBlobsController. Antes (`url_for(file)` / `file.blob.url`) o link
    # era um signed URL do storage backend (S3/R2) que validava só assinatura
    # — quem vazasse o link tinha acesso, inclusive user de OUTRA conta.
    # Agora o token carrega `account_id` e o controller valida que o user
    # logado pertence à conta dona do blob antes de redirecionar (janela 30s
    # no storage como defense-in-depth).
    #
    # Reusa Patients::SecureBlobTokenService — nome do namespace é histórico
    # (deveria migrar pra beclinic_core num refactor futuro), mas o service
    # já é genérico (recebe blob_id + account_id).
    FILE_URL_TTL = 1.hour
    THUMB_RESIZE = { resize_to_fill: [250, nil] }.freeze

    def file_url
      build_secure_url(file)
    end

    def download_url
      # Mesma URL do file_url. O AttachmentsController#download trata
      # disposition via conversion server-side (WebP → JPG/PNG) ou redirect
      # depois do guard. O TTL é o mesmo: 1h é folga pra UX de download.
      build_secure_url(file)
    end

    def thumb_url
      return '' unless file.attached? && file_type == 'image'
      return '' unless file.variable?

      build_secure_url(file, transformations: THUMB_RESIZE)
    rescue ActiveStorage::UnrepresentableError, StandardError
      # Fallback transparente quando o variant pifa (ImageMagick ausente,
      # imagem corrompida, libvips quebrada). O frontend cai no file_url.
      ''
    end

    def self.classify(content_type)
      return 'file' if content_type.blank?

      case content_type
      when %r{^image/} then 'image'
      when %r{^audio/} then 'audio'
      when %r{^video/} then 'video'
      else 'file'
      end
    end

    private

    def build_secure_url(attached, transformations: nil)
      return '' unless attached&.attached?

      account_id = message&.room&.account_id
      return '' if account_id.blank? # sem conta = sem URL servível

      token = ::Patients::SecureBlobTokenService.encode(
        blob_id: attached.blob.id,
        account_id: account_id,
        expires_in: FILE_URL_TTL,
        transformations: transformations
      )
      Rails.application.routes.url_helpers.secure_blob_url(token: token)
    rescue StandardError
      ''
    end

    def acceptable_file
      return unless file.attached?

      if file.blob.byte_size > MAX_SIZE_BYTES
        errors.add(:file, "excede #{MAX_SIZE_BYTES / 1.megabyte} MB")
      end

      ct = file.blob.content_type
      return if ct.blank?
      return if ct.start_with?('image/', 'audio/', 'video/')
      return if ACCEPTABLE_DOC_TYPES.include?(ct)

      errors.add(:file, "tipo não permitido (#{ct})")
    end
  end
end
