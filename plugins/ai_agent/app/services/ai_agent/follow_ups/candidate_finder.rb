# Stateless: dado uma `FollowUpRule`, retorna a lista de candidatos
# elegíveis NESSE momento. O dispatcher chama em loop pra cada rule
# enabled e enfileira `SendFollowUpJob` pra cada candidato.
#
# Cada candidato é um Hash com:
#   { contact_id:, conversation_id:, agenda_event_id:, step_id:,
#     anchor_at:, target_at: }
#
# `anchor_at` é o instante-âncora do episódio (starts_at do evento,
# último incoming do paciente, vencimento do recall) — o StopConditions
# usa pra escopar `stop_on_reply` ao episódio certo, em vez de uma
# resposta antiga barrar follow-ups de alvos futuros.
#
# Janela de elegibilidade: o cron roda a cada 1min e a janela é ±1min em
# torno do `target_at`; a idempotência via UNIQUE no banco impede
# duplicação quando o jitter empurra dois ticks pro mesmo registro.
#
# Filtros transversais (todos os triggers):
#   - Bea habilitada na conta (resolver.enabled?)
#   - Contato sem `recall_opt_out` em PatientMemory.preferences
#   - Cap de execuções por alvo (rule.max_per_target)
#   - Não recriar uma execution pendente já existente (idempotência
#     no nível do app — backstop ao UNIQUE do banco)
class AiAgent::FollowUps::CandidateFinder
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

    # Itera a cadência completa (passo 1 = regra + passos adicionais).
    # Cada passo gera seus próprios candidatos com `target_at`/`step_id`
    # próprios; os filtros transversais rodam sobre o conjunto.
    stops = AiAgent::FollowUps::StopConditions.new(@rule, now: @now)

    dispatch_steps
      .flat_map { |step| candidates_for(step) }
      .reject { |c| opted_out?(c[:contact_id]) }
      .reject { |c| stops.stopped?(c) }
      .reject { |c| cap_reached?(c) }
      .reject { |c| already_executed?(c) }
  end

  private

  # service_recall é single-shot (usa o intervalo do serviço, não cadência):
  # roda só o passo base, mesmo que passos extras existam por engano —
  # senão N passos com o MESMO target_at gerariam N recalls iguais.
  def dispatch_steps
    return [@rule.dispatch_steps.first] if @rule.service_recall?

    @rule.dispatch_steps
  end

  def candidates_for(step)
    case @rule.trigger_type
    when 'pre_appointment'  then find_pre_appointment(step)
    when 'post_appointment' then find_post_appointment(step)
    when 'no_response'      then find_no_response(step)
    when 'no_show'          then find_no_show(step)
    when 'service_recall'   then AiAgent::FollowUps::ServiceRecallFinder.new(@rule, step, now: @now).call
    else []
    end
  end

  def rule_active?
    return false unless @rule.enabled
    return false if @rule.account.nil?

    AiAgent::ConfigResolver.new(@rule.account).enabled?
  rescue StandardError
    false
  end

  # ── triggers ────────────────────────────────────────────────────

  # N horas ANTES de AgendaEvent.starts_at. Status default =
  # scheduled/confirmed (pode ser sobrescrito por `status_filter`).
  def find_pre_appointment(step)
    offset = step.offset_seconds.seconds
    agenda_candidates(step,
                      statuses: filter_statuses(default: %w[scheduled confirmed]),
                      window: window_around(@now + offset)) { |starts_at| starts_at - offset }
  end

  # N horas DEPOIS do starts_at — útil pra "como foi sua consulta?",
  # NPS, reagendamento de no_show, etc.
  def find_post_appointment(step)
    offset = step.offset_seconds.seconds
    agenda_candidates(step,
                      statuses: filter_statuses(default: %w[completed no_show]),
                      window: window_around(@now - offset)) { |starts_at| starts_at + offset }
  end

  # Atalho de post_appointment, status filtrado em no_show. Mantido
  # como trigger separado pra ficar legível na UI ("Reagendar quem
  # faltou") e permitir cooldown próprio.
  def find_no_show(step)
    offset = step.offset_seconds.seconds
    agenda_candidates(step, statuses: %w[no_show],
                            window: window_around(@now - offset)) { |starts_at| starts_at + offset }
  end

  # Busca eventos da agenda na janela e monta os candidatos. Eventos
  # criados pela UI/Bea costumam ter contact_id NIL (vínculo via
  # custom_attributes.patient_id) — resolve o contato pelo Patient; sem
  # contato resolvível não há canal, descarta. Ignora soft-deletados
  # (deleted_at): consulta excluída da agenda nunca gera mensagem.
  def agenda_candidates(step, statuses:, window:)
    return [] unless defined?(::AgendaEvent)

    scope = ::AgendaEvent.where(account_id: @rule.account_id, status: statuses, deleted_at: nil)
                         .where(starts_at: window)
    rows = filter_by_source(scope)
           .pluck(:id, :starts_at, :contact_id, Arel.sql("custom_attributes ->> 'patient_id'"))
    contacts = patient_contact_ids(rows)
    rows.filter_map do |event_id, starts_at, contact_id, patient_id|
      cid = contact_id || contacts[patient_id.to_s]
      next if cid.blank?

      { contact_id: cid, conversation_id: nil, agenda_event_id: event_id, step_id: step.id,
        anchor_at: starts_at, target_at: yield(starts_at) }
    end
  end

  # patient_id (string, vindo do jsonb) → contact_id, escopado pela conta.
  def patient_contact_ids(rows)
    pids = rows.filter_map { |_id, _at, contact_id, patient_id| patient_id if contact_id.nil? }
    return {} if pids.empty? || !defined?(::Patient)

    ::Patient.where(account_id: @rule.account_id, id: pids)
             .pluck(:id, :contact_id)
             .to_h
             .transform_keys(&:to_s)
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

  # Conversa em que a CLÍNICA/Bea falou por último (outgoing) e o
  # paciente está em silêncio há mais de offset — "paciente parou de
  # responder". A âncora do episódio é esse outgoing; os beats da
  # cadência disparam em âncora+offset de cada passo. Se o paciente
  # responder, a última vira incoming e a conversa sai do gatilho
  # naturalmente. (Última mensagem INCOMING sem resposta = clínica é
  # quem está devendo — nunca cutucamos o paciente nesse caso.)
  def find_no_response(step)
    return [] unless defined?(::Conversation) && defined?(::Message)

    cutoff = @now - step.offset_seconds.seconds
    last_message_ids_per_open_conversation.filter_map do |conv_id, max_id|
      no_response_candidate(conv_id, max_id, cutoff, step)
    end
  end

  # ÚLTIMA mensagem (não-privada) por conversa aberta OU pendente (com a
  # Bea ativa, a maioria fica em `pending` — só `open` deixaria o trigger
  # cego), considerando TODAS as mensagens até agora — assim um outgoing
  # recente da clínica desqualifica a conversa. EXCETO os outgoing que o
  # PRÓPRIO motor mandou (execution.message_id): senão o beat 1 da
  # cadência contaria como "clínica respondeu" e mataria os beats 2..N.
  # `.reorder(nil)` limpa o default_scope asc do Message pro GROUP BY.
  def last_message_ids_per_open_conversation
    ::Message
      .reorder(nil)
      .joins(:conversation)
      .where(conversations: { account_id: @rule.account_id, status: %w[open pending] })
      .where(message_type: %i[incoming outgoing])
      .where(private: false)
      .where.not(id: engine_sent_message_ids)
      .group(:conversation_id)
      .pluck('conversation_id', 'MAX(messages.id)')
  end

  # Mensagens já enviadas pelo motor de follow-up nesta conta (subquery;
  # o `where.not(message_id: nil)` evita NOT IN com NULL, que zeraria tudo).
  def engine_sent_message_ids
    AiAgent::FollowUpExecution.where(account_id: @rule.account_id).where.not(message_id: nil).select(:message_id)
  end

  def no_response_candidate(conv_id, max_id, cutoff, step)
    last = ::Message.find_by(id: max_id)
    # Só dispara se a ÚLTIMA mensagem (não-privada, não-motor) é da
    # CLÍNICA (outgoing) E já é mais antiga que o cutoff — paciente em
    # silêncio há >= offset desde a última fala da clínica/Bea.
    return nil unless last&.message_type == 'outgoing' && last.created_at <= cutoff

    conversation = ::Conversation.find_by(id: conv_id)
    return nil unless conversation

    {
      contact_id: conversation.contact_id,
      conversation_id: conv_id,
      agenda_event_id: nil,
      step_id: step.id,
      anchor_at: last.created_at,
      target_at: last.created_at + step.offset_seconds.seconds
    }
  end

  # ── filtros transversais ────────────────────────────────────────

  def opted_out?(contact_id)
    return false if contact_id.blank?

    mem = AiAgent::PatientMemory.find_by(account_id: @rule.account_id, contact_id: contact_id)
    return false if mem.nil?

    prefs = mem.preferences || {}
    prefs['recall_opt_out'] || prefs['follow_up_opt_out']
  end

  # Cap por (regra, contato, EVENTO-alvo) escopado por passo. Sem o
  # `step_id`, o cap de `1` faria a cadência parar no passo 1.
  #
  # Só se aplica a candidatos COM evento de agenda: para no_response e
  # service_recall o "alvo" é o episódio (âncora), cuja exatamente-uma-vez
  # já vem do índice único via target_at — um cap por contato aqui
  # bloquearia episódios futuros (ex: o recall do botox a cada 6 meses
  # dispararia uma única vez na VIDA do paciente).
  def cap_reached?(candidate)
    return false if @rule.max_per_target.to_i.zero?
    return false if candidate[:agenda_event_id].blank?

    AiAgent::FollowUpExecution
      .where(rule_id: @rule.id, status: 'sent', step_id: candidate[:step_id])
      .where(contact_id: candidate[:contact_id], agenda_event_id: candidate[:agenda_event_id])
      .count >= @rule.max_per_target.to_i
  end

  # Idempotência inclui `step_id`: dois passos distintos com o mesmo
  # target_at (ex: offsets iguais por engano) continuam sendo execuções
  # distintas em vez de um beat sumir. Casa com o índice único (COALESCE).
  def already_executed?(candidate)
    AiAgent::FollowUpExecution.exists?(
      rule_id: @rule.id,
      contact_id: candidate[:contact_id],
      agenda_event_id: candidate[:agenda_event_id],
      step_id: candidate[:step_id],
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
