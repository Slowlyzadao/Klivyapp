# Consent do paciente para gravação da teleconsulta.
#
# Antes da extração do plugin telemed, esses consents viviam em
# PatientPortalConsent com term_type='telemedicine_recording'. Migrados pra
# tabela própria pra isolar o plugin.
#
# Idempotência: único por (account, patient, term_version). Re-emissão do
# termo (novo term_version) cria row nova; revogação não deleta — só seta
# `revoked_at`.
class TelemedConsent < ApplicationRecord
  CURRENT_TERM_VERSION = '1.0'.freeze

  belongs_to :account
  belongs_to :patient

  validates :term_version, presence: true
  validates :accepted_at,  presence: true

  scope :active, -> { where(revoked_at: nil) }

  # AUDIT 2026-05-25 — `find_or_create_by!` retornava silenciosamente uma
  # row com `revoked_at` setado (paciente revogou; tenta aceitar de novo →
  # nada acontece). LGPD Art. 8º §5º exige re-aceite explícito após revogação.
  # Filtramos `revoked_at: nil` no find; se o consent encontrado já foi
  # revogado mas o paciente está re-aceitando agora, atualizamos accepted_at
  # e limpamos revoked_at (mesmo registro, audit trail preservado em ip/UA).
  def self.accept!(account:, patient:, ip: nil, user_agent: nil)
    active_consent = active.find_by(
      account: account,
      patient: patient,
      term_version: CURRENT_TERM_VERSION
    )
    return active_consent if active_consent

    revoked = where(
      account: account,
      patient: patient,
      term_version: CURRENT_TERM_VERSION
    ).where.not(revoked_at: nil).first

    if revoked
      revoked.update!(
        accepted_at: Time.current,
        revoked_at:  nil,
        ip:          ip,
        user_agent:  user_agent.to_s.first(255)
      )
      return revoked
    end

    create!(
      account:      account,
      patient:      patient,
      term_version: CURRENT_TERM_VERSION,
      accepted_at:  Time.current,
      ip:           ip,
      user_agent:   user_agent.to_s.first(255)
    )
  end
end
