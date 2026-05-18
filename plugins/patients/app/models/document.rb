class Document < ApplicationRecord
  include TimelineTrackable
  include BeclinicPurgeableAttachment

  # Active Storage — o PDF gerado ou arquivo externo
  has_one_attached :file
  purges_attachment_with job_class: Patients::DocumentPurgeJob

  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :patient
  belongs_to :account
  belongs_to :generated_by, class_name: 'User', optional: true
  belongs_to :form_template, optional: true
  belongs_to :signed_by, class_name: 'User', optional: true

  # Tipos de documento
  DOCUMENT_TYPES = %w[
    receita
    atestado
    pedido_exame
    declaracao
    relatorio_clinico
    encaminhamento
    contrato
    orcamento
    instrucao_procedimento
    questionario
    outro
  ].freeze

  # Status do documento
  STATUSES = %w[gerado pendente_assinatura assinado enviado arquivado].freeze

  # Enums
  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :title, presence: true, length: { minimum: 2, maximum: 255 }
  validates :patient_id, presence: true
  validates :account_id, presence: true
  validates :version, numericality: { greater_than: 0 }

  # Callbacks
  before_create :set_next_version
  before_create :capture_file_metadata
  after_create_commit :record_timeline_document_generated

  # Scopes
  scope :by_type, ->(type) { where(document_type: type) }
  scope :by_status, ->(status) { where(status: status) }
  scope :pending_signature, -> { where(status: 'pendente_assinatura') }
  scope :signed, -> { where(status: 'assinado') }
  scope :generated_by_server, -> { where(is_generated: true) }
  scope :latest_versions, lambda {
    # Retorna apenas a versão mais recente de cada "família" agrupada por tipo + data
    where(id: select('MAX(id)').group(:document_type, :title))
  }

  def soft_delete!
    update!(deleted_at: Time.current)
    schedule_attachment_purge!
  end

  def deleted?
    deleted_at.present?
  end

  # URL assinada via Active Storage padrão (rails_blob_url).
  #
  # NOTA arquitetural: tentamos antes apontar pra um SecureBlobsController
  # com guard de cross-tenant via devise_token_auth, mas isso quebra o
  # click-to-open do browser (browser GET vanilla não envia headers de auth
  # token, então devise rejeita com 401). A guarda de cross-tenant via
  # auth de API é incompatível com o fluxo "clicar no link pra abrir PDF".
  #
  # Mitigação atual: signed_id curto (30min) + HTTPS limitam superfície de
  # replay caso a URL vaze. Para hardening adicional (cross-tenant guard
  # SEM quebrar click-to-open), seria necessário redesign — token customizado
  # que carrega account_id + auth via cookie de sessão. Fora de escopo agora.
  def signed_url(expires_in: 30.minutes, disposition: :inline)
    return nil unless file.attached?

    Rails.application.routes.url_helpers.rails_blob_url(
      file,
      expires_in: expires_in,
      disposition: disposition
    )
  rescue StandardError
    nil
  end

  def pending_signature?
    status == 'pendente_assinatura'
  end

  def signed?
    status == 'assinado'
  end

  def sent?
    status == 'enviado'
  end

  def mark_as_sent!
    update!(status: 'enviado', sent_at: Time.current)
  end

  def mark_as_signed!(user)
    update!(
      status: 'assinado',
      signed_at: Time.current,
      signed_by: user
    )
  end

  private

  def set_next_version
    last_version = patient.documents
                          .active
                          .where(document_type: document_type, title: title)
                          .maximum(:version) || 0
    self.version = last_version + 1
  end

  def capture_file_metadata
    return unless file.attached?

    self.file_name ||= file.filename.to_s
    self.mime_type ||= file.content_type
    self.file_size ||= file.byte_size
  end

  def record_timeline_document_generated
    record_timeline_event!(
      event_type: 'document_generated',
      label: "Documento gerado: #{title} (#{document_type})",
      actor: generated_by,
      occurred_at: Time.current,
      metadata: { titulo: title.to_s, tipo: document_type.to_s, versao: version }
    )
  end
end
