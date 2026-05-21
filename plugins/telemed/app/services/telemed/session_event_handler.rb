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
    MIN_BOTH_PRESENT_SECONDS = 5.minutes
    NO_SHOW_GRACE_SECONDS    = 5.minutes

    Result = Struct.new(:event, :session, :transition, :scheduled_jobs, :recording, keyword_init: true)

    def initialize(event:, role:, now: Time.current, recording_orchestrator: nil)
      @event = event
      @role  = role.to_s
      @now   = now
      @tracker    = SessionTracker.new(event)
      @transition = StatusTransition.new(event)
      @scheduled_jobs = []
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

      schedule_in_progress_job(session) if session.both_present?
      schedule_no_show_job(session)     if doctor_alone?(session)
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

    def schedule_in_progress_job(session)
      return unless session.both_started_at

      MarkInProgressJob
        .set(wait: MIN_BOTH_PRESENT_SECONDS)
        .perform_later(@event.id, session.both_started_at.iso8601)
      @scheduled_jobs << :mark_in_progress
    end

    def schedule_no_show_job(session)
      return unless session.doctor_joined_at

      MarkNoShowJob
        .set(wait: NO_SHOW_GRACE_SECONDS)
        .perform_later(@event.id, session.doctor_joined_at.iso8601)
      @scheduled_jobs << :mark_no_show
    end

    # Doutor entrou mas paciente ainda não chegou. Job de no_show só faz
    # sentido nesse caso — se paciente entrou primeiro e doutor depois,
    # já é uma consulta acontecendo, sem motivo pra agendar no_show.
    def doctor_alone?(session)
      @role == 'doctor' &&
        session.doctor_present? &&
        session.patient_joined_at.blank?
    end

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
      @scheduled_jobs << :start_recording if @recording_result&.started?
    rescue StandardError => e
      Rails.logger.error("[SessionEventHandler] start_recording_if_needed event=#{@event.id} #{e.class}: #{e.message}")
      # Engole pra não quebrar fluxo de joined! — consulta continua sem gravação.
    end

    def stop_recording_if_active
      recording = @event.telemed_recordings.where.not(status: %w[failed ready]).order(created_at: :desc).first
      return unless recording

      orchestrator = @recording_orchestrator || RecordingOrchestrator.new(event: @event)
      orchestrator.stop!(recording)
      @scheduled_jobs << :stop_recording
    rescue StandardError => e
      Rails.logger.error("[SessionEventHandler] stop_recording_if_active event=#{@event.id} #{e.class}: #{e.message}")
    end

    def result(session, transition_result)
      Result.new(
        event: @event,
        session: session,
        transition: transition_result,
        scheduled_jobs: @scheduled_jobs.dup,
        recording: @recording_result
      )
    end
  end
end
