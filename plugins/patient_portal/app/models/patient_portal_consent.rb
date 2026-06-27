# Termo Klivy aceito pelo paciente (não confundir com ConsentRecord, que é do
# plugin Pacientes e cobre termos clínicos por procedimento).
#
# Duas categorias:
#   - 'portal_terms' — Termo de Uso do Portal
#   - 'lgpd'         — Política de Privacidade (LGPD)
#
# Antes existia também 'telemedicine_recording' — movido pra TelemedConsent
# no plugin telemed. Rows antigas continuam aqui como audit trail até cleanup.
#
# Versionamento: ao mudar `CURRENT_TERM_VERSION`, todos os pacientes recebem
# o modal de aceite novamente no próximo login (PRD §11.4).
class PatientPortalConsent < ApplicationRecord
  CURRENT_TERM_VERSION = '1.0'.freeze

  TERM_TYPES = %w[portal_terms lgpd].freeze

  belongs_to :account
  belongs_to :patient

  validates :term_type, inclusion: { in: TERM_TYPES }
  validates :term_version, presence: true

  scope :active, -> { where(revoked_at: nil) }

  def self.accept!(account:, patient:, term_type:, ip: nil, user_agent: nil)
    create!(
      account:      account,
      patient:      patient,
      term_type:    term_type,
      term_version: CURRENT_TERM_VERSION,
      accepted_at:  Time.current,
      ip:           ip,
      user_agent:   user_agent
    )
  end
end
