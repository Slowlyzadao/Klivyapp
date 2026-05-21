class CriticalAlert < ApplicationRecord
  # Soft delete
  scope :active, -> { where(deleted_at: nil).where(active: true) }
  scope :all_active, -> { where(active: true) }

  # Associations
  belongs_to :account
  belongs_to :patient
  belongs_to :created_by, class_name: 'User', optional: true

  # Enums
  enum :alert_type, {
    allergy: 'allergy',
    condition: 'condition',
    medication: 'medication',
    contraindication: 'contraindication',
    other: 'other'
  }, prefix: true

  enum :severity, {
    high: 'high',
    medium: 'medium',
    low: 'low'
  }, prefix: true

  # Validations
  validates :title, presence: true, length: { minimum: 2, maximum: 255 }
  validates :alert_type, presence: true, inclusion: { in: alert_types.keys }
  validates :severity, presence: true, inclusion: { in: severities.keys }
  validates :patient, presence: true
  validates :account, presence: true

  # Callbacks
  after_create :auto_activate_patient
  after_destroy :check_remaining_alerts

  # Scopes
  scope :high_severity, -> { where(severity: 'high') }
  scope :ordered_by_severity, -> { order(Arel.sql("CASE severity WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END")) }

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  def deactivate!
    update!(active: false)
  end

  private

  def auto_activate_patient
    # Se paciente está como 'novo' e recebe um alerta, atualiza status
    patient.update!(patient_status: 'ativo') if patient.patient_status_novo?
  end

  def check_remaining_alerts
    # Lógica de recalcular status do paciente se necessário
    # Implementação completa no contexto do Bloco 2 (AnamnesisFinalizerService)
    true
  end
end
