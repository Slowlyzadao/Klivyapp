module AiAgent
  module FollowUps
    # Stateless: dado uma `FollowUpRule`, retorna a lista de candidatos
    # elegíveis NESSE momento. O dispatcher chama em loop pra cada rule
    # enabled e enfileira `SendFollowUpJob` pra cada candidato.
    #
    # Cada candidato é um Hash com:
    #   { contact_id:, conversation_id:, agenda_event_id:, target_at: }
    #
    # Janela de elegibilidade: o cron roda a cada 15min. O finder pega
    # candidatos cujo `target_at` cai dentro de [now - 15min, now + 15min].
    # Janela ampla evita perder disparos por jitter do scheduler, e a
    # idempotência via UNIQUE no banco impede duplicação.
    #
    # Filtros transversais (todos os triggers):
    #   - Bea habilitada na conta (resolver.enabled?)
    #   - Contato sem `recall_opt_out` em PatientMemory.preferences
    #   - Cap de execuções por alvo (rule.max_per_target)
    #   - Não recriar uma execution pendente já existente (idempotência
    #     no nível do app — backstop ao UNIQUE do banco)
    class CandidateFinder
      # Janela ±1min em torno do `target_at`. Casa com a frequência do
      # cron (1min). Idempotência via UNIQUE no banco impede duplicação
      # caso o cron jitter empurre dois ticks pro mesmo registro.
      WINDOW_MINUTES = 1

      def initialize(rule, now: Time.current)
        @rule = rule
        @now = now
      end

      def call
        return [] unless rule_active?

        candidates = case @rule.trigger_type
                     when 'pre_appointment'  then find_pre_appointment
                     when 'post_appointment' then find_post_appointment
                     when 'no_response'      then find_no_response
                     when 'no_show'          then find_no_show
                     else []
                     end

        candidates
          .reject { |c| opted_out?(c[:contact_id]) }
          .reject { |c| cap_reached?(c) }
          .reject { |c| already_executed?(c) }
      end

      private

      def rule_active?
        return false unless @rule.enabled
        return false if @rule.account.nil?

        AiAgent::ConfigResolver.new(@rule.account).enabled?
      rescue StandardError
        false
      end

      # ── triggers ────────────────────────────────────────────────────

      # N horas ANTES de AgendaEvent.starts_at. Pega eventos cujo starts_at
      # está em torno de (now + offset). Status default = scheduled/confirmed
      # (pode ser sobrescrito por `status_filter`).
      def find_pre_appointment
        return [] unless defined?(::AgendaEvent)

        target_window = window_around(@now + @rule.offset_seconds.seconds)
        statuses = filter_statuses(default: %w[scheduled confirmed])

        scope = ::AgendaEvent.where(account_id: @rule.account_id)
                             .where(status: statuses)
                             .where(starts_at: target_window)
                             .where.not(contact_id: nil)
        scope = filter_by_source(scope)
        scope.pluck(:id, :starts_at, :contact_id).map do |event_id, starts_at, contact_id|
          {
            contact_id: contact_id,
            conversation_id: nil,
            agenda_event_id: event_id,
            target_at: starts_at - @rule.offset_seconds.seconds
          }
        end
      end

      # N horas DEPOIS do starts_at — útil pra "como foi sua consulta?",
      # NPS, reagendamento de no_show, etc.
      def find_post_appointment
        return [] unless defined?(::AgendaEvent)

        target_window = window_around(@now - @rule.offset_seconds.seconds)
        statuses = filter_statuses(default: %w[completed no_show])

        scope = ::AgendaEvent.where(account_id: @rule.account_id)
                             .where(status: statuses)
                             .where(starts_at: target_window)
                             .where.not(contact_id: nil)
        scope = filter_by_source(scope)
        scope.pluck(:id, :starts_at, :contact_id).map do |event_id, starts_at, contact_id|
          {
            contact_id: contact_id,
            conversation_id: nil,
            agenda_event_id: event_id,
            target_at: starts_at + @rule.offset_seconds.seconds
          }
        end
      end

      # Atalho de post_appointment, status filtrado em no_show. Mantido
      # como trigger separado pra ficar legível na UI ("Reagendar quem
      # faltou") e permitir cooldown próprio.
      def find_no_show
        return [] unless defined?(::AgendaEvent)

        target_window = window_around(@now - @rule.offset_seconds.seconds)

        scope = ::AgendaEvent.where(account_id: @rule.account_id, status: 'no_show')
                             .where(starts_at: target_window)
                             .where.not(contact_id: nil)
        scope = filter_by_source(scope)
        scope.pluck(:id, :starts_at, :contact_id).map do |event_id, starts_at, contact_id|
          {
            contact_id: contact_id,
            conversation_id: nil,
            agenda_event_id: event_id,
            target_at: starts_at + @rule.offset_seconds.seconds
          }
        end
      end

      # Aplica o filtro `applies_to` (Bea / humano / ambos) na query da
      # agenda. Quando 'both', `agenda_source_filter` é nil — segue sem
      # filtrar. Pra `no_response` e `custom` essa função nem é chamada
      # (não há AgendaEvent envolvido).
      def filter_by_source(scope)
        sources = @rule.agenda_source_filter
        return scope if sources.nil?

        scope.where(source: sources)
      end

      # Conversa em que o último incoming foi há mais de offset_hours e
      # NENHUM outgoing posterior — paciente parou de responder antes
      # de fechar. Janela ampla pra pegar a primeira oportunidade depois
      # do offset; cap_reached? evita bombardeio.
      def find_no_response
        return [] unless defined?(::Conversation) && defined?(::Message)

        cutoff = @now - @rule.offset_seconds.seconds

        # Última mensagem por conversa (incoming OR outgoing).
        # `.reorder(nil)` limpa o default_scope `order(created_at: :asc)`
        # do `Message`, que conflitaria com o GROUP BY (PG exige que
        # toda coluna do ORDER BY apareça no GROUP BY ou seja agregada).
        last_msgs = ::Message
                    .reorder(nil)
                    .joins(:conversation)
                    .where(conversations: { account_id: @rule.account_id, status: 'open' })
                    .where(message_type: %i[incoming outgoing])
                    .where(private: false)
                    .where('messages.created_at <= ?', cutoff)
                    .group(:conversation_id)
                    .pluck('conversation_id', 'MAX(messages.created_at)', 'MAX(messages.id)')

        # Pra cada conversa, garantir que a ÚLTIMA mensagem é incoming
        # (paciente). Se for outgoing (Bea/agente respondendo), não é
        # candidata.
        candidates = []
        last_msgs.each do |conv_id, _max_created_at, max_id|
          last = ::Message.find_by(id: max_id)
          next unless last && last.message_type == 'incoming'

          conversation = ::Conversation.find_by(id: conv_id)
          next unless conversation

          candidates << {
            contact_id: conversation.contact_id,
            conversation_id: conv_id,
            agenda_event_id: nil,
            target_at: last.created_at + @rule.offset_seconds.seconds
          }
        end

        candidates
      end

      # ── filtros transversais ────────────────────────────────────────

      def opted_out?(contact_id)
        return false if contact_id.blank?

        mem = AiAgent::PatientMemory.find_by(account_id: @rule.account_id, contact_id: contact_id)
        return false if mem.nil?

        prefs = mem.preferences || {}
        prefs['recall_opt_out'] || prefs['follow_up_opt_out']
      end

      def cap_reached?(candidate)
        return false if @rule.max_per_target.to_i.zero?

        scope = AiAgent::FollowUpExecution
                .where(rule_id: @rule.id, status: 'sent')
                .where(contact_id: candidate[:contact_id])
        scope = scope.where(agenda_event_id: candidate[:agenda_event_id]) if candidate[:agenda_event_id]
        scope.count >= @rule.max_per_target.to_i
      end

      def already_executed?(candidate)
        AiAgent::FollowUpExecution.exists?(
          rule_id: @rule.id,
          contact_id: candidate[:contact_id],
          agenda_event_id: candidate[:agenda_event_id],
          target_at: candidate[:target_at]
        )
      end

      def filter_statuses(default:)
        list = @rule.status_filter['allowed'] || @rule.status_filter[:allowed]
        return default if list.blank?

        Array(list).map(&:to_s)
      end

      def window_around(time)
        (time - WINDOW_MINUTES.minutes)..(time + WINDOW_MINUTES.minutes)
      end
    end
  end
end
