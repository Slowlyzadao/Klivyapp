# Job Sidekiq: 5 minutos após "ambos conectados", marca status como
# in_progress (Sprint K).
#
# Enfileirado por SessionEventHandler quando detecta `both_started_at`
# pela primeira vez. Recebe o `both_started_at` original como argumento
# pra validar que a sessão ainda é a mesma — se o paciente saiu e voltou,
# `both_started_at` foi renovado no SessionTracker e este job (do ciclo
# antigo) torna-se obsoleto e não deve transicionar.
#
# Idempotente: rodar 2x não causa dano. StatusTransition já valida que só
# transiciona de `arrived` → `in_progress` (idempotente nas chamadas
# subsequentes).
module Telemed
  class MarkInProgressJob < ApplicationJob
    queue_as :default

    # Tolerância: se o job rodar levemente antes dos 5min (Sidekiq pode
    # antecipar alguns segundos), aceitamos com 30s de folga.
    TOLERANCE_SECONDS = 30

    def perform(event_id, both_started_at_iso)
      event = AgendaEvent.find_by(id: event_id)
      return unless event

      tracker = SessionTracker.new(event)
      session = tracker.session

      # Sessão diferente — usuário saiu e voltou, both_started_at foi
      # renovado. Outro job (do novo ciclo) cuida agora.
      return unless session.both_started_at == parse_time(both_started_at_iso)

      # Ambos ainda presentes? Se alguém saiu nesse meio tempo, o
      # SessionEventHandler já cuidou (ou não — fica em arrived até voltar).
      return unless session.both_present?

      # Sanity: tempo mínimo decorrido. Defesa caso Sidekiq antecipe.
      elapsed = Time.current - session.both_started_at
      return if elapsed < (SessionEventHandler::MIN_BOTH_PRESENT_SECONDS - TOLERANCE_SECONDS.seconds)

      StatusTransition.new(event).mark_in_progress!
    end

    private

    def parse_time(value)
      return value if value.is_a?(Time)

      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
