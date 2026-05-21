# Subscription de Web Push de um paciente (Sprint G).
#
# Modelo "burro": guarda chaves VAPID do device. Toda a lógica de envio
# (criptografia, retry, disable após falha) fica em `PatientPortal::PushNotifier`.
class PatientPortalPushSubscription < ApplicationRecord
  self.table_name = 'patient_portal_push_subscriptions'

  belongs_to :account
  belongs_to :patient

  validates :endpoint,   presence: true, uniqueness: true, length: { maximum: 1024 }
  validates :p256dh_key, presence: true
  validates :auth_key,   presence: true

  scope :active,   -> { where(disabled_at: nil) }
  scope :for_patient, ->(p) { where(patient_id: p.id) }

  # Desativa após N falhas consecutivas (gateway retornou 410/404 → endpoint morto).
  MAX_FAILURES = 3

  def record_success!
    update_columns(failure_count: 0, last_used_at: Time.current, updated_at: Time.current)
  end

  def record_failure!(permanent: false)
    new_count = failure_count + 1
    attrs = { failure_count: new_count, updated_at: Time.current }
    attrs[:disabled_at] = Time.current if permanent || new_count >= MAX_FAILURES
    update_columns(attrs)
  end

  def disabled? = disabled_at.present?
end
