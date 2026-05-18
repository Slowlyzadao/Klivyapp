module AiAgent
  # Assina/valida tokens HMAC pra autorizar feedback público sem login.
  #
  # Fluxo:
  #   1. Quando a Bea posta uma resposta, o widget recebe (no payload da
  #      mensagem) o `trace_id` + `feedback_token = sign(trace_id)`
  #   2. Paciente clica 👍/👎 → frontend POST /api/v1/ai_agent/feedback
  #      com trace_id + token + rating
  #   3. Backend valida o token via `verify` antes de gravar
  #
  # Sem isso, qualquer um podia POSTar feedback falso pra envenenar CSAT.
  # O HMAC usa `secret_key_base` — gira automaticamente quando o app
  # gira credentials, invalidando tokens antigos.
  #
  # Nome fora do namespace `AiAgent::Feedback` porque esse já é o model.
  # Mantemos o signer flat aqui pra evitar conflito Zeitwerk.
  class FeedbackTokenSigner
    ALGO = 'SHA256'.freeze

    def self.sign(trace_id)
      OpenSSL::HMAC.hexdigest(ALGO, secret, trace_id.to_s)
    end

    def self.verify(trace_id, token)
      return false if trace_id.blank? || token.blank?

      ActiveSupport::SecurityUtils.secure_compare(sign(trace_id), token.to_s)
    end

    def self.secret
      Rails.application.secret_key_base.to_s
    end
  end
end
