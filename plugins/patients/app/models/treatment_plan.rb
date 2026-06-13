class TreatmentPlan < ApplicationRecord
  include TimelineTrackable

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :professional, class_name: 'User', optional: true
  belongs_to :approved_by, class_name: 'User', optional: true
  has_many :treatment_items, -> { where(deleted_at: nil) }, dependent: :destroy
  has_many :session_logs, -> { where(deleted_at: nil) }, dependent: :destroy
  has_one_attached :pdf

  # Enums
  enum :status, {
    proposto: 'proposto',
    aprovado: 'aprovado',
    em_execucao: 'em_execucao',
    concluido: 'concluido',
    cancelado: 'cancelado'
  }, prefix: true

  # Validations
  validates :account, presence: true
  validates :patient, presence: true
  validates :status, inclusion: { in: statuses.keys }

  # Scopes
  scope :by_patient, ->(patient_id) { where(patient_id: patient_id) }
  scope :pending_approval, -> { where(status: ['proposto']) }
  scope :in_progress, -> { where(status: %w[aprovado em_execucao]) }

  # Callbacks
  after_create_commit :assign_patient_responsible_if_missing

  # Methods
  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def approved?
    status_aprovado? || status_em_execucao? || status_concluido?
  end

  def total_planned
    treatment_items.sum(:total_price)
  end

  def total_sessions_planned
    treatment_items.sum(:sessions_planned)
  end

  def total_sessions_done
    treatment_items.sum(:sessions_done)
  end

  def completion_percentage
    return 0 if total_sessions_planned.zero?

    ((total_sessions_done.to_f / total_sessions_planned) * 100).round(1)
  end

  # ─── Callbacks de Timeline ───────────────────────────────────────────────────
  after_create_commit :record_timeline_plan_created
  after_update_commit :record_timeline_plan_status_changed, if: :saved_change_to_status?

  # ─── Refresh do PDF anexado ──────────────────────────────────────────────────
  # Regenera o PDF assincronamente quando o plano muda APÓS a primeira geração.
  # `pdf.attached?` evita disparar durante o approve (o approver anexa fora dos
  # callbacks de `update!`). Cancelados mantêm o PDF como histórico.
  after_update_commit :enqueue_pdf_refresh, if: :should_refresh_pdf?

  # Campos cuja mudança justifica regenerar o PDF. `updated_at` e
  # `lock_version` ficam de fora — a própria geração faz attach do PDF que
  # touchea esses dois campos, e sem essa exclusão o callback dispara em
  # loop infinito (job regenera → attach toca → callback dispara → ...).
  PDF_RELEVANT_FIELDS = %w[
    title description estimated_duration status partially_approved
    approved_at approved_by_id cancellation_reason
  ].freeze

  private

  def should_refresh_pdf?
    return false unless pdf.attached?
    return false unless status_aprovado? || status_em_execucao? || status_concluido?
    return false if (saved_changes.keys & PDF_RELEVANT_FIELDS).empty?

    true
  end

  def enqueue_pdf_refresh
    Patients::RegenerateTreatmentPlanPdfJob.perform_later(id)
  end

  def record_timeline_plan_created
    items_count = treatment_items.count
    record_timeline_event!(
      event_type: 'status_changed',
      label: "Plano de tratamento criado (#{items_count} procedimento#{'s' if items_count != 1})",
      actor: professional,
      occurred_at: Time.current,
      metadata: { plano_id: id, status: status.to_s, profissional: professional&.name.to_s }
    )
  end

  def record_timeline_plan_status_changed
    label = case status
            when 'aprovado' then 'Plano de tratamento aprovado'
            when 'em_execucao' then 'Plano de tratamento em execução'
            when 'concluido' then 'Plano de tratamento concluído'
            when 'cancelado' then 'Plano de tratamento cancelado'
            else "Plano de tratamento atualizado para #{status}"
            end

    record_timeline_event!(
      event_type: 'status_changed',
      label: label,
      actor: approved_by || professional,
      occurred_at: Time.current,
      metadata: { plano_id: id, status: status.to_s, anterior: status_before_last_save.to_s }
    )
  end

  # Etapa A da auto-atribuição (decisão Mamedes 2026-05-11): se o paciente não
  # tem `responsible_professional_id` e este plano tem profissional, adota.
  # Cobre o caso "primeiro plano criado define o dono do paciente".
  def assign_patient_responsible_if_missing
    return if professional_id.blank?
    return unless patient
    return if patient.responsible_professional_id.present?

    patient.update_column(:responsible_professional_id, professional_id)
  end
end
