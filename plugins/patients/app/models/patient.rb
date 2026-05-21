class Patient < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  # Associations
  belongs_to :account
  belongs_to :contact, optional: true  # ponte com Chatwoot contacts
  belongs_to :responsible_professional, class_name: 'User', optional: true
  has_many :critical_alerts, -> { where(deleted_at: nil) }, dependent: :destroy
  has_many :patient_audit_logs, dependent: :destroy
  has_many :cash_entries, dependent: :nullify
  has_many :anamneses, -> { where(deleted_at: nil) }, dependent: :destroy, class_name: 'Anamnesis'
  has_many :clinical_notes, -> { where(deleted_at: nil) }, dependent: :destroy
  # Bloco 3: Plano de Tratamento + Sessões
  has_many :treatment_plans, -> { where(deleted_at: nil) }, dependent: :destroy
  has_many :treatment_items, through: :treatment_plans
  has_many :session_logs, -> { where(deleted_at: nil) }, dependent: :destroy
  # Bloco 4: Financeiro do Paciente — modelos v1 (Transaction/FinancialEstimate/
  # Installment global) deletados na Fase A de 2026-05-11. Dados financeiros do
  # paciente agora vivem em `Financial::Budget`/`Financial::Installment` (v2);
  # paciente acessa via Financial::Budget.where(patient_id: id) ou helpers
  # equivalentes em controllers/services do plugin financial.
  # Bloco 5: Mídia, Documentos e Consentimentos
  has_many :exam_medias, -> { where(deleted_at: nil) }, dependent: :destroy
  has_many :documents, -> { where(deleted_at: nil) }, dependent: :destroy
  has_many :consent_records, -> { where(deleted_at: nil) }, dependent: :destroy
  # Bloco 6: Agenda do Paciente + Timeline
  has_many :patient_appointments, -> { where(deleted_at: nil) }, dependent: :destroy
  has_many :patient_timeline_events, dependent: :destroy
  has_many :exam_folders, dependent: :destroy
  belongs_to :recall_dismissed_by, class_name: 'User', optional: true

  has_one_attached :avatar

  # Enums
  enum :patient_status, {
    novo: 'novo',
    ativo: 'ativo',
    inativo: 'inativo',
    faltoso: 'faltoso',
    alta: 'alta',
    arquivado: 'arquivado'
  }, prefix: true

  enum :sex, {
    masculino: 'masculino',
    feminino: 'feminino',
    outro: 'outro',
    nao_informado: 'nao_informado'
  }, prefix: true

  enum :marital_status, {
    solteiro: 'solteiro',
    casado: 'casado',
    divorciado: 'divorciado',
    viuvo: 'viuvo'
  }, prefix: true

  GUARDIAN_REQUIRED_FIELDS = %w[name cpf phone relationship].freeze

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :account, presence: true
  validates :cpf, format: { with: /\A\d{11}\z/, message: :invalid_cpf }, allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :patient_status, inclusion: { in: patient_statuses.keys }
  validates :sex, inclusion: { in: sexes.keys }, allow_blank: true
  validates :marital_status, inclusion: { in: marital_statuses.keys }, allow_blank: true
  validate :guardian_fields_present, if: :has_guardian
  validate :guardian_cpf_format, if: :has_guardian

  # Callbacks
  before_validation :strip_cpf
  before_validation :strip_guardian_cpf
  before_validation :clear_guardian_when_disabled
  before_save :update_needs_recall

  # Scopes
  scope :by_name, -> { order(:name) }
  scope :needs_recall, -> { where(needs_recall: true) }
  scope :faltosos, -> { where(patient_status: 'faltoso') }
  scope :with_critical_alerts, -> { joins(:critical_alerts).distinct }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deleted?
    deleted_at.present?
  end

  def age
    return nil unless birthdate

    today = Date.current
    age = today.year - birthdate.year
    age -= 1 if today < birthdate + age.years
    age
  end

  def full_address
    return nil if address.blank?

    [
      address['street'],
      address['number'],
      address['complement'],
      address['neighborhood'],
      address['city'],
      address['state'],
      address['zip_code']
    ].compact.reject(&:blank?).join(', ')
  end

  def resolved_avatar_url
    return Rails.application.routes.url_helpers.rails_blob_url(avatar, only_path: true) if avatar.attached?

    avatar_url
  end

  private

  def strip_cpf
    self.cpf = cpf.gsub(/\D/, '') if cpf.present?
  end

  def strip_guardian_cpf
    return unless guardian.is_a?(Hash) && guardian['cpf'].present?

    guardian['cpf'] = guardian['cpf'].gsub(/\D/, '')
  end

  # Quando has_guardian é desligado, garantimos que o jsonb do responsável
  # seja zerado — evita que dados antigos persistam ocultos no banco.
  def clear_guardian_when_disabled
    return if has_guardian

    self.guardian = {} if guardian.is_a?(Hash) && guardian.any?
  end

  def guardian_fields_present
    GUARDIAN_REQUIRED_FIELDS.each do |key|
      errors.add(:"guardian_#{key}", :blank) if guardian.is_a?(Hash) ? guardian[key].blank? : true
    end
  end

  def guardian_cpf_format
    cpf_value = guardian.is_a?(Hash) ? guardian['cpf'].to_s : ''
    return if cpf_value.blank? # presence é coberta por guardian_fields_present
    return if cpf_value.match?(/\A\d{11}\z/)

    errors.add(:guardian_cpf, :invalid_cpf)
  end

  def update_needs_recall
    # Calcula dinamicamente se o paciente precisa de recall
    # Lógica: último agendamento concluído existe, não há agendamento futuro,
    # e o paciente não tem status 'alta' ou 'arquivado'
    return if patient_status_alta? || patient_status_arquivado?

    last_done = patient_appointments.done.order(scheduled_at: :desc).first
    return unless last_done # Nunca foi atendido — não precisa de recall

    has_future = patient_appointments.upcoming.exists?
    self.needs_recall = !has_future
  end
end
