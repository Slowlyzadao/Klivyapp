class FormTemplate < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil).where(active: true) }
  scope :global, -> { where(is_global: true) }

  # Associations
  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  # Enums
  enum :template_type, {
    anamnesis: 'anamnesis',
    clinical_note: 'clinical_note',
    consent: 'consent',
    document: 'document',
    receipt: 'receipt'
  }, prefix: true

  # Validations
  validates :name, presence: true, length: { minimum: 2, maximum: 255 }
  validates :template_type, presence: true, inclusion: { in: template_types.keys }
  validates :account, presence: true

  # Scopes
  scope :by_type, ->(type) { where(template_type: type) }
  scope :by_specialty, ->(specialty) { where(specialty: specialty) }
  scope :for_account_or_global, ->(account_id) { where(account_id: account_id).or(where(is_global: true)) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def field_count
    fields.size
  end
end
