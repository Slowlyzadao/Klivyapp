# == Schema Information
#
# Table name: anamneses
#
# id                :bigint   not null, primary key
# patient_id        :bigint   not null
# account_id        :bigint   not null
# professional_id   :bigint
# form_template_id  :bigint
# version_number    :integer  default(1), not null
# specialty         :string
# chief_complaint   :text
# medical_history   :jsonb    default({})
# allergies         :jsonb    default([])
# current_medications :jsonb  default([])
# surgical_history  :text
# family_history    :text
# pregnancy         :jsonb    default({})
# relevant_habits   :jsonb    default({})
# contraindications :jsonb    default([])
# additional_notes  :text
# status            :string   default("draft"), not null
# finalized_at      :datetime
# deleted_at        :datetime
# created_at        :datetime not null
# updated_at        :datetime not null

class Anamnesis < ApplicationRecord
  include TimelineTrackable

  # ============================================================
  # Associations
  # ============================================================
  belongs_to :account
  belongs_to :patient
  belongs_to :professional, class_name: 'User', optional: true
  belongs_to :form_template, optional: true

  has_one_attached :pdf

  # ============================================================
  # Enums
  # ============================================================
  enum status: {
    draft: 'draft',
    finalized: 'finalized'
  }, _prefix: :status

  # ============================================================
  # Validations
  # ============================================================
  validates :patient_id, :account_id, :version_number, :status, presence: true
  validates :version_number, numericality: { greater_than: 0 }

  # ============================================================
  # Scopes
  # ============================================================
  scope :active,      -> { where(deleted_at: nil) }
  scope :deleted,     -> { where.not(deleted_at: nil) }
  scope :latest,      -> { active.order(version_number: :desc) }
  scope :for_patient, ->(patient_id) { active.where(patient_id: patient_id) }

  # ============================================================
  # Callbacks
  # ============================================================

  before_create :set_version_number
  before_update :prevent_edit_if_finalized
  after_create_commit :record_timeline_anamnesis_created
  after_update_commit :record_timeline_anamnesis_finalized, if: -> { saved_change_to_status? && status == 'finalized' }

  # ============================================================
  # Public Methods
  # ============================================================

  def finalize!(actor: nil)
    return false if status_finalized?

    transaction do
      update!(
        status: 'finalized',
        finalized_at: Time.current
      )
      PatientAuditLog.log!(
        account: account,
        patient: patient,
        actor: actor,
        action: 'finalize',
        resource: self,
        changes: { status: %w[draft finalized] }
      )
    end
    true
  end

  def soft_delete!
    update_column(:deleted_at, Time.current)
  end

  # Extrai alergias com severidade alta para geração de CriticalAlerts
  def high_severity_allergies
    Array(allergies).select { |a| a['severity'].to_s == 'high' }
  end

  # Extrai contraindicações registradas
  def active_contraindications
    Array(contraindications).reject { |c| c.blank? }
  end

  private

  def set_version_number
    last_version = patient
                   .anamneses
                   .where(account_id: account_id, deleted_at: nil)
                   .maximum(:version_number) || 0
    self.version_number = last_version + 1
  end

  def prevent_edit_if_finalized
    return unless status_was == 'finalized'

    throw(:abort)
  end

  def record_timeline_anamnesis_created
    record_timeline_event!(
      event_type: 'anamnesis_filled',
      label: 'Anamnese registrada',
      actor: professional,
      occurred_at: Time.current,
      metadata: { profissional: professional&.name.to_s, status: status.to_s }
    )
  end

  def record_timeline_anamnesis_finalized
    finalized_str = finalized_at&.in_time_zone('Brasilia')&.strftime('%d/%m/%Y às %H:%M')
    record_timeline_event!(
      event_type: 'anamnesis_filled',
      label: 'Anamnese finalizada',
      actor: professional,
      occurred_at: Time.current,
      metadata: { finalizada_em: finalized_str }
    )
  end
end
