# Orquestrador de eventos de sessão da teleconsulta (Sprint K).
#
# Recebe `joined`/`left` do cliente (frontend reporta) e decide:
#   - qual transição de status disparar (via StatusTransition)
#   - quais jobs Sidekiq enfileirar (timer de in_progress / no_show)
#
# Isolar essa decisão num serviço dedicado:
#   - controllers ficam thin (uma chamada só)
#   - regras de fluxo são testáveis sem stub HTTP
#   - quando migrar pro webhook do LiveKit, só troca o caller — service
#     continua o mesmo
#
# Regras automáticas implementadas:
#   - paciente conectou:                       confirmed → arrived
#   - doutor sozinho ≥ 5min sem paciente:      confirmed → no_show (job)
#   - ambos conectados ≥ 5min ininterruptos:   arrived   → in_progress (job)
#   - ambos sairam após in_progress:           in_progress → completed
module Telemed
  class SessionEventHandler
    # Constantes proxy mantidas pra compat com callers existentes
    # (MarkInProgressJob lê `SessionEventHandler::MIN_BOTH_PRESENT_SECONDS`).
    # Fonte da verdade é o SessionJobScheduler.
    MIN_BOTH_PRESENT_SECONDS = SessionJobScheduler::MIN_BOTH_PRESENT_SECONDS
    NO_SHOW_GRACE_SECONDS    = SessionJobScheduler::NO_SHOW_GRACE_SECONDS

    Result = Struct.new(:event, :session, :transition, :scheduled_jobs, :recording, keyword_init: true)

    def initialize(event:, role:, now: Time.current, recording_orchestrator: nil)
      @event = event
      @role  = role.to_s
      @now   = now
      @tracker    = SessionTracker.new(event)
      @transition = StatusTransition.new(event)
      @scheduler  = SessionJobScheduler.new(event: @event)
      # Sprint L — injetável pra testes; default constrói o orchestrator
      # quando ambos os participantes estiverem na sala. nil → sem gravação.
      @recording_orchestrator = recording_orchestrator
      @recording_result = nil
      validate_role!
    end

    def joined!
      session = @tracker.record_joined!(@role, at: @now)
      transition_result = nil

      if @role == 'patient'
        # Paciente entrou → marca arrived. Idempotente — se já estava
        # arrived ou além (in_progress), `transition!` retorna noop.
        transition_result = @transition.mark_arrived!
      end

      # Decisões de scheduling delegadas (audit Fase 3 — extração).
      @scheduler.schedule_in_progress_if_both_present(session)
      @scheduler.schedule_no_show_if_doctor_alone(session, joining_role: @role)

      # Sprint L — dispara gravação no momento em que ambos chegam.
      # Idempotente (RecordingOrchestrator pula se já tem gravação ativa).
      start_recording_if_needed(session)

      result(session, transition_result)
    end

    def left!
      session = @tracker.record_left!(@role, at: @now)
      transition_result = nil

      # Encerramento natural: ambos saíram E a sessão chegou a ser
      # in_progress (ou seja, doutor + paciente conversaram ≥ 5min). Sem
      # esse guard, sair antes do timer marcaria a consulta como
      # completed sem ter atendido.
      if session.nobody_present? && @event.status == 'in_progress'
        transition_result = @transition.mark_completed!
        # Sprint L — encerra LiveKit Egress. Webhook do LiveKit finaliza
        # upload no R2 e enfileira TranscribeRecordingJob.
        stop_recording_if_active
      end

      result(session, transition_result)
    end

    private

    def validate_role!
      return if %w[doctor patient].include?(@role)

      raise ArgumentError, "role inválido: #{@role.inspect}"
    end

    # Sprint L — chamado quando session.both_present? vira true (segundo
    # participante a entrar). Construímos o orchestrator apenas neste
    # momento pra evitar tocar em LiveKit/R2 em saves sem ambos presentes.
    # Erros não-fatais: gravação nunca pode quebrar joined!/left!.
    def start_recording_if_needed(session)
      return unless session.both_present?
      return if @event.telemed_recordings.where.not(status: %w[failed ready]).exists?

      orchestrator = @recording_orchestrator || RecordingOrchestrator.new(event: @event)
      @recording_result = orchestrator.start!
      @scheduler.scheduled << :start_recording if @recording_result&.started?
    rescue StandardError => e
      Rails.logger.error("[SessionEventHandler] start_recording_if_needed event=#{@event.id} #{e.class}: #{e.message}")
      # Engole pra não quebrar fluxo de joined! — consulta continua sem gravação.
    end

    def stop_recording_if_active
      recording = @event.telemed_recordings.where.not(status: %w[failed ready]).order(created_at: :desc).first
      return unless recording

      orchestrator = @recording_orchestrator || RecordingOrchestrator.new(event: @event)
      orchestrator.stop!(recording)
      @scheduler.scheduled << :stop_recording
    rescue StandardError => e
      Rails.logger.error("[SessionEventHandler] stop_recording_if_active event=#{@event.id} #{e.class}: #{e.message}")
    end

    def result(session, transition_result)
      Result.new(
        event: @event,
        session: session,
        transition: transition_result,
        scheduled_jobs: @scheduler.scheduled.dup,
        recording: @recording_result
      )
    end
  end
end
