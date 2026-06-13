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

      # 2026-05-22 — Auto-trigger de gravação no `joined!` REMOVIDO.
      # Motivo: o orchestrator rodava no exato instante do join, antes do
      # microfone do paciente publicar o track de áudio. Resultado:
      # `list_participants` devolvia `patient.tracks = []`, TrackEgress por
      # participante não disparava (sem track_sid), e o recording era criado
      # só com o composite. Quando o doutor depois clicava "Gravar", o
      # orchestrator via o recording existente e dava `skip(:already_active)`
      # — TrackEgress NUNCA era tentado de novo → transcrição perdia
      # diarização (tudo virava 1 speaker "Participante").
      #
      # Agora gravação é 100% manual via `start_recording` controller. No
      # momento do clique, os 2 microfones já publicaram (latência típica
      # 500-2000ms após o join), então `list_participants` retorna tracks
      # completos e TrackEgress dispara corretamente. Casa com o comentário
      # já existente em `SessionsController#start_recording` que diz que o
      # doutor tem controle direto. Limpeza que faltava da Sprint L.
      # start_recording_if_needed(session)

      result(session, transition_result)
    end

    def left!
      session = @tracker.record_left!(@role, at: @now)
      transition_result = nil

      # 2026-05-21 — auto `mark_completed!` REMOVIDO. Antes, quando ambos
      # saíam E status era in_progress, o backend marcava completed
      # automaticamente. Problema: doutor podia ter ficado 5+ min tentando
      # admitir o paciente mas a chamada não rolou (internet do paciente
      # ruim, paciente entrou e saiu correndo). Auto-completed marcava
      # como "atendido" mesmo sem atendimento de fato.
      #
      # Agora: status permanece in_progress até o doutor confirmar via
      # `confirm_completed` (clica "Sim, atendi" no modal pós-encerramento).
      # Se ele responder "Não consegui", status fica em in_progress —
      # cabe ao doutor mudar manualmente pelo calendário (cancelado/no_show).
      #
      # Recording continua sendo finalizado aqui — a gravação ACABOU de
      # fato (LiveKit Egress tem que encerrar pro pipeline de transcrição/
      # evolução rodar). Independente de status do evento.
      #
      # 2026-05-22 — Doutor saindo encerra a gravação MESMO com paciente
      # ainda presente. Antes só parava em `nobody_present?`, mas se o
      # doutor encerrava antes do paciente desconectar, o Egress ficava
      # rodando sozinho (consumindo recurso e atrasando a transcrição).
      # Doutor = fim da consulta, sempre.
      if @event.status == 'in_progress' && (session.nobody_present? || @role == 'doctor')
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
