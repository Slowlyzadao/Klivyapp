# Job Sidekiq: 5 minutos após o doutor entrar SEM o paciente, marca
# no_show (Sprint K).
#
# Enfileirado por SessionEventHandler quando o doutor conecta antes do
# paciente. Recebe o `doctor_joined_at` original — se o doutor saiu e
# voltou, o timestamp mudou e este job (do ciclo antigo) é obsoleto.
#
# Importante: se o paciente CHEGOU em algum momento (mesmo que tenha saído
# depois), NÃO é no-show. Só é no-show se o paciente nunca apareceu.
module Telemed
  class MarkNoShowJob < ApplicationJob
    queue_as :default

    def perform(event_id, doctor_joined_at_iso)
      event = AgendaEvent.find_by(id: event_id)
      return unless event

      tracker = SessionTracker.new(event)
      session = tracker.session

      # Sessão de outro ciclo (doutor saiu e reentrou após este job ter
      # sido enfileirado) — descarta.
      return unless session.doctor_joined_at == parse_time(doctor_joined_at_iso)

      # Paciente chegou em algum momento — sai do escopo "no_show".
      return if session.patient_joined_at.present?

      StatusTransition.new(event).mark_no_show!
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
