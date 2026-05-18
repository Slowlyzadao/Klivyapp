module InternalChat
  # Centraliza emissão de eventos de telemetria do chat interno. Hoje só
  # escreve no Rails.logger com prefixo padronizado — o pipeline de analytics
  # do app pode plugar aqui depois sem que os call sites mudem.
  #
  # Convenção: payload sempre tem account_id pra agregação multi-tenant.
  class Telemetry
    EVENTS = %w[
      room_created
      message_sent
      mention_received
      attachment_uploaded
      room_archived
      room_muted
    ].freeze

    def self.track(event, payload = {})
      return unless EVENTS.include?(event.to_s)

      data = { event: "internal_chat.#{event}" }.merge(payload).compact
      Rails.logger.info("[InternalChat::Telemetry] #{data.to_json}")
    rescue StandardError => e
      Rails.logger.warn("[InternalChat::Telemetry] falha ao registrar #{event}: #{e.class}: #{e.message}")
    end
  end
end
