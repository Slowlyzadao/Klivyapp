module AiAgent
  # Single-agent orchestrator. Given an account, a conversation_id, a contact
  # and the latest user message, runs one full LLM turn (with tool calling)
  # and returns the agent's reply plus telemetry.
  #
  # This is the entry point used by the webhook dispatcher (Phase 4) and by
  # any internal caller (smoke tests, CLI, future API endpoint).
  class ChatService
    Context = Struct.new(:account, :conversation_state, :patient_memory, :contact_id, keyword_init: true)
    Result  = Struct.new(:message, :tool_executions, :usage, :state, :handoff,
                         :trace, keyword_init: true)

    DEFAULT_GEMINI_MODEL = 'gemini-3-flash-preview'.freeze
    DEFAULT_OPENAI_MODEL = 'gpt-4.1-mini'.freeze

    def initialize(account:, conversation_id:, contact_id: nil, history: [])
      @account = account
      @conversation_id = conversation_id
      @contact_id = contact_id
      @history = history
      @resolver = AiAgent::ConfigResolver.new(account)
    end

    def respond(user_message, message_id: nil)
      raise ArgumentError, 'user_message blank' if user_message.to_s.strip.empty?
      raise BeaDisabledError, 'Bea is not enabled for this account' unless @resolver.enabled?
      raise BudgetExceededError, 'monthly cost cap reached' if @resolver.over_monthly_cost_cap?

      @last_message_id_for_repeat_tracking = message_id

      ::Llm::Config.initialize!

      state   = AiAgent::ConversationState.for(account: @account, conversation_id: @conversation_id)
      memory  = @contact_id ? AiAgent::PatientMemory.for(account: @account, contact_id: @contact_id) : nil
      context = Context.new(
        account: @account,
        conversation_state: state,
        patient_memory: memory,
        contact_id: @contact_id
      )

      started_at = Time.current
      track_message_repetition(state, user_message)
      apply_sentiment(state, user_message)

      # Camada de emergência determinística. Mount Sinai 2026 / Nature
      # Medicine: LLMs subdiagnosticam 52% das emergências reais. Por
      # isso classificamos via keyword PT-BR ANTES do LLM ver — risco
      # de vida não delega. Resposta-template fixa (SAMU 192 / CVV 188)
      # + escala humana imediata, latência < 100ms.
      if (emergency = AiAgent::Emergency::Detector.new(user_message).call)
        return emergency_short_circuit(state, emergency, started_at)
      end

      # Tom ofensivo do paciente — Bea continua respondendo normalmente
      # (não silencia, não escala), mas notifica equipe interna pra
      # eventual intervenção. Dedupe em janela de 30min no notifier.
      if (offensive = AiAgent::Detectors::OffensiveTone.new(user_message).call)
        AiAgent::InternalNotifier::OffensiveToneAlert.call(
          account: @account,
          conversation: ::Conversation.find_by(id: @conversation_id),
          contact: ::Contact.find_by(id: @contact_id),
          terms: offensive.terms
        )
      end

      # Pedido de estorno/reembolso/contestação. Notifica financeiro;
      # Bea segue respondendo normalmente. Dedupe em janela de 1h.
      if (refund = AiAgent::Detectors::RefundRequest.new(user_message).call)
        AiAgent::InternalNotifier::RefundRequestAlert.call(
          account: @account,
          conversation: ::Conversation.find_by(id: @conversation_id),
          contact: ::Contact.find_by(id: @contact_id),
          terms: refund.terms,
          summary: refund.summary
        )
      end

      # Opt-out de recall proativo. Se paciente respondeu "NÃO" / "PARE"
      # / "STOP" dentro de 7 dias após ProactiveOutreachJob ter enviado
      # uma mensagem de recall, marca preferências e responde
      # determinísticamente. RecallFinder respeita esse flag em runs
      # futuros — paciente não recebe mais lembretes proativos.
      if memory && recall_opt_out_response?(user_message, memory)
        return recall_opt_out_short_circuit(state, memory, started_at)
      end

      return captain_quota_handoff(state, started_at) if captain_quota_exhausted?

      escalation = AiAgent::Humanization::EscalationRules.new(state, last_user_message: user_message).evaluate
      return early_handoff(state, escalation, started_at) if escalation.escalate?

      # State machine determinístico: se paciente respondeu uma confirmação
      # curta ("sim", "ok", etc) e há uma oferta pendente que a Bea acabou
      # de fazer no turno anterior, executa o booking direto SEM passar
      # pelo LLM (evita o bug do LLM perder contexto e re-disparar uma
      # ação antiga). Mesma coisa pra "já feito" — se a ação já rolou,
      # responde determinísticamente em vez de deixar o LLM repetir.
      ctx_state = AiAgent::StateMachine::ConversationContext.new(state)
      if ctx_state.confirmation?(user_message)
        deterministic = handle_deterministic_confirmation(ctx_state, context, started_at, state)
        return deterministic if deterministic
      end

      # Aceite com horário específico ("Podemos as 11h?", "Pode ser 14h",
      # "Quero 9:30") quando há `pending_offer.alternatives` ativa que
      # casa com o horário mencionado. Dispara book/reschedule
      # deterministicamente — evita o LLM alucinar "esse horário acabou
      # de ser preenchido" mesmo com a tool tendo retornado disponível.
      if (matched_offer = ctx_state.offer_match_for(user_message))
        Rails.logger.info("[AiAgent] deterministic accept: paciente mencionou horário no pending_offer.alternatives — bookando #{matched_offer['starts_at']}")
        result = book_from_offer(matched_offer, context)
        return result if result
      end

      # Per-turn context block: datetime, clinic open/closed status, reference
      # dates ("amanhã" → 07/05), patient hints. Reuses `started_at` so the
      # clock is frozen for the whole turn (no drift across helpers).
      # Goes as a PREFIX to the user message — never the system prompt —
      # so the cached system prompt stays cache-hit-friendly.
      context_block = AiAgent::ContextBuilder.new(
        account: @account,
        now: started_at,
        patient_memory: memory,
        contact_id: @contact_id
      ).block

      # Anti-anchor: se há serviço ativo no fluxo atual, marca
      # explicitamente pro LLM ver POR CIMA do histórico. Sem isso,
      # Gemini tende a saltar pra serviço anterior bem-sucedido só
      # porque tá no histórico.
      if (active = ctx_state.active_service)
        context_block += "\n\n[FLUXO ATIVO: você está no agendamento de \"#{active['name']}\" (service_id=#{active['id']}). Continue NESSE serviço. NÃO salte pra outro só porque aparece no histórico — só mude se o paciente PEDIR explicitamente outro serviço pelo nome agora.]"
      end

      # Mesmo padrão pro paciente alvo (família WhatsApp). Quando o
      # paciente do agendamento é um TERCEIRO (pai marcando pra filho),
      # o LLM precisa lembrar de passar `patient_id` no book_appointment.
      # Esse hint sobrevive mesmo se o create_patient_minimal saiu da
      # janela de história (>10 msgs atrás).
      if (active_pat = ctx_state.active_patient) && active_pat['is_third_party']
        minor_note = active_pat['is_minor'] ? ' (MENOR de idade — lembre que precisa vir com responsável e termo)' : ''
        context_block += "\n\n[PACIENTE DO AGENDAMENTO: \"#{active_pat['name']}\" (patient_id=#{active_pat['id']}, terceiro vinculado a este WhatsApp#{minor_note}). SEMPRE passe `patient_id=#{active_pat['id']}` quando chamar book_appointment — sem isso o evento sai pra pessoa errada.]"
      end

      tool_log = []
      response, model_used, used_fallback = with_provider_fallback do |model|
        chat = build_chat(context, tool_log, model: model, user_message: user_message)
        send_with_history(chat, user_message, context_prefix: context_block)
      end
      @last_model_used = model_used
      @last_used_fallback = used_fallback

      validation = AiAgent::Guardrail::Validator.new(response.content.to_s, context: context).call
      final_message = validation.sanitized_message

      unless validation.safe?
        state.escalate!(reason: "guardrail:#{validation.violations.join(',')}")
        Rails.logger.warn("[AiAgent::Guardrail] blocked: #{validation.violations.join(',')}")
      end

      # Resposta evasiva ("vou checar com a equipe", "não tenho essa info").
      # Conta no working_memory; se atingir 3 evasivas em janela de 60min,
      # dispara notificação de lacuna pra equipe revisar a base de conhecimento.
      if AiAgent::Detectors::EvasiveResponse.new(final_message).evasive?
        AiAgent::InternalNotifier::RepeatedFailuresAlert.track(
          state: state,
          last_user_message: user_message,
          conversation: ::Conversation.find_by(id: @conversation_id),
          contact: ::Contact.find_by(id: @contact_id),
          account: @account
        )
      end

      # Sentinel: Reflection 1-step pós-LLM em turnos high-stakes.
      # Apenas registra verdict no Trace (não regenera) — telemetria
      # primeiro pra validar custo×ganho antes de mexer na resposta.
      sentinel_verdict = run_sentinel(user_message, final_message, tool_log)

      state.update!(last_message_at: Time.current)
      record_usage(response)
      trace = persist_trace(
        state: state,
        response: response,
        tool_log: tool_log,
        validation: validation,
        sentinel_verdict: sentinel_verdict,
        started_at: started_at
      )

      Result.new(
        message: final_message,
        tool_executions: tool_log,
        usage: { input_tokens: response.input_tokens, output_tokens: response.output_tokens },
        state: state,
        handoff: state.status == 'escalated',
        trace: trace
      )
    end

    private

    def build_chat(context, tool_log, model: nil, user_message: nil)
      chat = RubyLLM.chat(model: model || model_for_provider)

      builder = AiAgent::PromptBuilder.new(
        account: @account,
        conversation_state: context.conversation_state,
        patient_memory: context.patient_memory,
        contact: context.contact_id ? ::Contact.find_by(id: context.contact_id) : nil
      )
      chat.with_instructions(builder.system_instructions)

      enabled_keys = @resolver.enabled_tools
      tool_classes = AiAgent::ToolRegistry.lookup(enabled_keys)
      ctx_state = AiAgent::StateMachine::ConversationContext.new(context.conversation_state)

      tool_classes.each do |klass|
        instance = klass.new(context)
        wrap_tool_for_state_capture(instance, ctx_state, user_message: user_message)
        chat.with_tool(instance)
      end

      chat.on_tool_call do |tool_call|
        tool_log << { name: tool_call.name, arguments: tool_call.arguments }
      end

      chat
    end

    # Override `execute` na instância da tool pra capturar o resultado
    # e atualizar o state machine — sem precisar editar cada tool. Delega
    # a chamada original e olha o hash retornado pra inferir oferta ou
    # ação concluída. Defensivo: se a tool não retornar formato esperado
    # ou der raise, segue tranquilo.
    def wrap_tool_for_state_capture(tool_instance, ctx_state, user_message: nil)
      original_execute = tool_instance.method(:execute)
      key = tool_instance.name

      account_for_critique = @account
      user_msg_for_anchor = user_message.to_s.downcase
      tool_instance.define_singleton_method(:execute) do |**args|
        # Anti-anchor: se há um serviço ativo no fluxo (paciente pediu
        # "remoção de pontos" turno passado e isso foi capturado), e o
        # LLM tenta chamar search_available_slots com OUTRO service_id
        # sem o paciente ter pedido a mudança, sobrescreve. Defesa
        # contra o bug clássico do LLM voltar pra um serviço anterior
        # de sucesso só porque ele apareceu no histórico.
        #
        # EXCEÇÃO: se o paciente mencionou EXPLICITAMENTE o nome do
        # serviço novo na mensagem atual ("seria avaliação", "quero
        # marcar limpeza"), respeita o LLM e LIMPA o anchor antigo.
        # Caso contrário, mudanças legítimas de assunto ficam presas
        # no serviço da conversa anterior — bug visto em produção
        # quando paciente troca de "remoção de pontos" pra "avaliação".
        if key == 'search_available_slots' && (active = ctx_state.active_service) && args[:service_id].to_i != active['id'].to_i
          requested = ::AgendaService.where(account_id: account_for_critique.id).find_by(id: args[:service_id])
          mentioned_explicit = requested && user_msg_for_anchor.include?(requested.name.to_s.downcase)

          if mentioned_explicit
            Rails.logger.info("[AiAgent] active_service override SKIP: paciente mencionou '#{requested.name}' explicitamente — respeitando LLM e limpando anchor antigo")
            ctx_state.clear_active_service!
          else
            Rails.logger.info("[AiAgent] active_service override: LLM passou service_id=#{args[:service_id]} mas active=#{active['id']} (#{active['name']}) — sobrescrevendo")
            args[:service_id] = active['id']
          end
        end

        # Auto-inject patient_id em book_appointment quando há terceiro
        # ativo no fluxo e o LLM esqueceu de passar. Sem isso, o evento
        # vai pro Patient padrão (quem está conversando) em vez do
        # terceiro (filho/familiar). Bug clássico depois de >10 msgs
        # quando o create_patient_minimal cai fora da janela de history.
        contact_id_for_check = @contact_id
        if key == 'book_appointment' && args[:patient_id].blank?
          if (active_pat = ctx_state.active_patient) && active_pat['is_third_party']
            Rails.logger.info("[AiAgent] auto-injecting patient_id=#{active_pat['id']} (#{active_pat['name']}) em book_appointment — LLM esqueceu de passar")
            args[:patient_id] = active_pat['id']
          elsif defined?(::Patient) && contact_id_for_check.present?
            # Defesa em profundidade: mesmo sem active_patient, se este
            # Contact tem MAIS DE UM Patient ativo (família WhatsApp),
            # NÃO podemos chutar pra qual deles agendar. Recusa com erro
            # claro pra Bea pedir clarificação ao paciente em vez de
            # agendar pro errado silenciosamente.
            family = ::Patient.active.where(account_id: account_for_critique.id, contact_id: contact_id_for_check).limit(2).pluck(:id, :name)
            if family.size > 1
              names = family.map { |_id, name| name }.join(', ')
              Rails.logger.warn("[AiAgent] book_appointment SEM patient_id mas Contact tem #{family.size} Patients (#{names}) — recusando")
              return {
                booked: false,
                error: "Este WhatsApp tem mais de um cadastro (#{names}). Você esqueceu de passar `patient_id`. Pergunte ao paciente PARA QUEM EXATAMENTE é o agendamento e use o patient_id correspondente."
              }
            end
          end
        end

        # Critique 1-step antes de book/reschedule. Se reprovar, devolve
        # erro estruturado pro LLM em vez de executar — deterministic,
        # sem custo de LLM extra. Cobre data passada, fora do horário,
        # profissional que não faz o serviço, duração fora de banda.
        critique_tool = case key
                        when 'book_appointment'        then :book
                        when 'reschedule_appointment'  then :reschedule
                        end
        if critique_tool
          verdict = AiAgent::Humanization::Critique.new(account: account_for_critique, tool: critique_tool, args: args).call
          if verdict.failed?
            Rails.logger.warn("[AiAgent::Critique] reprovou #{key}: #{verdict.reasons.join(' | ')} (args=#{args.slice(:starts_at, :new_starts_at, :user_id, :service_id, :duration_minutes).inspect})")
            err = verdict.error_result_for(critique_tool)
            return err
          end
        end

        result = original_execute.call(**args)
        AiAgent::ChatService.record_state_from_result(ctx_state, key, result) rescue nil
        result
      end
    end

    # Lê o resultado da tool e atualiza pending_offer / last_completed.
    def self.record_state_from_result(ctx_state, key, result)
      return unless result.is_a?(Hash)

      case key
      when 'list_appointments'
        # Se a tool retornou EXATAMENTE 1 agendamento, marca como
        # candidato de remarcação. Se vierem múltiplos, deixa o LLM
        # perguntar qual antes de oferecer slot novo.
        appts = result[:appointments]
        if appts.is_a?(Array) && appts.size == 1
          ctx_state.remember_listed_appointment!(appts.first[:id])
        end
      when 'search_available_slots'
        # Marca active_service mesmo que a busca venha vazia — o
        # paciente está no fluxo desse serviço, e turnos ambíguos
        # subsequentes ("agende pra depois de amanhã") devem continuar
        # nele, não saltar pra outro.
        if result.dig(:service, :id) && result.dig(:service, :name)
          ctx_state.set_active_service!(id: result[:service][:id], name: result[:service][:name])
        end

        return unless result[:available] && result[:slots].is_a?(Array) && result[:slots].any?

        first = result[:slots].first
        first_pro = (first[:available_with] || []).first
        # Captura TODOS os slots oferecidos como `alternatives` pra que
        # o pré-LLM matcher consiga disparar book direto quando o
        # paciente mencionar um horário específico ("Podemos as 11h?").
        # Sem isso, só "Sim" plain dispara — qualquer outra forma de
        # aceite força o LLM a decidir e ele às vezes alucina
        # "esse horário acabou de ser preenchido".
        alternatives = result[:slots].map do |slot|
          pro = (slot[:available_with] || []).first
          {
            'starts_at' => slot[:starts_at],
            'user_id' => pro&.dig(:id),
            'professional_name' => pro&.dig(:name),
            'time' => slot[:time],
            'date' => slot[:date]
          }
        end
        # Se list_appointments rodou no mesmo turno e retornou 1
        # consulta, search_available_slots subsequente é parte de um
        # fluxo de REMARCAÇÃO. Marca o offer com target_appointment_id
        # pra que a confirmação ("Sim") dispare reschedule, não book.
        target_id = ctx_state.recent_listed_appointment_id
        ctx_state.offer_slot!(
          starts_at: first[:starts_at],
          duration_minutes: result.dig(:service, :duration_minutes) || 60,
          service_id: result.dig(:service, :id),
          service_name: result.dig(:service, :name),
          user_id: first_pro&.dig(:id),
          professional_name: first_pro&.dig(:name),
          target_appointment_id: target_id,
          alternatives: alternatives
        )
      when 'create_patient_minimal'
        # Quando uma ficha de TERCEIRO é criada (pai agendando pra filho),
        # rastreia esse paciente como alvo do fluxo. O book_appointment
        # subsequente usa esse estado pra auto-injetar patient_id se o
        # LLM esquecer (bug clássico de perda de contexto após N turnos).
        return unless result[:created] && result.dig(:patient, :id)

        patient_data = result[:patient]
        if patient_data[:is_third_party]
          ctx_state.set_active_patient!(
            id: patient_data[:id],
            name: patient_data[:name],
            is_third_party: true,
            is_minor: patient_data[:is_minor] || false
          )
        end
      when 'book_appointment'
        return unless result[:booked]

        appt = result[:appointment] || {}
        ctx_state.mark_completed!(
          type: 'booked',
          summary: "#{appt[:title]} para #{appt[:starts_at]} com #{appt[:professional_name]}"
        )
        ctx_state.clear_active_service!
        ctx_state.clear_active_patient!
      when 'reschedule_appointment'
        return unless result[:rescheduled]

        appt = result[:appointment] || {}
        ctx_state.mark_completed!(
          type: 'rescheduled',
          summary: "#{appt[:title]} remarcada para #{appt[:new_starts_at]}"
        )
        ctx_state.clear_active_service!
      when 'cancel_appointment'
        return unless result[:cancelled]

        appt = result[:appointment] || {}
        ctx_state.mark_completed!(
          type: 'cancelled',
          summary: "#{appt[:title]} cancelada (era para #{appt[:was_scheduled_for]})"
        )
        ctx_state.clear_active_service!
      end
    end

    # Pré-LLM: paciente respondeu uma confirmação curta. Se temos
    # estado válido, agimos sem o LLM.
    def handle_deterministic_confirmation(ctx_state, context, started_at, state)
      offer = ctx_state.pending_offer
      completed = ctx_state.recent_completed

      if offer && context.contact_id
        result = book_from_offer(offer, context)
        return result if result
      end

      if completed
        msg = build_completed_acknowledgment(completed)
        ctx_state.clear_completed!
        return build_short_circuit_result(msg, state, started_at, deterministic_action: 'ack_completed')
      end

      nil
    end

    def book_from_offer(offer, context)
      ctx_state = AiAgent::StateMachine::ConversationContext.new(context.conversation_state)
      starts = Time.zone.parse(offer['starts_at']) rescue nil
      time_label = starts ? starts.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M') : offer['starts_at']

      # Se a oferta tem target_appointment_id, é remarcação — chama
      # reschedule_appointment, não book. Senão é agendamento novo.
      if offer['target_appointment_id'].present?
        result = AiAgent::Tools::RescheduleAppointmentTool.new(context).execute(
          appointment_id: offer['target_appointment_id'].to_i,
          new_starts_at: offer['starts_at'],
          reason: 'Confirmado pelo paciente'
        )
        return nil unless result.is_a?(Hash) && result[:rescheduled]

        msg = "Pronto! Sua #{offer['service_name']} ficou reservada para #{time_label} com #{offer['professional_name']}. A clínica vai confirmar e te avisar."
        ctx_state.mark_completed!(type: 'rescheduled', summary: msg)
        return build_short_circuit_result(msg, context.conversation_state, Time.current, deterministic_action: 'auto_rescheduled')
      end

      # CRÍTICO: passa patient_id quando há terceiro ativo (família
      # WhatsApp). Sem isso, o auto-book ignora o estado e usa o
      # Patient padrão do Contact, e o evento sai pra pessoa errada
      # (Leandro em vez de Gustavo). Esse caminho determinístico
      # contorna o wrapper do tool, então as defesas em wrap_tool não
      # aplicam — replicamos a lógica aqui.
      patient_id_for_book = nil
      if (active_pat = ctx_state.active_patient) && active_pat['is_third_party']
        patient_id_for_book = active_pat['id']
        Rails.logger.info("[AiAgent] auto_booked com patient_id=#{patient_id_for_book} (#{active_pat['name']}, terceiro)")
      end

      result = AiAgent::Tools::BookAppointmentTool.new(context).execute(
        starts_at: offer['starts_at'],
        duration_minutes: offer['duration_minutes'],
        title: offer['service_name'].to_s.strip[0, 200].presence || 'Consulta',
        user_id: offer['user_id'],
        service_id: offer['service_id'],
        patient_id: patient_id_for_book
      )
      return nil unless result.is_a?(Hash) && result[:booked]

      msg = "Pronto! Sua #{offer['service_name']} ficou reservada para #{time_label} com #{offer['professional_name']}. A clínica vai confirmar e te avisar."
      ctx_state.mark_completed!(type: 'booked', summary: msg)
      ctx_state.clear_active_patient!

      build_short_circuit_result(msg, context.conversation_state, Time.current, deterministic_action: 'auto_booked')
    rescue StandardError => e
      Rails.logger.warn("[AiAgent] auto_book/reschedule falhou: #{e.message}")
      nil
    end

    def build_completed_acknowledgment(completed)
      case completed['type']
      when 'booked'
        'Sim, sua reserva já está feita. A clínica vai confirmar e te avisar. Posso ajudar em mais alguma coisa?'
      when 'rescheduled'
        'Sim, sua reserva já foi movida para o novo horário. A clínica vai confirmar e te avisar. Posso ajudar em algo mais?'
      when 'cancelled'
        'Sim, sua consulta já foi cancelada. Posso ajudar em algo mais?'
      else
        'Beleza, está tudo certo. Posso ajudar em algo mais?'
      end
    end

    def build_short_circuit_result(message, state, started_at, deterministic_action:)
      trace = AiAgent::Trace.create!(
        account_id: @account.id,
        conversation_id: @conversation_id,
        contact_id: @contact_id,
        model: 'deterministic',
        provider: 'state_machine',
        latency_ms: ((Time.current - started_at) * 1000).to_i,
        short_circuited: true,
        tool_calls: [{ name: deterministic_action }],
        created_at: Time.current
      )

      Result.new(
        message: message,
        tool_executions: [{ name: deterministic_action }],
        usage: { input_tokens: 0, output_tokens: 0 },
        state: state,
        handoff: false,
        trace: trace
      )
    end

    # Inlines the conversation history into the current user turn instead of
    # using `chat.add_message(role: :assistant, ...)` for past replies.
    # We hit a reproducible RubyLLM + Gemini bug where the model returns an
    # empty response (output_tokens=0, no tool call, no error) whenever an
    # assistant-role message had been pre-loaded via add_message AND tools
    # were attached. Serializing the history as plain text in the user turn
    # gives Gemini the same context without tripping the bug.
    def send_with_history(chat, user_message, context_prefix: nil)
      prefix = context_prefix.to_s.strip
      prefix = prefix.empty? ? '' : "#{prefix}\n\n"

      return chat.ask("#{prefix}#{user_message}") if @history.empty?

      preamble = @history.map do |msg|
        speaker = msg[:role].to_s == 'user' ? 'Paciente' : 'Você (Bea)'
        "#{speaker}: #{msg[:content]}"
      end.join("\n")
      chat.ask("#{prefix}Histórico recente desta conversa:\n#{preamble}\n\nNova mensagem do paciente: #{user_message}")
    end

    def model_for_provider
      provider = (InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value || 'openai').to_s

      override = @resolver.chat_model
      return override if override.present?

      case provider
      when 'gemini'
        InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_MODEL')&.value.presence || DEFAULT_GEMINI_MODEL
      else
        InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || DEFAULT_OPENAI_MODEL
      end
    end

    def track_message_repetition(state, user_message)
      mem = state.working_memory

      # Idempotent by message id: each Chatwoot Message is one turn,
      # period. Reruns of the same job (manual debug, Sidekiq retry,
      # double dispatch from any source) all see the same id and skip
      # incrementing — preventing false `user_loop` escalations that
      # silenced the patient on otherwise valid follow-ups.
      current_id = @last_message_id_for_repeat_tracking
      last_id = mem['last_message_id']

      return if current_id && last_id == current_id

      same_text = mem['last_user_message'].to_s == user_message.to_s
      mem['repeat_count'] = same_text ? mem['repeat_count'].to_i + 1 : 1
      mem['last_user_message'] = user_message.to_s
      mem['last_message_id'] = current_id if current_id
      state.update!(working_memory: mem)
    end

    # Sentiment analyzer makes an extra LLM call per turn. On Gemini free
    # tier (20 RPM), this can push the conversation over quota. Disabled
    # unless explicitly enabled via env or InstallationConfig.
    def apply_sentiment(state, user_message)
      return unless sentiment_enabled?

      sentiment = AiAgent::Humanization::SentimentAnalyzer.new.call(user_message)
      negative_streak = sentiment.score <= AiAgent::Humanization::EscalationRules::NEGATIVE_THRESHOLD ? state.consecutive_negative_count + 1 : 0

      state.update!(
        last_sentiment_score: sentiment.score,
        last_sentiment_label: sentiment.label,
        consecutive_negative_count: negative_streak
      )
    rescue StandardError => e
      Rails.logger.warn("[AiAgent] sentiment skipped: #{e.message}")
    end

    def sentiment_enabled?
      InstallationConfig.find_by(name: 'CAPTAIN_BEA_SENTIMENT_ENABLED')&.value.to_s == 'true'
    end

    # Curto-circuito de emergência: paciente disparou keyword
    # clínica (SAMU 192) ou ideação suicida (CVV 188). Não passa
    # pelo LLM, não chama tool, escala humano imediatamente, e
    # registra trace separado pra auditoria (escalation_reason
    # começa com `emergency:`, tool_calls inclui keyword detectada).
    def emergency_short_circuit(state, emergency, started_at)
      reason = "emergency:#{emergency.category}"
      state.escalate!(reason: reason)

      message = AiAgent::Emergency::Responder.message_for(emergency.category)

      trace = AiAgent::Trace.create!(
        account_id: @account.id,
        conversation_id: @conversation_id,
        contact_id: @contact_id,
        model: 'deterministic',
        provider: 'emergency_detector',
        latency_ms: ((Time.current - started_at) * 1000).to_i,
        sentiment_label: state.last_sentiment_label,
        sentiment_score: state.last_sentiment_score,
        escalated: true,
        escalation_reason: reason,
        short_circuited: true,
        tool_calls: [{ name: 'emergency_detector',
                       category: emergency.category.to_s,
                       keyword: emergency.keyword.to_s.strip[0, 100] }],
        created_at: Time.current
      )

      Rails.logger.warn("[AiAgent::Emergency] #{reason} disparado conv=#{@conversation_id} contact=#{@contact_id} keyword=#{emergency.keyword.inspect}")

      # Pipeline A — notifica equipe interna no Chat Interno (template editável
      # via /captain/<id>/templates). Dedupe por janela de 5min: se o paciente
      # mandar 3 mensagens em sequência com keywords, equipe recebe 1 alerta.
      AiAgent::InternalNotifier::EmergencyAlert.call(
        account: @account,
        conversation: ::Conversation.find_by(id: @conversation_id),
        contact: ::Contact.find_by(id: @contact_id),
        category: emergency.category,
        trigger_terms: emergency.keyword
      )

      Result.new(
        message: message,
        tool_executions: [{ name: 'emergency_detector', category: emergency.category.to_s }],
        usage: { input_tokens: 0, output_tokens: 0 },
        state: state,
        handoff: true,
        trace: trace
      )
    end

    # Casa só após `.downcase` — Ruby /i não faz fold consistente em
    # Ã/À/Á maiúsculos, mas downcase converte tudo limpo.
    OPT_OUT_REGEX = /\A\s*(não|nao|pare|stop|chega|não\s+quero|não\s+receber|sair|cancela\s+(?:os?\s+)?lembretes?)[\s.!?]*\z/

    def recall_opt_out_response?(user_message, memory)
      return false unless OPT_OUT_REGEX.match?(user_message.to_s.strip.downcase)

      prefs = memory.preferences.is_a?(Hash) ? memory.preferences : {}
      last_recall = prefs['last_recall_at'].to_s
      return false if last_recall.blank?

      recall_at = Time.zone.parse(last_recall) rescue nil
      return false if recall_at.nil?

      recall_at > 7.days.ago
    end

    def recall_opt_out_short_circuit(state, memory, started_at)
      prefs = memory.preferences.is_a?(Hash) ? memory.preferences.dup : {}
      prefs['recall_opt_out'] = true
      prefs['recall_opt_out_at'] = Time.current.iso8601
      memory.update!(preferences: prefs)
      memory.append_history(
        event_type: 'recall_opt_out',
        summary: 'Paciente optou por não receber lembretes proativos',
        metadata: { triggered_by: 'message_response' }
      )

      msg = 'Tudo bem, não te chamo mais com lembretes proativos. Se um dia quiser remarcar, é só falar comigo. 🙏'

      trace = AiAgent::Trace.create!(
        account_id: @account.id,
        conversation_id: @conversation_id,
        contact_id: @contact_id,
        model: 'deterministic',
        provider: 'recall_opt_out',
        latency_ms: ((Time.current - started_at) * 1000).to_i,
        short_circuited: true,
        tool_calls: [{ name: 'recall_opt_out_acknowledged' }],
        created_at: Time.current
      )

      Result.new(
        message: msg,
        tool_executions: [{ name: 'recall_opt_out_acknowledged' }],
        usage: { input_tokens: 0, output_tokens: 0 },
        state: state,
        handoff: false,
        trace: trace
      )
    end

    def early_handoff(state, escalation, started_at)
      state.escalate!(reason: escalation.reason)

      trace = AiAgent::Trace.create!(
        account_id: @account.id,
        conversation_id: @conversation_id,
        contact_id: @contact_id,
        model: model_for_provider,
        provider: provider_name,
        latency_ms: ((Time.current - started_at) * 1000).to_i,
        sentiment_label: state.last_sentiment_label,
        sentiment_score: state.last_sentiment_score,
        escalated: true,
        escalation_reason: escalation.reason,
        short_circuited: true,
        created_at: Time.current
      )

      Result.new(
        message: 'Vou te passar para um atendente da nossa equipe agora. Só um instante.',
        tool_executions: [],
        usage: { input_tokens: 0, output_tokens: 0 },
        state: state,
        handoff: true,
        trace: trace
      )
    end

    # Sentinel: pós-LLM critique em high-stakes. Roda só quando o
    # InstallationConfig CAPTAIN_BEA_SENTINEL_ENABLED=true E o
    # HighStakesDetector classifica o turno como high-stakes — evita
    # custo de 2× LLM em turnos triviais (saudação, hora). Verdict vai
    # pro Trace.guardrail_violations pra dashboards.
    def run_sentinel(user_message, response_text, tool_log)
      return nil unless AiAgent::Humanization::Sentinel.enabled?
      return nil if response_text.to_s.strip.empty?

      detector = AiAgent::Humanization::HighStakesDetector.new(
        response_text: response_text, tool_log: tool_log
      ).call
      return nil unless detector.high_stakes?

      AiAgent::Humanization::Sentinel.new(
        user_message: user_message,
        response_text: response_text,
        tool_log: tool_log,
        categories: detector.categories
      ).call
    rescue StandardError => e
      Rails.logger.warn("[AiAgent::Humanization::Sentinel] wrap falhou: #{e.class}: #{e.message[0, 200]}")
      nil
    end

    def persist_trace(state:, response:, tool_log:, validation:, sentinel_verdict: nil, started_at:)
      input  = response.input_tokens.to_i
      output = response.output_tokens.to_i
      model  = @last_model_used || model_for_provider

      AiAgent::Trace.create!(
        account_id: @account.id,
        conversation_id: @conversation_id,
        contact_id: @contact_id,
        message_id: @last_message_id_for_repeat_tracking,
        model: model,
        provider: actual_provider_used,
        latency_ms: ((Time.current - started_at) * 1000).to_i,
        input_tokens: input,
        output_tokens: output,
        cost_cents: AiAgent::Pricing.cost_cents(model: model, input_tokens: input, output_tokens: output),
        tool_calls: tool_log,
        sentiment_label: state.last_sentiment_label,
        sentiment_score: state.last_sentiment_score,
        escalated: state.status == 'escalated',
        escalation_reason: validation.safe? ? nil : "guardrail:#{validation.violations.join(',')}",
        guardrail_violations: combine_violations(validation.violations, sentinel_verdict),
        short_circuited: false,
        created_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      # Outro job rodou em paralelo e criou Trace pra mesma message_id —
      # tudo bem, é exatamente isso que o índice único parcial bloqueia.
      # Aborta o turno sem error pra Sidekiq não retentar.
      Rails.logger.warn("[AiAgent::ChatService] persist_trace race: msg=#{@last_message_id_for_repeat_tracking} já tem Trace bem-sucedido — abortando duplicado")
      raise AiAgent::DuplicateTurnError, 'Trace já existe pra esta mensagem'
    end

    # Empilha verdict do Sentinel em guardrail_violations (jsonb array)
    # pra dashboards filtrarem `sentinel:reproved` sem precisar de
    # coluna nova. Quando sentinel passa OU está desligado, mantém só
    # as violations do Validator.
    def combine_violations(validator_violations, sentinel_verdict)
      base = Array(validator_violations)
      return base if sentinel_verdict.nil?

      tag = if sentinel_verdict.passed?
              'sentinel:ok'
            elsif sentinel_verdict.failed?
              reason = sentinel_verdict.reason.to_s.tr(',|', ' ').strip[0, 120]
              reason.empty? ? 'sentinel:reproved' : "sentinel:reproved:#{reason}"
            else
              'sentinel:unknown'
            end

      base + [tag]
    end

    def provider_name
      InstallationConfig.find_by(name: 'CAPTAIN_LLM_PROVIDER')&.value.presence || 'openai'
    end

    # Provider que efetivamente respondeu o turno corrente. Se `with_provider_fallback`
    # caiu pro OpenAI por outage do Gemini, retorna 'openai' (não o configurado).
    # Usado no Trace pra dashboards de saúde detectarem fallback real.
    def actual_provider_used
      return 'openai' if @last_used_fallback

      provider_name
    end

    # Tries the configured model first; on transient provider failures
    # (rate limit, 5xx, forbidden access) retries once with the OpenAI
    # fallback model. The Trace records which one actually answered so we
    # can spot Gemini outages in the dashboard later.
    FALLBACK_ERRORS = [
      defined?(RubyLLM::RateLimitError)         ? RubyLLM::RateLimitError         : nil,
      defined?(RubyLLM::ServerError)            ? RubyLLM::ServerError            : nil,
      defined?(RubyLLM::ForbiddenError)         ? RubyLLM::ForbiddenError         : nil,
      defined?(RubyLLM::ServiceUnavailableError) ? RubyLLM::ServiceUnavailableError : nil
    ].compact.freeze

    # If primary fails AND there is no OpenAI fallback configured (or both
    # exhaust), retry once on the same model after a short backoff. Gemini's
    # "high demand" 503 is intermittent — a single retry usually clears it
    # and beats erroring out the whole turn.
    INLINE_RETRY_DELAY = 2.0

    def with_provider_fallback
      primary = model_for_provider
      response = yield(primary)
      [response, primary, false]
    rescue *FALLBACK_ERRORS => e
      fallback = openai_fallback_model
      has_openai_fallback = fallback.present? &&
                            primary != fallback &&
                            RubyLLM.config.openai_api_key.present?

      if has_openai_fallback
        Rails.logger.warn("[AiAgent] primary #{primary} failed (#{e.class}); falling back to #{fallback}")
        response = yield(fallback)
        return [response, fallback, true]
      end

      # No fallback available → retry the same model once after a short pause.
      # Gemini's "high demand" 503s clear within a couple of seconds.
      Rails.logger.warn("[AiAgent] primary #{primary} failed (#{e.class}); retrying once after #{INLINE_RETRY_DELAY}s")
      sleep INLINE_RETRY_DELAY
      response = yield(primary)
      [response, primary, false]
    end

    def openai_fallback_model
      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || DEFAULT_OPENAI_MODEL
    end

    def record_usage(response)
      input  = response.input_tokens.to_i
      output = response.output_tokens.to_i
      # Usa o modelo REAL que respondeu (pode ser fallback), não o configurado.
      # Sem isso, contas com Gemini primário subnotificam custo do fallback
      # OpenAI (que pode custar 3-5x mais por token).
      model  = @last_model_used || model_for_provider

      AiAgent::UsageCounter.bump!(
        account_id: @account.id,
        input_tokens: input,
        output_tokens: output,
        cost_cents: AiAgent::Pricing.cost_cents(model: model, input_tokens: input, output_tokens: output),
        conversations: 0
      )

      # Bea shares the same per-account quota as the legacy Captain so that
      # super admins can cap "AI replies" with one number (`limits.captain_responses`).
      # Each Bea answer counts as one response, matching audio transcription
      # and copilot which already increment this counter.
      @account.increment_response_usage if @account.respond_to?(:increment_response_usage)
    end

    # True when the account has consumed its monthly captain_responses quota.
    # Returns false (= unlimited) for self-hosted setups where the quota helper
    # isn't loaded.
    def captain_quota_exhausted?
      return false unless @account.respond_to?(:usage_limits)

      captain = @account.usage_limits[:captain]
      return false if captain.blank?

      available = captain.dig(:responses, :current_available)
      available.present? && available.to_i <= 0
    end

    def captain_quota_handoff(state, started_at)
      state.escalate!(reason: 'captain_quota_exhausted')

      trace = AiAgent::Trace.create!(
        account_id: @account.id,
        conversation_id: @conversation_id,
        contact_id: @contact_id,
        model: model_for_provider,
        provider: provider_name,
        latency_ms: ((Time.current - started_at) * 1000).to_i,
        sentiment_label: state.last_sentiment_label,
        sentiment_score: state.last_sentiment_score,
        escalated: true,
        escalation_reason: 'captain_quota_exhausted',
        short_circuited: true,
        created_at: Time.current
      )

      Result.new(
        message: 'O atendimento automático bateu o limite do plano deste mês. Já avisei a equipe — em instantes alguém continua o atendimento por aqui. 🙏',
        tool_executions: [],
        usage: { input_tokens: 0, output_tokens: 0 },
        state: state,
        handoff: true,
        trace: trace
      )
    end

    class BeaDisabledError < StandardError; end
    class BudgetExceededError < StandardError; end
    # Raised quando dois ChatResponseJob rodam pra mesma message_id e o
    # 2º tenta gravar Trace mas o índice único bloqueia. O caller (job)
    # deve tratar como "nada a fazer" e NÃO retentar.
    class DuplicateTurnError < StandardError; end
  end
end
