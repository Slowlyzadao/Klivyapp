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

    def file_url
      file.attached? ? url_for(file) : ''
    end

    def download_url
      return '' unless file.attached?

      ActiveStorage::Current.url_options ||= Rails.application.routes.default_url_options
      file.blob.url
    end

    def thumb_url
      return '' unless file.attached? && file_type == 'image'

      url_for(file.representation(resize_to_fill: [250, nil]))
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
