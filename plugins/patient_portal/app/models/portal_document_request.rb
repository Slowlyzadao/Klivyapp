# Pedido de documento (2ª via ou novo tipo) feito pelo paciente (PRD §8).
class PortalDocumentRequest < ApplicationRecord
  self.table_name = 'portal_document_requests'

  STATUSES = %w[pending approved rejected fulfilled cancelled].freeze

  belongs_to :account
  belongs_to :patient
  belongs_to :source_document,     class_name: 'Document', optional: true
  belongs_to :fulfilled_document,  class_name: 'Document', optional: true
  belongs_to :processed_by,        class_name: 'User',     optional: true

  validates :reason, presence: true, length: { maximum: 1000 }
  validates :status, inclusion: { in: STATUSES }
  validate  :source_or_type_present
  validates :document_type, inclusion: { in: Document::DOCUMENT_TYPES }, allow_blank: true

  scope :pending,    -> { where(status: 'pending') }
  scope :resolved,   -> { where(status: %w[approved rejected fulfilled cancelled]) }
  scope :for_patient, ->(id) { where(patient_id: id) }
  scope :recent_first, -> { order(created_at: :desc) }

  def pending?  = status == 'pending'
  def cancelable_by_patient? = pending?

  private

  def source_or_type_present
    return if source_document_id.present? || document_type.present?

    errors.add(:base, 'informe o documento de origem ou o tipo desejado')
  end
end
