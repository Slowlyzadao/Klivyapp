class SessionLog < ApplicationRecord
  include TimelineTrackable

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :professional, class_name: 'User', optional: true
  belongs_to :treatment_plan, optional: true
  belongs_to :treatment_item, optional: true
  belongs_to :appointment, class_name: 'AgendaEvent', optional: true

  # Validations
  validates :account, presence: true
  validates :patient, presence: true
  validates :performed_at, presence: true
  validates :duration_minutes, numericality: { greater_than: 0, only_integer: true, allow_nil: true }
  validates :return_in_days, numericality: { greater_than: 0, only_integer: true, allow_nil: true }
  validate :return_in_days_requires_return_needed

  # Callbacks
  after_create :increment_treatment_item_sessions
  after_create :update_treatment_plan_status
  after_create_commit :record_timeline_session_performed

  # Scopes
  scope :by_patient, ->(patient_id) { where(patient_id: patient_id) }
  scope :recent, -> { order(performed_at: :desc) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  private

  def increment_treatment_item_sessions
    return unless treatment_item_id.present?

    # Job assíncrono para não travar o request
    Patients::IncrementTreatmentSessionJob.perform_later(treatment_item_id)
  end

  def update_treatment_plan_status
    return unless treatment_plan_id.present?

    Patients::UpdateTreatmentPlanStatusJob.perform_later(treatment_plan_id)
  end

  def return_in_days_requires_return_needed
    return unless return_in_days.present? && !return_needed?

    errors.add(:return_in_days, :requires_return_needed)
  end

  def record_timeline_session_performed
    item_name = treatment_item&.procedure_name || 'Procedimento'
    record_timeline_event!(
      event_type: 'session_performed',
      label: "Sessão realizada: #{item_name} (#{performed_at&.strftime('%d/%m/%Y')})",
      actor: professional,
      occurred_at: Time.current,
      metadata: {
        procedimento: item_name,
        duracao: duration_minutes.to_s,
        profissional: professional&.name.to_s,
        plano_id: treatment_plan_id.to_s
      }
    )
  end
end
