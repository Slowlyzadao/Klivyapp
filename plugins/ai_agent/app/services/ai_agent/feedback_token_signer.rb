# Assina/valida tokens HMAC pra autorizar feedback público sem login.
#
# Fluxo:
#   1. Quando a Bea posta uma resposta, o widget recebe (no payload da
#      mensagem) o `trace_id`, `account_id` e
#      `feedback_token = sign(trace_id:, account_id:)`
#   2. Paciente clica 👍/👎 → frontend POST /api/v1/ai_agent/feedback
#      com trace_id + account_id + token + rating
#   3. Backend valida o token via `verify` antes de gravar
#
# Sem isso, qualquer um podia POSTar feedback falso pra envenenar CSAT.
# O HMAC usa `secret_key_base` — gira automaticamente quando o app
# gira credentials, invalidando tokens antigos.
#
# Bindings de segurança (SEC-11, auditoria 2026-05-18):
#   - account_id no payload assinado: bloqueia forja inter-tenant. Mesmo
#     que atacante saiba um `trace_id` válido de outra clínica, não
#     consegue gerar token cujo account_id bata.
#   - issued_at no payload + max_age: bloqueia replay indefinido. Padrão
#     de 7 dias é folga pra patient devolver feedback na mesma semana
#     em que recebeu a resposta da Bea.
#
# Formato do token: `v1:<account_id>:<issued_at_unix>:<hex32>` — versionado
# pra permitir bump futuro do esquema sem invalidar tokens em vôo.
#
# Nome fora do namespace `AiAgent::Feedback` porque esse já é o model.
# Mantemos o signer flat aqui pra evitar conflito Zeitwerk.
class AiAgent::FeedbackTokenSigner
  ALGO = 'SHA256'.freeze
  VERSION = 'v1'.freeze
  DEFAULT_MAX_AGE = 7.days

  def self.sign(trace_id:, account_id:, issued_at: Time.current)
    issued_at_unix = issued_at.to_i
    digest = OpenSSL::HMAC.hexdigest(ALGO, secret, canonical_payload(trace_id, account_id, issued_at_unix))
    "#{VERSION}:#{account_id}:#{issued_at_unix}:#{digest}"
  end

  def self.verify(trace_id:, account_id:, token:, max_age: DEFAULT_MAX_AGE)
    return false if trace_id.blank? || account_id.blank? || token.blank?

    parts = token.to_s.split(':', 4)
    return false unless parts.size == 4
    return false unless parts[0] == VERSION

    token_account_id = parts[1]
    issued_at = parts[2].to_i
    token_digest = parts[3]

    # account_id no token deve bater com o que o cliente afirmou no request
    return false unless token_account_id.to_s == account_id.to_s
    return false if issued_at <= 0
    # TTL — rejeita tokens muito antigos pra impedir replay indefinido
    return false if (Time.current.to_i - issued_at) > max_age.to_i

    expected_digest = OpenSSL::HMAC.hexdigest(ALGO, secret, canonical_payload(trace_id, account_id, issued_at))
    ActiveSupport::SecurityUtils.secure_compare(expected_digest, token_digest)
  end

  def self.canonical_payload(trace_id, account_id, issued_at_unix)
    "#{VERSION}:#{account_id}:#{trace_id}:#{issued_at_unix}"
  end

  def self.secret
    Rails.application.secret_key_base.to_s
  end
end
