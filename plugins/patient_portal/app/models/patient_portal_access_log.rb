# Trilha de auditoria de cada acesso/ação do paciente no portal.
# PRD §17.1 — LGPD obrigatório. Insere SEMPRE via `PatientPortalAccessLog.log!`
# (não usar `create` direto, que pode falhar silenciosamente em batch).
class PatientPortalAccessLog < ApplicationRecord
  ACTIONS = %w[
    login_otp_request
    login_otp_success
    login_otp_failed
    login_account_selected
    logout
    view
    download
    sign
    revoke
    message
    suspension_change
    invite_sent
    invite_accepted
  ].freeze

  belongs_to :account
  belongs_to :patient

  validates :action, presence: true

  # Atalho idempotente — não levanta exceção em produção; loga no Rails logger
  # para não derrubar a request principal por causa de uma falha de auditoria.
  def self.log!(account:, patient:, action:, resource: nil, ip: nil, user_agent: nil, metadata: {})
    create!(
      account:       account,
      patient:       patient,
      action:        action.to_s,
      resource_type: resource&.class&.name,
      resource_id:   resource&.id,
      ip:            ip,
      user_agent:    user_agent,
      metadata:      metadata
    )
  rescue StandardError => e
    Rails.logger.warn("[PatientPortalAccessLog] failed to log #{action}: #{e.message}")
    nil
  end
end
