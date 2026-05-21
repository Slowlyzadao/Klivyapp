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
    # `:high` — timer crítico de UX (5min após doutor entrar sem paciente).
    # Não pode atrás de TranscribeJob de 10min na mesma queue `:default`.
    # Audit Fase 2.
    queue_as :high

    def perform(event_id, doctor_joined_at_iso)
      event = AgendaEvent.find_by(id: event_id)
      return unless event

      # Validação + transição dentro de um único lock pessimista no event
      # — sem isso, o session/timestamp podia ser lido fora do lock e mudar
      # entre o check e o `mark_no_show!`, levando a no-show num evento
      # que o paciente já entrou (race fix do audit #32).
      event.with_lock do
        session = SessionTracker.new(event).session

        # Sessão de outro ciclo (doutor saiu e reentrou após este job ter
        # sido enfileirado) — descarta.
        return unless session.doctor_joined_at == parse_time(doctor_joined_at_iso)

        # Paciente chegou em algum momento — sai do escopo "no_show".
        return if session.patient_joined_at.present?

        StatusTransition.new(event).mark_no_show!
      end
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
