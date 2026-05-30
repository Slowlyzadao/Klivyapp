# State machine de status do AgendaEvent dirigida pela telemedicina (Sprint K).
#
# Responsabilidade ÚNICA: validar transições permitidas e aplicar com lock.
# Não conhece HTTP, jobs, ou jsonb tracking. Quem decide QUANDO chamar é o
# SessionEventHandler ou os jobs Sidekiq — este service só sabe se a
# transição é válida e como persistir atomicamente.
#
# Regras (subset do fluxo manual, intencional — auto só pode "andar pra
# frente" no caminho linear scheduled → confirmed → arrived → in_progress
# → completed; OU pular pra no_show de scheduled/confirmed):
#
#   transição     ← origens permitidas
#   confirmed     ← scheduled, confirmed (idempotente)
#   arrived       ← scheduled, confirmed, arrived
#   in_progress   ← arrived, in_progress
#   completed     ← in_progress, completed
#   no_show       ← scheduled, confirmed, no_show
#
# Cenários NÃO permitidos pelo automatismo (mesmo se chamados):
#   - regredir (in_progress → arrived) — bug? cliente recém-conectou? ignora
#   - sair de completed/cancelled — eventos encerrados ficam encerrados
#   - cancelled, completed manualmente pelo doutor → automatismo não toca
#
# Idempotência: chamar transition!('arrived') 2x no mesmo evento retorna
# true das duas vezes mas só persiste a primeira. Crítico porque a UI pode
# disparar `joined` várias vezes (refresh, reconnect).
module Telemed
  class StatusTransition
    # Mapa "destino → origens válidas". Inclui o próprio destino pra
    # tornar idempotente sem código extra (mark_arrived!() chamado 2x).
    ALLOWED_FROM = {
      'confirmed'   => %w[scheduled confirmed].freeze,
      'arrived'     => %w[scheduled confirmed arrived].freeze,
      'in_progress' => %w[arrived in_progress].freeze,
      'completed'   => %w[in_progress completed].freeze,
      'no_show'     => %w[scheduled confirmed no_show].freeze
    }.freeze

    Result = Struct.new(:transitioned, :from, :to, :reason, keyword_init: true) do
      def success? = !!transitioned
      def noop?    = !transitioned && reason == :already_in_target
    end

    def initialize(event)
      @event = event
    end

    # Aplica a transição se as regras permitirem. Retorna `Result` (struct
    # com `transitioned: bool, from:, to:, reason:`). NUNCA levanta
    # exceção pra controle de fluxo — chamadores podem só checar success?.
    def transition!(new_status, source: nil)
      return invalid_target(new_status) unless ALLOWED_FROM.key?(new_status.to_s)

      @event.with_lock do
        current = @event.status

        # Evento descartado (soft-delete) não transiciona. Mesmo se o
        # cliente reportou conexão, não vamos reanimar evento cancelado.
        return rejected(current, new_status, :discarded) if @event.try(:discarded?)

        return already_target(current) if current == new_status.to_s
        return rejected(current, new_status, :not_allowed) unless allowed?(current, new_status)

        @event.update!(status: new_status.to_s)
        clear_admissions_if_final(new_status.to_s)
        log_transition(current, new_status.to_s, source)
        ok(current, new_status.to_s)
      end
    end

    def mark_arrived!(source: 'telemed_joined')
      transition!('arrived', source: source)
    end

    def mark_in_progress!(source: 'telemed_5min_both')
      transition!('in_progress', source: source)
    end

    def mark_completed!(source: 'telemed_left')
      transition!('completed', source: source)
    end

    def mark_no_show!(source: 'telemed_5min_no_patient')
      transition!('no_show', source: source)
    end

    private

    def allowed?(current, new_status)
      ALLOWED_FROM.fetch(new_status.to_s, []).include?(current.to_s)
    end

    # 2026-05-22 — Admissões server-side ficam por evento em
    # custom_attributes. Quando o evento entra em estado final, limpa
    # pra que se um dia o mesmo agenda_event_id for reaberto (caso
    # raro, mas possível via UI de undo), não venha com admissão
    # antiga grudada. A leitura via AdmissionWindow JÁ rejeita
    # admissão em status final — esse cleanup é defesa em profundidade
    # + economia de JSON.
    def clear_admissions_if_final(new_status)
      return unless AdmissionWindow::FINAL_STATUSES.include?(new_status)
      AdmissionWindow.clear_for!(@event)
    end

    def log_transition(from, to, source)
      Rails.logger.info(
        "[Telemed::StatusTransition] event_id=#{@event.id} #{from}→#{to} source=#{source}"
      )
    end

    def ok(from, to)
      Result.new(transitioned: true, from: from, to: to, reason: :transitioned)
    end

    def already_target(current)
      Result.new(transitioned: false, from: current, to: current, reason: :already_in_target)
    end

    def rejected(current, target, reason)
      Result.new(transitioned: false, from: current, to: target.to_s, reason: reason)
    end

    def invalid_target(target)
      Result.new(transitioned: false, from: @event.status, to: target.to_s, reason: :invalid_target)
    end
  end
end
