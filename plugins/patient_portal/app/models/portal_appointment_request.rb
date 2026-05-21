# Pedido de agendamento feito pelo paciente. Fila aguardando confirmação da
# clínica (PRD §7). Não bate diretamente em `AgendaEvent` — a recepção cria o
# evento e linka via `agenda_event_id` quando aprova.
class PortalAppointmentRequest < ApplicationRecord
  self.table_name = 'portal_appointment_requests'

  STATUSES = %w[pending approved rejected scheduled cancelled].freeze
  PERIODS  = %w[morning afternoon evening].freeze

  belongs_to :account
  belongs_to :patient
  belongs_to :preferred_professional, class_name: 'User',          optional: true
  belongs_to :preferred_service,      class_name: 'AgendaService', optional: true
  belongs_to :processed_by,           class_name: 'User',          optional: true
  belongs_to :agenda_event,                                        optional: true

  validates :status,         inclusion: { in: STATUSES }
  validates :preferred_period, inclusion: { in: PERIODS }, allow_blank: true
  validate  :validate_preferred_dates

  scope :pending,    -> { where(status: 'pending') }
  scope :resolved,   -> { where(status: %w[approved rejected scheduled cancelled]) }
  scope :for_patient, ->(id) { where(patient_id: id) }
  scope :recent_first, -> { order(created_at: :desc) }

  def pending?   = status == 'pending'
  def cancelable_by_patient? = pending?

  private

  # Limita o array a no máximo 3 datas válidas. Não tentamos parsear para
  # Time aqui — o controller que envia já valida formato e a tela é controlada.
  def validate_preferred_dates
    return if preferred_dates.blank?

    unless preferred_dates.is_a?(Array)
      errors.add(:preferred_dates, 'deve ser uma lista')
      return
    end
    errors.add(:preferred_dates, 'máximo 3 sugestões') if preferred_dates.length > 3
  end
end
