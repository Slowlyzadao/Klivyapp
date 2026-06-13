# Audit Fase 3 — extraído de SessionEventHandler (audit #10.14: god
# service com 3 responsabilidades + scheduler embutido).
#
# Responsabilidade única: dado um `session` snapshot (de SessionTracker),
# decidir quais timers Sidekiq agendar pra automação de status.
#
# Antes vivia inline em `SessionEventHandler#schedule_*_job` — sem isso
# qualquer teste do handler precisava stubar ActiveJob test_helper, e
# qualquer mudança nas regras de tempo (5min, no-show grace, etc.) mexia
# direto no handler.
#
# Regras encapsuladas aqui:
#   - MIN_BOTH_PRESENT_SECONDS: tempo "ininterrupto" pra contar in_progress
#   - NO_SHOW_GRACE_SECONDS: tempo doutor sozinho antes de no_show
module Telemed
  class SessionJobScheduler
    # 2026-05-21 — reduzido de 5 → 2 min a pedido do usuário. Cobre casos
    # em que a consulta arranca rápido (paciente + doutor já presentes
    # 1-2 min de check-in) e o status do calendário precisa refletir
    # "em atendimento" antes do 5º minuto.
    MIN_BOTH_PRESENT_SECONDS = 2.minutes
    NO_SHOW_GRACE_SECONDS    = 5.minutes

    def initialize(event:)
      @event = event
      @scheduled = []
    end

    # Lista dos jobs realmente agendados nesta chamada — útil pra logs e
    # retorno via Result do SessionEventHandler.
    attr_reader :scheduled

    # Chamado após `joined!` quando ambos chegam à sala. Idempotente em
    # essência: rerun com a mesma session → Sidekiq aceita os jobs novos
    # mas a validação no MarkInProgressJob (compara both_started_at)
    # garante que só o ciclo atual transiciona.
    def schedule_in_progress_if_both_present(session)
      return unless session.both_present?
      return unless session.both_started_at

      MarkInProgressJob
        .set(wait: MIN_BOTH_PRESENT_SECONDS)
        .perform_later(@event.id, session.both_started_at.iso8601)
      @scheduled << :mark_in_progress
    end

    # Chamado após `joined!` quando doutor entra antes do paciente.
    # Valida origem (doctor) + paciente ausente — caso contrário não faz
    # sentido enfileirar no_show.
    def schedule_no_show_if_doctor_alone(session, joining_role:)
      return unless joining_role == 'doctor'
      return unless session.doctor_present?
      return if session.patient_joined_at.present?
      return unless session.doctor_joined_at

      MarkNoShowJob
        .set(wait: NO_SHOW_GRACE_SECONDS)
        .perform_later(@event.id, session.doctor_joined_at.iso8601)
      @scheduled << :mark_no_show
    end
  end
end
