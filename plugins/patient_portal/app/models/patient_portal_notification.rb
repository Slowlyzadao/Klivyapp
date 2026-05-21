# Notificação in-app do paciente. Stub de Sprints A-D só servia 0 — agora
# alimentada por `PatientPortal::NotificationDispatcher` chamado dos outros
# fluxos (Sprint C/D).
class PatientPortalNotification < ApplicationRecord
  self.table_name = 'patient_portal_notifications'

  KINDS = %w[
    appointment_confirmed
    appointment_canceled
    appointment_reminder
    document_ready
    consent_pending
    consent_signed
    recall
    message_received
    financial_charge
    financial_overdue
    generic
  ].freeze

  belongs_to :account
  belongs_to :patient

  validates :kind,  inclusion: { in: KINDS }
  validates :title, presence: true, length: { maximum: 200 }
  validates :body,  length: { maximum: 1000 }, allow_blank: true

  scope :unread,        -> { where(read_at: nil) }
  scope :recent_first,  -> { order(created_at: :desc) }
  scope :for_patient,   ->(id) { where(patient_id: id) }

  def read?  = read_at.present?
  def unread? = read_at.nil?

  def mark_read!
    update!(read_at: Time.current) if unread?
  end
end
