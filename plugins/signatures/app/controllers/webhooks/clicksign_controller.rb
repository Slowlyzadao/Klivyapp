# frozen_string_literal: true

# Webhook receiver pra eventos do Clicksign. Skeleton: parsing + validação
# HMAC + dispatch das transições. HTTP real do Clicksign fica pra próxima
# sessão — por ora aceita POST e registra no log pra inspeção.
#
# Endpoint público (sem auth) — segurança baseada em HMAC compartilhado.
#
# Eventos comuns do Clicksign v3:
#   - envelope.opened     (signer abriu o link) → mark_viewed!
#   - envelope.signed     (signer completou)    → mark_signed!
#   - envelope.completed  (todos os signers assinaram + doc final disponível)
#                         → enqueue job pra baixar PDF + mark_completed!
#   - envelope.cancelled
#   - envelope.refused
class Webhooks::ClicksignController < ActionController::API
  before_action :verify_signature

  def process_payload
    event = params[:event].to_s
    envelope_id = params.dig(:data, :envelope, :id) || params[:envelope_id]

    Rails.logger.info("[Clicksign webhook] event=#{event} envelope=#{envelope_id}")

    request = SignatureRequest.find_by(provider: 'clicksign', external_id: envelope_id)
    return head :ok unless request # idempotente quando envelope desconhecido

    dispatch_event(request, event)
    head :ok
  rescue StandardError => e
    Rails.logger.error("[Clicksign webhook] #{e.class}: #{e.message}")
    head :unprocessable_entity
  end

  private

  def dispatch_event(request, event)
    case event
    when 'envelope.opened', 'document.viewed'
      request.mark_viewed!(meta: { event: event, payload: webhook_meta }) unless request.viewed?
    when 'envelope.signed', 'document.signed'
      request.mark_signed!(meta: { event: event, payload: webhook_meta })
    when 'envelope.completed', 'auto_close'
      # TODOS os signers assinaram. Enfileira o job que baixa o PDF final
      # do provider, atualiza signed_pdf_hash, substitui o file attachment
      # do Document e marca como completed. Job é idempotente.
      request.append_audit!(kind: 'completed.queued', meta: { event: event })
      ::Signatures::DownloadSignedPdfJob.perform_later(request.id)
    when 'envelope.cancelled'
      request.mark_cancelled!(reason: 'cancelled at provider', meta: { event: event })
    when 'envelope.refused'
      request.mark_failed!(reason: 'signer refused', meta: { event: event })
    else
      request.append_audit!(kind: "unknown.#{event}", meta: webhook_meta)
    end
  end

  def webhook_meta
    {
      remote_ip: request.remote_ip,
      user_agent: request.user_agent,
      received_at: Time.current.iso8601
    }
  end

  # Validação HMAC do webhook Clicksign.
  # Próxima sessão: implementar conforme docs do Clicksign:
  #   HMAC-SHA256(body) com chave `CLICKSIGN_WEBHOOK_SECRET`,
  #   comparada com header `Content-Hmac` ou `X-Hub-Signature`.
  def verify_signature
    secret = ENV['CLICKSIGN_WEBHOOK_SECRET']
    if secret.blank?
      # Fail-CLOSED em produção: sem segredo configurado, rejeita (não dá
      # pra confiar no payload). Em dev/test aceita pra facilitar testes
      # locais com o MockProvider, que não dispara webhook real.
      return unless Rails.env.production?

      Rails.logger.error('[Clicksign webhook] CLICKSIGN_WEBHOOK_SECRET ausente em produção — rejeitando')
      return head :unauthorized
    end

    received = request.headers['Content-Hmac'].to_s.sub(/^sha256=/, '')
    expected = OpenSSL::HMAC.hexdigest('sha256', secret, request.raw_post)

    return if ActiveSupport::SecurityUtils.secure_compare(received, expected)

    Rails.logger.warn('[Clicksign webhook] HMAC inválido — rejeitando')
    head :unauthorized
  end
end
