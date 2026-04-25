# == Schema Information
#
# Table name: clinical_notes
#
# id                  :bigint   not null, primary key
# patient_id          :bigint   not null
# account_id          :bigint   not null
# professional_id     :bigint
# appointment_id      :bigint
# form_template_id    :bigint
# note_date           :date     not null
# complaint_of_day    :text
# assessment          :text
# conduct             :text
# complications       :text
# guidance_given      :text
# return_recommended  :date
# status              :string   default("draft"), not null
# signed_at           :datetime
# signed_by_id        :bigint
# deleted_at          :datetime
# created_at          :datetime not null
# updated_at          :datetime not null

class ClinicalNote < ApplicationRecord
  include TimelineTrackable

  # ============================================================
  # Constants
  # ============================================================
  # Janela de edição draft configurável via Account.settings["clinical_note_draft_hours"]
  DEFAULT_DRAFT_HOURS = 48

  # ============================================================
  # Associations
  # ============================================================
  belongs_to :account
  belongs_to :patient
  belongs_to :professional, class_name: 'User', optional: true
  belongs_to :appointment,  class_name: 'AgendaEvent', optional: true
  belongs_to :form_template, optional: true
  belongs_to :signed_by,    class_name: 'User', optional: true

  # ============================================================
  # Enums
  # ============================================================
  enum status: {
    draft: 'draft',
    signed: 'signed'
  }, _prefix: :status

  # ============================================================
  # Validations
  # ============================================================
  validates :patient_id, :account_id, :note_date, :status, presence: true

  # ============================================================
  # Scopes
  # ============================================================
  scope :active,      -> { where(deleted_at: nil) }
  scope :deleted,     -> { where.not(deleted_at: nil) }
  scope :drafts,      -> { active.where(status: 'draft') }
  scope :signed,      -> { active.where(status: 'signed') }
  scope :for_patient, ->(patient_id) { active.where(patient_id: patient_id) }
  scope :recent,      -> { active.order(note_date: :desc, created_at: :desc) }
  scope :editable,    -> { drafts.where('created_at > ?', DEFAULT_DRAFT_HOURS.hours.ago) }

  # ============================================================
  # Callbacks
  # ============================================================
  before_update :prevent_edit_if_signed
  after_create_commit :record_timeline_note_created
  after_update_commit :record_timeline_note_signed, if: -> { saved_change_to_status? && status == 'signed' }

  # ============================================================
  # Public Methods
  # ============================================================

  def sign!(actor:)
    raise Pundit::NotAuthorizedError, 'Nota já assinada.' if status_signed?
    raise Pundit::NotAuthorizedError, 'Janela de edição encerrada.' unless within_draft_window?

    transaction do
      update!(
        status: 'signed',
        signed_at: Time.current,
        signed_by_id: actor.id
      )
      PatientAuditLog.log!(
        account: account,
        patient: patient,
        actor: actor,
        action: 'sign',
        resource: self,
        changes: { status: %w[draft signed] }
      )
    end
    true
  end

  def soft_delete!
    raise 'Evolução assinada não pode ser excluída.' if status_signed?

    update_column(:deleted_at, Time.current)
  end

  def within_draft_window?
    draft_hours = account&.settings&.dig('clinical_note_draft_hours')&.to_i || DEFAULT_DRAFT_HOURS
    created_at > draft_hours.hours.ago
  end

  def editable_by?(user)
    return false if status_signed?
    return false unless within_draft_window?

    professional_id == user.id || user.administrator?
  end

  private

  def prevent_edit_if_signed
    return unless status_was == 'signed'

    errors.add(:base, 'Evolução assinada não pode ser alterada.')
    throw(:abort)
  end

  def record_timeline_note_created
    record_timeline_event!(
      event_type: 'clinical_note',
      label: "Evolução clínica registrada (#{note_date&.strftime('%d/%m/%Y')})",
      actor: professional,
      occurred_at: Time.current,
      metadata: { data: note_date.to_s, profissional: professional&.name.to_s, status: status.to_s }
    )
  end

  def record_timeline_note_signed
    record_timeline_event!(
      event_type: 'clinical_note',
      label: "Evolução clínica assinada (#{note_date&.strftime('%d/%m/%Y')})",
      actor: signed_by || professional,
      occurred_at: Time.current,
      metadata: { data: note_date.to_s, assinada_por: (signed_by || professional)&.name.to_s }
    )
  end
end
