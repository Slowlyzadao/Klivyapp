# == Schema Information
#
# Table name: patient_timeline_events
#
#  id             :bigint           not null, primary key
#  account_id     :bigint           not null
#  patient_id     :bigint           not null
#  actor_id       :bigint
#  event_type     :string           not null
#  label          :text             not null
#  actor_name     :string
#  reference_type :string
#  reference_id   :bigint
#  metadata       :jsonb            default({})
#  occurred_at    :datetime         not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#

class PatientTimelineEvent < ApplicationRecord
  # ─── Associations ─────────────────────────────────────────────────────────────
  belongs_to :account
  belongs_to :patient
  belongs_to :actor, class_name: 'User', optional: true

  # ─── Valid Event Types ────────────────────────────────────────────────────────
  # Mantenha em sincronia com o `TIMELINE_TYPE_CONFIG` em
  # plugins/patients/frontend/routes/patients/tabs/TimelineTab.vue
  VALID_EVENT_TYPES = %w[
    cadastro
    anamnesis_filled
    appointment_scheduled
    appointment_rescheduled
    appointment_done
    appointment_no_show
    appointment_canceled
    clinical_note
    session_performed
    exam_uploaded
    document_generated
    document_deleted
    consent_signed
    consent_revoked
    consent_expired
    treatment_plan_created
    treatment_plan_approved
    treatment_plan_archived
    payment
    refund
    status_changed
    discharge
    recall_sent
  ].freeze

  # ─── Validations ──────────────────────────────────────────────────────────────
  validates :account,    presence: true
  validates :patient,    presence: true
  validates :event_type, presence: true, inclusion: { in: VALID_EVENT_TYPES }
  validates :label,      presence: true
  validates :occurred_at, presence: true

  # ─── Scopes ───────────────────────────────────────────────────────────────────
  scope :chronological,       -> { order(occurred_at: :desc) }
  scope :by_type,             ->(types) { where(event_type: Array(types)) }
  scope :after_date,          ->(date) { where('occurred_at >= ?', date) }
  scope :before_date,         ->(date) { where('occurred_at <= ?', date) }
  scope :by_reference,        ->(type, id) { where(reference_type: type, reference_id: id) }

  # ─── Factory Method ───────────────────────────────────────────────────────────
  # Cria um evento na timeline de forma segura, sem propagar exceções.
  #
  # DECISÃO DE DESIGN: timeline é dado AUXILIAR (não-bloqueante) — uma falha
  # ao gravar evento NUNCA deve abortar a operação principal do caller (ex:
  # criar consulta, finalizar anamnese). Por isso fazemos rescue genérico e
  # retornamos nil em caso de erro.
  #
  # CONTRATO: caller pode checar o retorno (`event = record!(...); if event...`)
  # mas em geral não precisa — timeline é fire-and-forget. Em caso de falha,
  # log detalhado + Rollbar/Sentry (quando configurado) garantem visibilidade
  # para investigar sem quebrar UX.
  #
  # Em teste (`Rails.env.test?`), levantamos a exceção pra que specs detectem
  # validações quebradas em vez de silenciar.
  def self.record!(patient:, account:, event_type:, label:, actor: nil, reference: nil, metadata: {}, occurred_at: Time.current)
    return unless VALID_EVENT_TYPES.include?(event_type.to_s)

    create!(
      account: account,
      patient: patient,
      actor: actor,
      actor_name: actor&.name,
      event_type: event_type,
      label: label,
      reference_type: reference&.class&.name,
      reference_id: reference&.id,
      metadata: metadata,
      occurred_at: occurred_at
    )
  rescue StandardError => e
    Rails.logger.error(
      "[PatientTimelineEvent] Falha ao registrar evento " \
      "type=#{event_type} patient_id=#{patient&.id} account_id=#{account&.id} " \
      "actor_id=#{actor&.id}: #{e.class.name} - #{e.message}"
    )
    Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace
    # Em produção/staging — reporta a Sentry/Rollbar quando disponível.
    ChatwootExceptionTracker.new(e, account: account).capture_exception if defined?(ChatwootExceptionTracker)
    # Em teste, propaga pra fail-fast em specs que escondem bugs reais.
    raise if Rails.env.test?

    nil
  end
end
