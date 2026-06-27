# Template de documento — modelo central do plugin document_templates.
#
# Cada row é um modelo editável (contrato, atestado, consentimento) escrito
# no TipTap (frontend) e renderizado em PDF via Grover quando usado.
#
# Tipos de template:
#   - source='klivy'  + account_id=NULL → biblioteca Klivy global.
#   - source='clinic' + account_id=X    → criado do zero pela clínica X.
#   - source='cloned' + account_id=X    → clínica X clonou um Klivy.
#                                         source_template_id aponta pro Klivy.
#
# Document.document_type (string) é a chave de ligação com o sistema legado.
# Quando o profissional vai gerar documento dentro do paciente, filtramos
# os templates dessa account pelo document_type pedido.
class DocumentTemplate < ApplicationRecord
  # ── Tipos suportados (alinhado com Document.DOCUMENT_TYPES + tipos de
  # consentimento que hoje vivem em ConsentRecord.body) ────────────────────
  #
  # Decisão (auditoria 2026-05-27): document_type é string (não enum integer)
  # porque Document.document_type também é string. Mantemos consistência pra
  # não precisar de conversão na hora de filtrar templates por tipo.
  CLINICAL_TYPES = %w[
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

  CONSENT_TYPES = %w[
    consentimento_geral
    consentimento_lgpd
    consentimento_imagem
    consentimento_toxina
    consentimento_preenchimento
    consentimento_laser
    consentimento_fototerapia_led
    consentimento_peeling
    consentimento_dermoabrasao
    consentimento_menor
    consentimento_cirurgico
    consentimento_anestesia
  ].freeze

  DOCUMENT_TYPES = (CLINICAL_TYPES + CONSENT_TYPES).freeze

  SOURCES   = %w[klivy clinic cloned].freeze
  STATUSES  = %w[draft active archived].freeze

  PAPER_SIZES  = %w[A4 Letter A5].freeze
  ORIENTATIONS = %w[portrait landscape].freeze

  MAX_CONTENT_JSON_BYTES = 500_000

  # Tipos de nó ProseMirror que NUNCA podem aparecer no content_json
  # (defesa contra XSS / payload malicioso, mesmo que TipTap teoricamente
  # não emita esses nodes).
  FORBIDDEN_NODE_TYPES = %w[script iframe object embed].freeze

  # ── Associações ──────────────────────────────────────────────────────────
  # account é optional porque templates Klivy globais têm account_id NULL.
  belongs_to :account, optional: true
  belongs_to :folder,
             class_name: 'DocumentTemplateFolder',
             optional: true
  belongs_to :created_by_user,
             class_name: 'User',
             optional: true
  belongs_to :source_template,
             class_name: 'DocumentTemplate',
             optional: true

  has_many :clones,
           class_name: 'DocumentTemplate',
           foreign_key: 'source_template_id',
           dependent: :nullify

  has_many :documents,        dependent: :restrict_with_error
  has_many :consent_records,  dependent: :restrict_with_error

  # ── Validações ───────────────────────────────────────────────────────────
  validates :name, presence: true, length: { maximum: 200 }
  validates :document_type, presence: true, inclusion: { in: DOCUMENT_TYPES }
  validates :source,        presence: true, inclusion: { in: SOURCES }
  validates :status,        presence: true, inclusion: { in: STATUSES }
  validates :paper_size,    inclusion: { in: PAPER_SIZES }, allow_blank: true
  validates :orientation,   inclusion: { in: ORIENTATIONS }, allow_blank: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :description, length: { maximum: 2_000 }, allow_blank: true

  # Nome único dentro de (account, folder). Templates Klivy (account_id NULL)
  # podem ter nomes iguais entre si só se forem de tipos diferentes.
  validates :name,
            uniqueness: { scope: [:account_id, :folder_id], case_sensitive: false }

  validate :validate_account_consistency
  validate :validate_source_template_consistency
  validate :validate_folder_belongs_to_account
  validate :validate_content_json_structure

  # ── Callbacks ────────────────────────────────────────────────────────────
  # bump_version SÓ em update — no create, mantém o default 1 da coluna.
  before_update :bump_version,    if: :content_json_changed?
  before_save   :clear_html_cache, if: :content_json_changed?
  before_save   :sync_archived_at

  # ── Scopes ───────────────────────────────────────────────────────────────
  scope :active,    -> { where(status: 'active') }
  scope :archived,  -> { where(status: 'archived') }
  scope :draft,     -> { where(status: 'draft') }
  scope :klivy,     -> { where(source: 'klivy', account_id: nil) }
  scope :clinical,  -> { where(document_type: CLINICAL_TYPES) }
  scope :consents,  -> { where(document_type: CONSENT_TYPES) }

  # Templates visíveis pra uma account específica: os próprios + os Klivy
  # globais. Usado tanto na listagem da aba Documentos quanto no modal de
  # "Gerar Documento" dentro do paciente.
  scope :for_account, ->(account) { where(account_id: [account.id, nil]) }

  # ── Helpers de leitura ───────────────────────────────────────────────────
  def klivy?
    source == 'klivy'
  end

  def cloned?
    source == 'cloned'
  end

  def clinic_owned?
    source == 'clinic'
  end

  def consent?
    CONSENT_TYPES.include?(document_type)
  end

  def family
    consent? ? :consent : :clinical
  end

  private

  # ── Regras de consistência ──────────────────────────────────────────────

  # Templates Klivy globais SEMPRE têm account_id NULL.
  # Templates de clínica (clinic ou cloned) SEMPRE têm account_id presente.
  def validate_account_consistency
    if klivy? && account_id.present?
      errors.add(:account_id, 'must be null for Klivy templates')
    elsif !klivy? && account_id.blank?
      errors.add(:account_id, 'must be present for non-Klivy templates')
    end
  end

  # source='cloned' exige source_template_id apontando pra um Klivy.
  def validate_source_template_consistency
    if cloned? && source_template_id.blank?
      errors.add(:source_template_id, 'is required when source is cloned')
    elsif !cloned? && source_template_id.present?
      errors.add(:source_template_id, 'must be empty unless source is cloned')
    end
  end

  def validate_folder_belongs_to_account
    return if folder.blank?
    return if folder.account_id == account_id

    errors.add(:folder, 'must belong to the same account as the template')
  end

  # Garante que content_json é um documento ProseMirror válido, não passa
  # do limite de bytes e não contém node types perigosos. Não fazemos
  # validação semântica completa do schema TipTap aqui (caro e frágil) — o
  # frontend é a primeira linha de defesa, esses checks são fallback.
  def validate_content_json_structure
    return errors.add(:content_json, 'must be a hash') unless content_json.is_a?(Hash)
    return errors.add(:content_json, 'must be a ProseMirror doc') unless content_json['type'] == 'doc'

    size_bytes = content_json.to_json.bytesize
    if size_bytes > MAX_CONTENT_JSON_BYTES
      errors.add(:content_json, "exceeds #{MAX_CONTENT_JSON_BYTES} bytes (got #{size_bytes})")
    end

    validate_no_dangerous_nodes(content_json)
  end

  def validate_no_dangerous_nodes(node)
    return if node.nil?

    if node.is_a?(Hash) && FORBIDDEN_NODE_TYPES.include?(node['type'])
      errors.add(:content_json, "contains forbidden node type: #{node['type']}")
      return
    end

    Array(node.is_a?(Hash) ? node['content'] : nil).each { |child| validate_no_dangerous_nodes(child) }
  end

  # ── Callbacks ───────────────────────────────────────────────────────────

  def bump_version
    self.version = (version || 0) + 1
  end

  def clear_html_cache
    self.content_html_cached = nil
  end

  # Mantém archived_at em sincronia com status='archived'. Permite query
  # rápida via index parcial em archived_at sem precisar JOIN no status.
  def sync_archived_at
    if status == 'archived' && archived_at.blank?
      self.archived_at = Time.current
    elsif status != 'archived' && archived_at.present?
      self.archived_at = nil
    end
  end
end
