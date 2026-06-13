# Endpoint público de feedback do paciente (👍/👎) sobre uma resposta
# específica da Bea. Autenticação por HMAC token: cada Trace gera um
# token único que vai pro widget junto com o trace_id. Frontend POSTa
# esse par + rating; backend valida o token antes de gravar.
#
# Idempotente: 1 feedback por trace_id (UNIQUE no banco se houver).
# Re-POSTa atualiza o feedback existente.
#
# Sem auth do Rails — é endpoint público de widget. Segurança vem
# do HMAC, não do session/cookie.
#
# SEC-28 (auditoria 2026-05-18): rate limit por IP via Redis. O HMAC já
# previne abuso direto (não dá pra forjar token sem ler do widget HTML),
# mas atacante que cole 1 token + rate-bombe POSTs (atualiza repetidas
# vezes o mesmo Feedback) pode degradar banco. Hard cap 60 req/min/IP.
class Api::V1::AiAgent::FeedbacksController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :verify_authenticity_token, raise: false

  RATE_LIMIT_PER_MIN = 60

  def create
    # SEC-28: rate limit antes de qualquer trabalho. Falha silenciosa se
    # Redis indisponível (fail-open) — não derruba feedback legítimo
    # durante incidente de infra.
    return render json: { error: 'rate_limited' }, status: :too_many_requests if rate_limit_exceeded?

    trace_id   = params[:trace_id]
    account_id = params[:account_id]
    token      = params[:token]
    rating     = params[:rating].to_i

    # SEC-11: token agora carrega account_id assinado + TTL. O cliente
    # precisa enviar account_id explicitamente; assinatura é validada
    # contra essa tripla {trace_id, account_id, issued_at}.
    unless ::AiAgent::FeedbackTokenSigner.verify(trace_id: trace_id, account_id: account_id, token: token)
      return render json: { error: 'invalid_token' }, status: :unauthorized
    end

    return render json: { error: 'rating must be 1 or -1' }, status: :unprocessable_entity unless [1, -1].include?(rating)

    # MT-2 fechado: lookup scoped pelo account_id que o cliente afirmou
    # (validado via HMAC acima). Trace de outra conta nunca é alcançado.
    trace = ::AiAgent::Trace.where(account_id: account_id).find_by(id: trace_id)
    return render json: { error: 'trace_not_found' }, status: :not_found if trace.nil?

    feedback = ::AiAgent::Feedback.find_or_initialize_by(trace_id: trace.id)
    feedback.assign_attributes(
      account_id: trace.account_id,
      conversation_id: trace.conversation_id,
      message_id: trace.message_id,
      contact_id: trace.contact_id,
      rating: rating,
      comment: params[:comment].to_s.strip[0, 500].presence
    )

    if feedback.save
      render json: { ok: true, id: feedback.id, rating: feedback.rating }, status: :ok
    else
      render json: { error: 'invalid', details: feedback.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  # SEC-28: Redis counter por IP por minuto. TTL 60s = janela rolante
  # simples. Falha silenciosa em Redis down (fail-open) — não bloqueia
  # feedback legítimo durante incidente.
  def rate_limit_exceeded?
    ip = request.remote_ip.to_s
    return false if ip.empty?

    key = "ai_agent:feedback_rl:#{ip}:#{Time.current.strftime('%Y%m%d%H%M')}"
    count = ::Redis::Alfred.incr(key)
    ::Redis::Alfred.expire(key, 70) if count == 1
    count > RATE_LIMIT_PER_MIN
  rescue StandardError => e
    Rails.logger.warn("[AiAgent::FeedbacksController] redis rate_limit check failed: #{e.class}: #{e.message}")
    false
  end
end
