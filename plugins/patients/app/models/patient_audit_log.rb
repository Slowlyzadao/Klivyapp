class PatientAuditLog < ApplicationRecord
  # IMUTÁVEL: sem update, sem destroy
  # A tabela não tem updated_at por design

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :resource, polymorphic: true, optional: true

  # Enums.
  #
  # As actions específicas do fluxo de prontuário (`erratum`,
  # `patient_sign_local`, `patient_signature_link_sent`, `clinical_override`)
  # foram adicionadas em [1.5.4.0] depois que a primeira chamada real ao
  # `send_patient_remote_signature_link` quebrou em produção com
  # `ArgumentError: 'patient_signature_link_sent' is not a valid action`.
  # Os endpoints já gravavam essas actions desde [1.5.x] mas só foram
  # exercitados em runtime agora.
  enum :action, {
    view: 'view',
    create: 'create',
    update: 'update',
    delete: 'delete',
    sign: 'sign',
    export: 'export',
    finalize: 'finalize',
    approve: 'approve',
    pay: 'pay',
    print: 'print',
    erratum: 'erratum',
    patient_sign_local: 'patient_sign_local',
    patient_signature_link_sent: 'patient_signature_link_sent',
    clinical_override: 'clinical_override'
  }, prefix: true

  # Validations
  validates :action, presence: true, inclusion: { in: actions.keys }
  validates :occurred_at, presence: true
  validates :patient, presence: true
  validates :account, presence: true

  # Scopes
  scope :ordered, -> { order(occurred_at: :desc) }
  scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  scope :by_actor, ->(actor_id) { where(actor_id: actor_id) }
  scope :by_action, ->(action) { where(action: action) }
  scope :recent, ->(count = 50) { ordered.limit(count) }

  # BLOQUEAR UPDATE e DESTROY — log é imutável por lei (LGPD + CFM)
  before_update { raise FrozenError, 'PatientAuditLog is immutable — cannot be updated' }
  before_destroy { raise FrozenError, 'PatientAuditLog is immutable — cannot be destroyed' }

  # Campos sensíveis que NUNCA devem aparecer em texto plano no log de auditoria.
  # LGPD/segurança: senhas, tokens, secrets jamais em log; CPF/RG ainda podem
  # vazar via screenshot/print, mas mascaramos pra reduzir superfície.
  SENSITIVE_FIELD_KEYS = %w[
    password password_digest password_confirmation
    encrypted_password reset_password_token
    access_token api_key secret_key
    cpf rg
    signature_blob signature_image_url
  ].freeze

  # JSONB grandes (avatar base64, metadata extensa) inflam a tabela e
  # estragam o UI da aba Auditoria. Trunca valores acima desse limite.
  MAX_FIELD_VALUE_SIZE = 1_000 # caracteres

  # Factory method para criar logs com snapshot automático
  def self.log!(account:, patient:, action:, actor: nil, resource: nil, changes: nil, ip_address: nil)
    create!(
      account: account,
      patient: patient,
      actor: actor,
      actor_id: actor&.id,
      actor_name: actor&.name,
      actor_role: actor&.account_users&.find_by(account: account)&.role,
      action: action,
      resource_type: resource&.class&.name,
      resource_id: resource&.id,
      changed_fields: sanitize_changes(changes),
      ip_address: ip_address,
      occurred_at: Time.current
    )
  end

  # Aplica mascaramento e truncamento ao hash de mudanças antes de gravar.
  # Aceita formato `{ field: [old, new] }` ou `{ field: value }`.
  # NÃO falha se entrada for nil ou tipo inesperado — retorna como está.
  def self.sanitize_changes(changes)
    return changes unless changes.is_a?(Hash)

    changes.each_with_object({}) do |(key, value), result|
      key_str = key.to_s.downcase
      result[key] =
        if SENSITIVE_FIELD_KEYS.any? { |sensitive| key_str.include?(sensitive) }
          # Preserva forma (array de [old, new] vs valor único) mas redige conteúdo
          value.is_a?(Array) ? value.map { '[REDACTED]' } : '[REDACTED]'
        else
          truncate_value(value)
        end
    end
  end

  # Trunca strings/JSON grandes pra evitar inflar a tabela. Mantém o tipo
  # original (Array de diff continua Array, etc).
  def self.truncate_value(value)
    case value
    when Array
      value.map { |v| truncate_value(v) }
    when String
      value.length > MAX_FIELD_VALUE_SIZE ? "#{value[0, MAX_FIELD_VALUE_SIZE]}… [truncated: #{value.length} chars]" : value
    when Hash
      serialized = value.to_json
      if serialized.length > MAX_FIELD_VALUE_SIZE
        "[truncated Hash: #{serialized.length} chars]"
      else
        value
      end
    else
      value
    end
  end
end
