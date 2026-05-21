class SessionLog < ApplicationRecord
  include TimelineTrackable

  DEFAULT_DRAFT_HOURS = 48
  STATUSES = %w[draft signed].freeze
  SIGNATURE_MODES = %w[local_tablet remote_link].freeze

  # Em sessão `signed` o conteúdo clínico é imutável, mas operações periféricas
  # (assinatura do paciente, marcação de errata) ainda podem alterar campos
  # técnicos. Listamos aqui as colunas que escapam ao guard.
  EDITABLE_AFTER_SIGN = %w[
    patient_signature_blob
    patient_signature_mode
    patient_signed_at
    patient_signature_integrity_hash
    patient_signature_remote_token
    patient_signature_remote_link_sent_at
    patient_signature_remote_link_expires_at
    patient_signature_ip
    patient_signature_device_info
    erratum_at
    erratum_by_id
    erratum_reason
    updated_at
    lock_version
  ].freeze

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :drafts, -> { active.where(status: 'draft') }
  scope :signed, -> { active.where(status: 'signed') }
  scope :erratum, -> { active.where.not(erratum_at: nil) }
  scope :valid_records, -> { active.where(erratum_at: nil) }
  scope :by_patient, ->(patient_id) { where(patient_id: patient_id) }
  scope :recent, -> { order(performed_at: :desc) }

  belongs_to :account
  belongs_to :patient
  belongs_to :professional, class_name: 'User', optional: true
  belongs_to :signed_by, class_name: 'User', optional: true
  belongs_to :erratum_by, class_name: 'User', optional: true
  belongs_to :treatment_plan, optional: true
  belongs_to :treatment_item, optional: true
  belongs_to :appointment, class_name: 'AgendaEvent', optional: true
  belongs_to :form_template, optional: true

  has_one_attached :patient_signature_image

  enum status: { draft: 'draft', signed: 'signed' }, _prefix: :status

  validates :account, presence: true
  validates :patient, presence: true
  validates :performed_at, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :duration_minutes, numericality: { greater_than: 0, only_integer: true, allow_nil: true }
  validates :return_in_days, numericality: { greater_than: 0, only_integer: true, allow_nil: true }
  validates :patient_signature_blob, length: { maximum: 500_000 }, allow_blank: true
  validates :patient_signature_mode, inclusion: { in: SIGNATURE_MODES }, allow_blank: true
  validate :return_in_days_requires_return_needed

  before_update :prevent_edit_if_signed
  after_create :increment_treatment_item_sessions
  after_create :update_treatment_plan_status
  after_create_commit :record_timeline_session_performed
  after_create_commit :assign_patient_responsible_if_missing
  after_update_commit :record_timeline_session_signed,
                      if: -> { saved_change_to_status? && status_signed? }

  def soft_delete!
    raise 'Sessão assinada não pode ser excluída.' if status_signed?

    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def erratum?
    erratum_at.present?
  end

  def patient_signed?
    patient_signed_at.present?
  end

  def patient_signature_method
    case patient_signature_mode
    when 'local_tablet' then 'local'
    when 'remote_link'  then 'remote'
    end
  end

  def patient_signature_remote_link_expired?
    patient_signature_remote_link_expires_at.present? &&
      patient_signature_remote_link_expires_at < Time.current
  end

  def within_draft_window?
    draft_hours = account&.settings&.dig('session_log_draft_hours')&.to_i
    draft_hours = DEFAULT_DRAFT_HOURS if draft_hours.nil? || draft_hours.zero?
    created_at > draft_hours.hours.ago
  end

  def editable_by?(user)
    return false if status_signed?
    return false unless within_draft_window?

    professional_id == user.id || user.administrator?
  end

  def sign!(actor:)
    raise Pundit::NotAuthorizedError, 'Sessão já assinada.' if status_signed?
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

  def mark_as_erratum!(actor:, reason:)
    raise 'Apenas sessões assinadas podem ser marcadas como errata.' unless status_signed?
    raise 'Esta sessão já está marcada como errata.' if erratum?
    raise 'Justificativa da errata é obrigatória.' if reason.blank?

    update_columns(
      erratum_at: Time.current,
      erratum_by_id: actor.id,
      erratum_reason: reason.to_s.strip,
      updated_at: Time.current
    )
    true
  end

  def sign_patient_locally!(signature_blob:, ip_address:, device_info: nil)
    raise StandardError, 'Sessão já assinada pelo paciente.' if patient_signed?
    raise StandardError, 'Assinatura é obrigatória.' if signature_blob.blank?

    signed_at_time = Time.current
    update!(
      patient_signature_blob: signature_blob,
      patient_signature_mode: 'local_tablet',
      patient_signed_at: signed_at_time,
      patient_signature_ip: ip_address,
      patient_signature_device_info: device_info,
      patient_signature_integrity_hash: generate_patient_signature_integrity_hash(signature_blob, signed_at_time)
    )
  end

  def sign_patient_remotely!(signature_blob:, ip_address:, device_info: nil)
    raise StandardError, 'Sessão já assinada pelo paciente.' if patient_signed?
    raise StandardError, 'Assinatura é obrigatória.' if signature_blob.blank?
    raise StandardError, 'Token expirado.' if patient_signature_remote_link_expired?

    signed_at_time = Time.current
    update!(
      patient_signature_blob: signature_blob,
      patient_signature_mode: 'remote_link',
      patient_signed_at: signed_at_time,
      patient_signature_ip: ip_address,
      patient_signature_device_info: device_info,
      patient_signature_integrity_hash: generate_patient_signature_integrity_hash(signature_blob, signed_at_time),
      patient_signature_remote_token: nil
    )
  end

  def send_patient_remote_signature_link!
    self.patient_signature_remote_token = SecureRandom.hex(32) if patient_signature_remote_token.blank?
    self.patient_signature_remote_link_sent_at = Time.current
    self.patient_signature_remote_link_expires_at = 48.hours.from_now
    save!
    true
  end

  def patient_signature_integrity_valid?
    return false if patient_signature_blob.blank? || patient_signed_at.blank? || patient_signature_integrity_hash.blank?

    expected = generate_patient_signature_integrity_hash(patient_signature_blob, patient_signed_at)
    expected == patient_signature_integrity_hash
  end

  def patient_signature_image_url
    return nil unless patient_signature_image.attached?

    token = Patients::SecureBlobTokenService.encode(
      blob_id: patient_signature_image.blob.id,
      account_id: account_id,
      expires_in: 15.minutes
    )
    Rails.application.routes.url_helpers.secure_blob_url(token: token)
  rescue StandardError
    nil
  end

  def migrated_from_clinical_note?
    migrated_from_clinical_note_id.present?
  end

  private

  def generate_patient_signature_integrity_hash(blob, timestamp)
    Digest::SHA256.hexdigest("#{patient_id}#{id}#{blob}#{timestamp}")
  end

  def prevent_edit_if_signed
    return unless status_was == 'signed'

    forbidden = changes.keys - EDITABLE_AFTER_SIGN
    return if forbidden.empty?

    errors.add(:base, 'Sessão assinada não pode ser alterada.')
    throw(:abort)
  end

  def increment_treatment_item_sessions
    return if treatment_item_id.blank?

    Patients::IncrementTreatmentSessionJob.perform_later(treatment_item_id)
  end

  def update_treatment_plan_status
    return if treatment_plan_id.blank?

    Patients::UpdateTreatmentPlanStatusJob.perform_later(treatment_plan_id)
  end

  def return_in_days_requires_return_needed
    return unless return_in_days.present? && !return_needed?

    errors.add(:return_in_days, :requires_return_needed)
  end

  def record_timeline_session_performed
    item_name = procedure_name.presence || treatment_item&.procedure_name || 'Procedimento'
    record_timeline_event!(
      event_type: 'session_performed',
      label: "Sessão realizada: #{item_name} (#{performed_at&.strftime('%d/%m/%Y')})",
      actor: professional,
      occurred_at: Time.current,
      metadata: {
        procedimento: item_name,
        duracao: duration_minutes.to_s,
        profissional: professional&.name.to_s,
        plano_id: treatment_plan_id.to_s,
        status: status.to_s
      }
    )
  end

  def record_timeline_session_signed
    record_timeline_event!(
      event_type: 'session_signed',
      label: "Sessão assinada (#{performed_at&.strftime('%d/%m/%Y')})",
      actor: signed_by || professional,
      occurred_at: Time.current,
      metadata: {
        assinada_por: (signed_by || professional)&.name.to_s,
        signed_at: signed_at&.iso8601
      }
    )
  end

  # Etapa A da auto-atribuição (decisão Mamedes 2026-05-11): quando uma sessão é
  # registrada e o paciente AINDA não tem `responsible_professional_id` setado,
  # adota o profissional desta sessão como responsável. Resolve pacientes
  # importados do Clinicorp ou criados sem responsável explícito — primeiro
  # dentista que atender vira o dono. Idempotente: roda só se patient.* nil.
  def assign_patient_responsible_if_missing
    return if professional_id.blank?
    return unless patient
    return if patient.responsible_professional_id.present?

    patient.update_column(:responsible_professional_id, professional_id)
  end
end
