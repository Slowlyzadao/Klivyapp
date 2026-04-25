class PatientAuditLog < ApplicationRecord
  # IMUTÁVEL: sem update, sem destroy
  # A tabela não tem updated_at por design

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :actor, class_name: 'User', optional: true
  belongs_to :resource, polymorphic: true, optional: true

  # Enums
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
    print: 'print'
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
      changed_fields: changes,
      ip_address: ip_address,
      occurred_at: Time.current
    )
  end
end
