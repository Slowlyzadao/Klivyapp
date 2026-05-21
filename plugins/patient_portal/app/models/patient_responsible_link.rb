# Vínculo paciente↔responsável legal (Sprint I, PRD §13.2).
#
# Idempotência: a tabela tem unique(responsible_id, dependent_id). Tentativas
# duplicadas levantam ActiveRecord::RecordNotUnique. Use o helper
# `find_or_create_link` quando o caller não quer lidar com a exceção.
#
# Mesma account: ambos os patients devem pertencer ao mesmo account (não
# atravessa clínicas — multi-tenant safety). Validamos no save.
class PatientResponsibleLink < ApplicationRecord
  self.table_name = 'patient_responsible_links'

  ROLES = %w[parent guardian curator spouse other].freeze

  belongs_to :account
  belongs_to :responsible, class_name: 'Patient', foreign_key: :responsible_patient_id
  belongs_to :dependent,   class_name: 'Patient', foreign_key: :dependent_patient_id

  validates :role, inclusion: { in: ROLES }
  validate  :same_account
  validate  :not_self_link
  validates :responsible_patient_id, uniqueness: { scope: :dependent_patient_id }

  scope :active, lambda {
    where(revoked_at: nil)
      .where('active_from <= ?', Time.current)
      .where('active_until IS NULL OR active_until > ?', Time.current)
  }

  scope :for_responsible, ->(p) { where(responsible_patient_id: p.id) }
  scope :for_dependent,   ->(p) { where(dependent_patient_id: p.id) }

  def revoke!(at: Time.current)
    update!(revoked_at: at)
  end

  def active?
    return false if revoked_at.present?
    return false if active_until.present? && active_until <= Time.current

    active_from <= Time.current
  end

  private

  def same_account
    return if responsible_patient_id.blank? || dependent_patient_id.blank?

    ra = responsible&.account_id
    da = dependent&.account_id
    return if ra && da && ra == da && ra == account_id

    errors.add(:base, 'Responsável e dependente devem pertencer à mesma clínica.')
  end

  def not_self_link
    return if responsible_patient_id.blank? || dependent_patient_id.blank?
    return unless responsible_patient_id == dependent_patient_id

    errors.add(:base, 'Não é possível ser responsável por si mesmo.')
  end
end
