# == Schema Information
#
# Table name: patient_appointments
#
#  id                  :bigint           not null, primary key
#  account_id          :bigint           not null
#  patient_id          :bigint           not null
#  professional_id     :bigint
#  agenda_event_id     :bigint
#  appointment_type    :string           default("avaliacao")
#  status              :string           default("scheduled")
#  scheduled_at        :datetime         not null
#  ends_at             :datetime
#  duration_minutes    :integer          default(60)
#  cancellation_reason :string
#  reschedule_reason   :string
#  notes               :text
#  recall_sent         :boolean          default(false)
#  recall_sent_at      :datetime
#  return_in_days      :integer
#  session_log_id      :bigint
#  treatment_plan_id   :bigint
#  deleted_at          :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

class PatientAppointment < ApplicationRecord
  # ─── Soft Delete ──────────────────────────────────────────────────────────────
  scope :active,   -> { where(deleted_at: nil) }
  scope :deleted,  -> { where.not(deleted_at: nil) }

  # ─── Associations ─────────────────────────────────────────────────────────────
  belongs_to :account
  belongs_to :patient
  belongs_to :professional, class_name: 'User', optional: true
  belongs_to :agenda_event,    optional: true
  belongs_to :session_log,     class_name: 'SessionLog',     optional: true
  belongs_to :treatment_plan,  class_name: 'TreatmentPlan',  optional: true

  # ─── Enums ────────────────────────────────────────────────────────────────────
  APPOINTMENT_TYPES = %w[avaliacao retorno procedimento revisao emergencia].freeze
  STATUSES = %w[scheduled confirmed arrived in_progress done no_show canceled rescheduled].freeze

  validates :appointment_type, inclusion: { in: APPOINTMENT_TYPES }
  validates :status, inclusion: { in: STATUSES }

  # ─── Validations ──────────────────────────────────────────────────────────────
  validates :account,      presence: true
  validates :patient,      presence: true
  validates :scheduled_at, presence: true

  validate :ends_at_after_scheduled_at, if: -> { ends_at.present? }

  # ─── Scopes ───────────────────────────────────────────────────────────────────
  scope :upcoming,     -> { active.where('scheduled_at > ?', Time.current).order(:scheduled_at) }
  scope :past,         -> { active.where('scheduled_at <= ?', Time.current).order(scheduled_at: :desc) }
  scope :by_status,    ->(s) { active.where(status: s) }
  scope :no_shows,     -> { active.where(status: 'no_show') }
  scope :done,         -> { active.where(status: 'done') }
  scope :scheduled,    -> { active.where(status: %w[scheduled confirmed arrived]) }
  scope :needs_recall, -> { active.no_shows.where(recall_sent: false) }

  # ─── Callbacks ────────────────────────────────────────────────────────────────
  before_save :compute_ends_at

  # ─── Instance Methods ─────────────────────────────────────────────────────────
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def upcoming?
    scheduled_at > Time.current
  end

  def past?
    scheduled_at <= Time.current
  end

  def cancellable?
    %w[scheduled confirmed arrived].include?(status)
  end

  def reschedulable?
    %w[scheduled confirmed].include?(status)
  end

  def mark_no_show!
    update!(status: 'no_show')
    # Incrementa o contador de faltas no patient
    patient.increment!(:no_show_count)
    # Se o paciente atingiu 3 faltas, marca como faltoso
    check_faltoso_threshold!
  end

  def mark_done!
    update!(status: 'done')
  end

  private

  def compute_ends_at
    return if ends_at.present?
    return if scheduled_at.blank?

    self.ends_at = scheduled_at + (duration_minutes || 60).minutes
  end

  def ends_at_after_scheduled_at
    return if ends_at > scheduled_at

    errors.add(:ends_at, 'deve ser posterior ao horário de início')
  end

  def check_faltoso_threshold!(threshold: 3)
    return unless patient.no_show_count >= threshold
    return if patient.patient_status_faltoso?

    patient.update(patient_status: 'faltoso')
  end
end
