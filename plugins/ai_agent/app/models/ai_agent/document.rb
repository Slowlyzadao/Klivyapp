class AiAgent::Document < ApplicationRecord
  self.table_name = 'ai_agent_documents'

  belongs_to :account
  has_many :parent_chunks,
           class_name: 'AiAgent::ParentChunk',
           dependent: :destroy
  has_many :child_chunks,
           class_name: 'AiAgent::ChildChunk',
           dependent: :destroy

  has_one_attached :pdf_file

  SOURCE_TYPES = %w[pdf text url].freeze

  enum :status, {
    pending: 0,
    processing: 1,
    processed: 2,
    failed: 3
  }

  MAX_PDF_SIZE = 20.megabytes

  validates :name, presence: true, length: { maximum: 255 }
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validate :validate_pdf_attachment
  validate :must_have_payload

  scope :ready, -> { where(status: :processed) }

  private

  def must_have_payload
    return if source_type == 'pdf' && pdf_file.attached?
    return if source_type == 'url' && external_link.present?
    return if source_type == 'text' && content.present?

    errors.add(:base, 'document must have a PDF attachment, an external link, or text content')
  end

  def validate_pdf_attachment
    return unless source_type == 'pdf' && pdf_file.attached?

    errors.add(:pdf_file, 'must be a PDF') unless pdf_file.content_type == 'application/pdf'
    errors.add(:pdf_file, "must be smaller than #{MAX_PDF_SIZE / 1.megabyte} MB") if pdf_file.byte_size > MAX_PDF_SIZE
  end
end
