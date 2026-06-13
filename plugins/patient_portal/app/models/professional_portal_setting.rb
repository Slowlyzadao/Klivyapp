# Overrides por profissional sobre PatientPortalSetting da account.
# Hierarquia: Account → Profissional (este) → Serviço → Procedimento → Tag (PRD §14.6).
class ProfessionalPortalSetting < ApplicationRecord
  belongs_to :account
  belongs_to :user

  validates :user_id, uniqueness: { scope: :account_id }
end
