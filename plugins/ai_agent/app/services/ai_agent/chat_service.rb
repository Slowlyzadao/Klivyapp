# Single-agent orchestrator. Given an account, a conversation_id, a contact
# and the latest user message, runs one full LLM turn (with tool calling)
# and returns the agent's reply plus telemetry.
#
# This is the entry point used by the webhook dispatcher (Phase 4) and by
# any internal caller (smoke tests, CLI, future API endpoint).
class AiAgent::ChatService
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
    wire_gemini_credentials!

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
    return recall_opt_out_short_circuit(state, memory, started_at) if memory && recall_opt_out_response?(user_message, memory)

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
    # Auto-book determinístico SÓ pra paciente já cadastrado (ou terceiro já
    # criado no fluxo): aí não falta ficha e o evento já sai com o nome certo.
    # Paciente NOVO (sem Patient) segue o fluxo do MD — pick → cadastra (nome)
    # → CPF → book — evitando evento sem nome e o double-book (auto-book + o
    # LLM re-agendando depois ao coletar o CPF).
    if (matched_offer = ctx_state.offer_match_for(user_message)) && autobook_allowed?(ctx_state)
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
      per = active['period'].to_s
      period_hint = per.present? && per != 'qualquer' ? " Período preferido do paciente: #{per}." : ''
      context_block += "\n\n[ESTADO DO ATENDIMENTO (vale MESMO que tenha saído da janela de histórico) — motivo/serviço: \"#{active['name']}\" (service_id=#{active['id']}).#{period_hint} Continue NESSE serviço/motivo; NÃO salte pra outro só porque aparece no histórico — só mude se o paciente PEDIR explicitamente outro serviço agora.]"
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

    # Guard anti-duplicação: se uma ação (book/reschedule/cancel) JÁ foi
    # concluída neste atendimento, avisa o LLM pra NÃO refazer. Sem isso,
    # após um agendamento a Bia às vezes seguia coletando dados e RE-AGENDAVA
    # num horário diferente → 2 eventos pro mesmo paciente.
    if (done = ctx_state.recent_completed)
      done_label = case done['type']
                   when 'booked'      then 'JÁ EXISTE um agendamento criado e CONFIRMADO'
                   when 'rescheduled' then 'a remarcação JÁ foi feita e CONFIRMADA'
                   when 'cancelled'   then 'o cancelamento JÁ foi feito'
                   else 'a ação JÁ foi concluída'
                   end
      context_block += "\n\n[#{done_label} neste atendimento: \"#{done['summary']}\". " \
                       'NÃO chame book_appointment/reschedule_appointment/search_available_slots de novo, e NÃO ofereça nem cite outros horários. ' \
                       'Se o paciente está só mandando dados que faltavam (CPF, nome), registre com update_patient_record/create_patient_minimal e apenas CONFIRME que está tudo certo. ' \
                       'Só inicie um novo agendamento se o paciente PEDIR explicitamente outra consulta/horário diferente agora.]'
    end

    # Consulta(s) futura(s) INJETADAS no contexto (determinístico): o LLM às
    # vezes não chama find_patient (confia no nome do contato) e abre genérico,
    # SEM citar a consulta marcada. Aqui garantimos que ele SEMPRE veja a(s)
    # consulta(s) e seja mandado mencionar — independe de chamar tool.
    upcoming = AiAgent::AppointmentsLookup.upcoming(@account, @contact_id, limit: 5)
    if upcoming.any?
      zone = AiAgent::ContextBuilder::CLINIC_TIMEZONE
      list = upcoming.map do |e|
        quem = e.user&.name
        pac = (e.custom_attributes || {})['patient_name']
        quando = e.starts_at.in_time_zone(zone).strftime('%d/%m às %H:%M')
        label = quem ? "#{quando} com #{quem}" : quando
        pac.present? ? "#{label} (paciente: #{pac})" : label
      end.join('; ')
      n = upcoming.size
      qtd = n == 1 ? '1 consulta marcada' : "#{n} consultas marcadas"
      cite = n == 1 ? 'essa consulta' : "as #{n} consultas"
      alvo = n == 1 ? 'ela' : 'alguma delas'
      multi = n > 1 ? ' Se ele pedir pra CANCELAR ou REMARCAR, pergunte QUAL (pelo paciente + dia + hora) e aja SÓ na escolhida — NUNCA mexa em todas de uma vez.' : ''
      ids_map = upcoming.map { |e| "#{e.starts_at.in_time_zone(zone).strftime('%d/%m %H:%M')} = ##{e.id}" }.join('; ')
      context_block += "\n\n[CONSULTA(S) FUTURA(S) deste paciente: #{qtd} — #{list}. " \
                       'Se for a ABERTURA da conversa, reconheça o paciente pelo nome e ' \
                       "MENCIONE #{cite} (dia, horário, profissional), perguntando se o contato " \
                       "é sobre #{alvo}.#{multi} Use o número EXATO; não invente. " \
                       'Pra CANCELAR ou REMARCAR use estes IDs internos como appointment_id ' \
                       "(NUNCA invente um id, NUNCA mostre o # ao paciente): #{ids_map}.]"
    end

    tool_log = []
    response, model_used, used_fallback = with_provider_fallback do |model|
      chat = build_chat(context, tool_log, model: model, user_message: user_message)
      send_with_history(chat, user_message, context_prefix: context_block)
    end
    @last_model_used = model_used
    @last_used_fallback = used_fallback

    # Anti-vazamento de raciocínio: Gemini às vezes escreve o chain-of-thought
    # COMO resposta ("retornou found: false, preciso solicitar o CPF dele...").
    # thinkingBudget=0 não cobre isso (é texto normal, não thinking token).
    # Detecta determinísticamente e REESCREVE só a fala ao paciente — sem tools
    # (sem risco de re-agendar). Rede de segurança: se a reescrita falhar ou
    # ainda vazar, remove as frases vazadas.
    raw_content = response.content.to_s
    if AiAgent::Guardrail::ReasoningLeak.leaked?(raw_content)
      Rails.logger.warn('[AiAgent] reasoning leak detectado — reescrevendo a resposta')
      rewritten = rewrite_clean(raw_content, model_used)
      raw_content = if rewritten.present? && !AiAgent::Guardrail::ReasoningLeak.leaked?(rewritten)
                      rewritten
                    else
                      AiAgent::Guardrail::ReasoningLeak.strip(raw_content).presence ||
                        'Me dá só um instante que já te respondo certinho.'
                    end
    end

    validation = AiAgent::Guardrail::Validator.new(raw_content, context: context, first_turn: first_turn?).call
    final_message = validation.sanitized_message

    # Anti-invenção de condições de pagamento: ao quebrar objeção de dinheiro
    # (regra 11 do prompt), o Gemini às vezes carimba um termo específico que
    # NÃO está no material ("8x sem juros no cartão"). Generaliza o que não vier
    # da RAG — regra de prompt não segura 100%. Detalhe no PaymentSpecifics.
    final_message = sanitize_payment_terms(final_message)

    # Cadência de emoji (projeto tom de voz, opção "Equilibrado"): o prompt não
    # segura a frequência de emoji no Gemini (carimba em ~toda msg, repete o
    # mesmo). Normaliza DETERMINÍSTICAMENTE — máx 1/msg, sem repetir o mesmo
    # seguido, ~2 a cada 3. Mexe SÓ no emoji, nunca nas palavras. Estado por
    # conversa no working_memory; persistido junto no state.update! abaixo.
    final_message = apply_emoji_cadence(final_message, state)

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

    persist_turn_state!(state)
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

  # Aplica a cadência de emoji na fala final (só quando a conta tem tom de voz
  # ATIVO — sem tom, a persona já usa "emoji raro" e não há spam). Lê o estado
  # da conversa (último emoji + streak) do working_memory e guarda o novo em
  # @pending_emoji_state pra ser persistido no state.update! do respond. Em
  # qualquer erro, devolve a mensagem original (nunca quebra o atendimento).
  def apply_emoji_cadence(message, state)
    return message unless style_profile_active?

    mem = state.working_memory.is_a?(Hash) ? state.working_memory : {}
    result = AiAgent::StyleProfile::EmojiNormalizer.call(text: message, state: mem['emoji_cadence'])
    @pending_emoji_state = result.state
    result.text
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] apply_emoji_cadence falhou: #{e.message}")
    message
  end

  # Generaliza condições de pagamento específicas que a Bea inventou (não vieram
  # da RAG). Em qualquer erro, devolve a mensagem original (nunca quebra o turno).
  def sanitize_payment_terms(message)
    AiAgent::Guardrail::PaymentSpecifics.sanitize(text: message, account: @account)
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] sanitize_payment_terms falhou: #{e.message}")
    message
  end

  def style_profile_active?
    return @style_profile_active if defined?(@style_profile_active)

    setting = AiAgent::AccountSetting.find_by(account_id: @account.id)
    @style_profile_active = setting&.style_profile.is_a?(Hash) && setting.style_profile['enabled'] == true
  end

  # Persiste o estado do turno: timestamp + (quando há) a cadência de emoji da
  # conversa no working_memory. Merge defensivo pra não pisar em outras chaves.
  def persist_turn_state!(state)
    attrs = { last_message_at: Time.current }
    if @pending_emoji_state
      mem = state.working_memory.is_a?(Hash) ? state.working_memory.dup : {}
      mem['emoji_cadence'] = @pending_emoji_state
      attrs[:working_memory] = mem
    end
    state.update!(attrs)
  end

  def build_chat(context, tool_log, model: nil, user_message: nil)
    resolved_model = (model || model_for_provider).to_s
    provider = provider_for_model(resolved_model)
    chat = RubyLLM.chat(
      model: resolved_model,
      provider: provider,
      assume_model_exists: true
    )
    apply_provider_tuning(chat, provider)

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
          Rails.logger.warn("[AiAgent::Critique] reprovou #{key}: #{verdict.reasons.join(' | ')} (args=#{args.slice(:starts_at, :new_starts_at,
                                                                                                                    :user_id, :service_id, :duration_minutes).inspect})")
          err = verdict.error_result_for(critique_tool)
          return err
        end
      end

      result = original_execute.call(**args)
      begin
        AiAgent::ChatService.record_state_from_result(ctx_state, key, result)
      rescue StandardError
        nil
      end
      result
    end
  end

  # Backwards-compat alias: lê o resultado da tool e atualiza
  # pending_offer / last_completed. Lógica vive em
  # `AiAgent::ChatService::StateMachineUpdater.record` (Fase 4 / BE-1
  # — refactor LITE pra reduzir LOC do orquestrador). Mantemos esta
  # API class-method porque o wrapper de tools chamava
  # `AiAgent::ChatService.record_state_from_result` — qualquer caller
  # externo (futuro spec, debug REPL) continua funcionando.
  def self.record_state_from_result(ctx_state, key, result)
    AiAgent::ChatService::StateMachineUpdater.record(ctx_state, key, result)
  end

  # 1º turno = a Bea ainda não falou nada nesta conversa (nenhuma entrada
  # 'assistant' no histórico). Só aí a saudação de abertura é permitida —
  # fora disso o Validator CORTA recumprimento determinísticamente.
  def first_turn?
    Array(@history).none? { |h| (h[:role] || h['role']).to_s == 'assistant' }
  end

  # Auto-book determinístico só vale quando já há ficha (Patient) deste
  # contato OU um terceiro ativo no fluxo — senão o evento sairia sem nome
  # e ainda colidiria com o cadastro que vem logo depois. Paciente novo faz
  # o caminho completo (cadastro → book) pelo LLM.
  def autobook_allowed?(ctx_state)
    return true if ctx_state.active_patient
    return false unless defined?(::Patient) && @contact_id.present?

    ::Patient.active.exists?(account_id: @account.id, contact_id: @contact_id)
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
    # Listagem recente mostrou 2+ consultas: o "Sim" curto NÃO diz QUAL delas
    # o paciente quer mexer — auto-agir aqui criou um 3º agendamento em vez de
    # remarcar (caso real 2026-06-11). Deixa o LLM decidir com o contexto.
    return nil if offer['ambiguous_reschedule']

    # Remarcação NUNCA é automática: o MOTIVO é obrigatório (vai pras
    # Observações da consulta) e só o LLM o coleta na conversa. O tool
    # reschedule_appointment recusa reason vazio — o fluxo cai no LLM,
    # que pergunta o motivo e remarca com o id certo.
    return nil if offer['target_appointment_id'].present?

    ctx_state = AiAgent::StateMachine::ConversationContext.new(context.conversation_state)
    starts = begin
      Time.zone.parse(offer['starts_at'])
    rescue StandardError
      nil
    end
    time_label = starts ? starts.in_time_zone('America/Sao_Paulo').strftime('%d/%m às %H:%M') : offer['starts_at']

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

    msg = "Pronto! Agendamento confirmado: #{offer['service_name']} em #{time_label} com #{offer['professional_name']}. ✅#{clinic_address_suffix}"
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
      'Sim, seu agendamento já está confirmado. Posso ajudar em mais alguma coisa?'
    when 'rescheduled'
      'Sim, sua remarcação já está confirmada. Posso ajudar em algo mais?'
    when 'cancelled'
      'Sim, sua consulta já foi cancelada. Posso ajudar em algo mais?'
    else
      'Beleza, está tudo certo. Posso ajudar em algo mais?'
    end
  end

  # Sufixo de endereço + Google Maps pro fechamento DETERMINÍSTICO (que não
  # passa pelo LLM, então não chama clinic_info). Mesma fonte do
  # clinic_info_tool: account.custom_attributes. Vazio se o endereço não foi
  # configurado. O "\n\n" vira bolha separada no MessageChunker.
  def clinic_address_suffix
    ca = @account.custom_attributes || {}
    street = ca['address_street'].to_s.strip
    city = ca['address_city'].to_s.strip
    return '' if street.blank? && city.blank?

    number = ca['address_number'].to_s.strip
    line = [street, number].reject(&:blank?).join(', ')
    city_uf = [city.presence, ca['address_state'].presence].compact.join('/')
    text = [line.presence, ca['address_neighborhood'].presence, city_uf.presence].compact.join(' - ')
    query = [ca['fantasy_name'], street, number, ca['address_neighborhood'], city, ca['address_state'],
             ca['address_zip']].reject { |x| x.to_s.strip.empty? }.join(', ')
    "\n\n📍 #{text}\n🗺️ https://www.google.com/maps/search/?api=1&query=#{CGI.escape(query)}"
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

  # Delega ao `HistoryFormatter` (Fase 4 / BE-1). Logic detail + workaround
  # Gemini documentados no módulo extraído. Usa `.call` (não `.send`) —
  # `Object#send` built-in atropelaria o dispatch.
  def send_with_history(chat, user_message, context_prefix: nil)
    AiAgent::ChatService::HistoryFormatter.call(
      chat, user_message, history: @history, context_prefix: context_prefix
    )
  end

  # Core's `Llm::Config.initialize!` só injeta a credencial da OpenAI no
  # RubyLLM. O Gemini é provider específico da Bea, então o plugin é dono
  # da própria injeção. Sem isto, trocar CAPTAIN_LLM_PROVIDER para 'gemini'
  # estoura `RubyLLM::ConfigurationError: Missing configuration for Gemini:
  # gemini_api_key` antes mesmo de chamar o modelo. Idempotente e barato.
  # Resolve o provider pelo nome do modelo. Combinado com `assume_model_exists`
  # no build_chat, manda a chamada DIRETO pra API real em vez de validar
  # contra o registro estático do ruby_llm — que fica desatualizado e não
  # conhece modelos novos (ex.: `gemini-3.5-flash`, lançado depois do release
  # do gem), levantando ModelNotFoundError. Gemini → :gemini; resto (fallback
  # gpt-*) → :openai.
  def provider_for_model(model)
    model.to_s.include?('gemini') ? :gemini : :openai
  end

  # Gemini 3.x Flash é um modelo "thinking": por padrão gasta 1000+ tokens
  # de raciocínio antes de responder, levando o turno a 40-80s — inviável no
  # WhatsApp (e estoura o read-timeout). `thinkingBudget: 0` desliga o
  # thinking → resposta direta, cortando a latência pela metade ou mais. O
  # prompt da Bea é explícito o bastante pra não depender de chain-of-thought,
  # e as decisões críticas já são determinísticas (critique/state-machine).
  # OBS: valores > 0 disparam um bug de parse de thought-signature no
  # ruby_llm 1.9.2 ("undefined method 'call' for nil"); 0 é o caminho estável.
  def apply_provider_tuning(chat, provider)
    return unless provider == :gemini

    chat.with_params(generationConfig: { thinkingConfig: { thinkingBudget: 0 } })
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] apply_provider_tuning skipped: #{e.message}")
  end

  # Reescreve um rascunho que vazou raciocínio como APENAS a fala ao paciente.
  # Chat SEM tools de propósito (não re-executa book/cancel/search — zero risco
  # de duplicar ação). Chamado só quando ReasoningLeak detecta vazamento (raro).
  REWRITE_INSTRUCTION = <<~PT.strip
    Você é a Bia, recepcionista de uma clínica no WhatsApp. Vou te dar um RASCUNHO
    que pode conter raciocínio interno, plano, citação de regras, nomes de tools
    ou referências técnicas (ex.: "found: false", "regra VOCÊ", "limite de 3 frases",
    "vou primeiro confirmar"). Reescreva APENAS a mensagem final que o paciente deve
    ler: PT-BR, calorosa e natural, curta (no máximo 3 frases), uma pergunta por vez,
    sem NENHUM meta-comentário, sem citar regras/variáveis/tools e sem narrar seu
    plano nem falar do paciente em 3ª pessoa. Se o rascunho indica que você precisa
    pedir dados (nome completo, CPF) ou confirmar se o agendamento é para a própria
    pessoa, faça essa pergunta DIRETAMENTE ao paciente.
  PT

  def rewrite_clean(draft, model)
    resolved = (model || model_for_provider).to_s
    provider = provider_for_model(resolved)
    chat = RubyLLM.chat(model: resolved, provider: provider, assume_model_exists: true)
    apply_provider_tuning(chat, provider)
    chat.with_instructions(REWRITE_INSTRUCTION)
    chat.ask("RASCUNHO (não mostre isto; reescreva como a fala final ao paciente):\n\n#{draft}").content.to_s.strip
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] rewrite_clean falhou: #{e.message}")
    nil
  end

  def wire_gemini_credentials!
    key = InstallationConfig.find_by(name: 'CAPTAIN_GEMINI_API_KEY')&.value
    return if key.blank?

    RubyLLM.config.gemini_api_key = key
  rescue StandardError => e
    Rails.logger.warn("[AiAgent] wire_gemini_credentials! skipped: #{e.message}")
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

    recall_at = begin
      Time.zone.parse(last_recall)
    rescue StandardError
      nil
    end
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

    # BE-26: passa @account pro Sentinel checar cost cap. Sentinel é uma
    # chamada LLM EXTRA (depois da resposta principal) — o gate em
    # ChatService#respond no início do turn não cobre porque acontece
    # antes do custo dos turnos serem somados ao UsageCounter.
    AiAgent::Humanization::Sentinel.new(
      user_message: user_message,
      response_text: response_text,
      tool_log: tool_log,
      categories: detector.categories,
      account: @account
    ).call
  rescue StandardError => e
    # BE-22 (auditoria 2026-05-18): inclui backtrace.first(3) — sem isso,
    # log warn não dava traço suficiente pra debugar Sentinel flakiness.
    # `message[0, 200]` mantido pra evitar log gigante de prompt no rescue.
    Rails.logger.warn(
      "[AiAgent::Humanization::Sentinel] wrap falhou: #{e.class}: #{e.message[0, 200]} | " \
      "trace=#{Array(e.backtrace).first(3).join(' | ')}"
    )
    nil
  end

  def persist_trace(state:, response:, tool_log:, validation:, started_at:, sentinel_verdict: nil)
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
  #
  # BE-27 (auditoria 2026-05-18): jitter no delay evita thundering herd
  # quando Gemini cai pra todos os tenants simultaneamente. Sem jitter,
  # todos os workers acordam exatamente após 2s e ressincronizam a queda.
  # Range: 1.5–3.5s (média 2.5s).
  INLINE_RETRY_BASE_DELAY = 2.0
  INLINE_RETRY_JITTER = 1.5

  # BE-24 (auditoria 2026-05-18): circuit breaker no provider primário.
  # Quando ele falha N vezes em janela curta, abre o circuit — pula
  # direto pro fallback (OpenAI) sem mais tentativas no primary. Evita
  # cada turn pagar latência de 2s+ esperando primary que está
  # comprovadamente fora. Após COOLDOWN sem tentativa, o circuit fecha
  # naturalmente (TTL no Redis) e re-tenta primary.
  CIRCUIT_BREAKER_THRESHOLD = 5
  CIRCUIT_BREAKER_WINDOW = 60.seconds
  CIRCUIT_BREAKER_COOLDOWN = 5.minutes

  def with_provider_fallback
    primary = model_for_provider
    fallback = openai_fallback_model
    has_openai_fallback = fallback.present? &&
                          primary != fallback &&
                          RubyLLM.config.openai_api_key.present?

    # BE-24: se circuit aberto pro primário E há fallback configurado,
    # vai direto pra fallback. Não conta como `used_fallback: false`
    # (preserva métricas no Trace).
    if has_openai_fallback && circuit_open?(primary)
      Rails.logger.info("[AiAgent] circuit open for #{primary} — using fallback #{fallback} directly")
      response = yield(fallback)
      return [response, fallback, true]
    end

    response = yield(primary)
    [response, primary, false]
  rescue *FALLBACK_ERRORS => e
    record_provider_failure(primary)

    if has_openai_fallback
      Rails.logger.warn("[AiAgent] primary #{primary} failed (#{e.class}); falling back to #{fallback}")
      response = yield(fallback)
      return [response, fallback, true]
    end

    # No fallback available → retry the same model once after backoff
    # com jitter. Gemini's "high demand" 503s clear within a couple of
    # seconds.
    delay = INLINE_RETRY_BASE_DELAY + rand * INLINE_RETRY_JITTER
    Rails.logger.warn("[AiAgent] primary #{primary} failed (#{e.class}); retrying once after #{delay.round(2)}s")
    sleep delay
    response = yield(primary)
    [response, primary, false]
  end

  # BE-24: delegate to `AiAgent::ChatService::CircuitBreaker` (Fase 4 / BE-1).
  # Constantes CIRCUIT_BREAKER_* permanecem em ChatService (API pública);
  # o módulo lê via namespace pai. Fail-open em Redis down preservado.
  def circuit_open?(model)
    AiAgent::ChatService::CircuitBreaker.open?(model)
  end

  def record_provider_failure(model)
    AiAgent::ChatService::CircuitBreaker.record_failure(model)
  end

  def circuit_key(model)
    AiAgent::ChatService::CircuitBreaker.key_for(model)
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
