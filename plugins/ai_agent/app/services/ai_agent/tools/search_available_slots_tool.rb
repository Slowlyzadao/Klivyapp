# Returns up to 3 real bookable slots for a specific service (spec BIA
# 2.1: "oferecer de 2 a 3 horários"), respecting which professionals
# offer it and each professional's own agenda. When period='qualquer'
# (default), distributes morning + afternoon (capped at 3 total) to give
# the patient real flexibility instead of dumping consecutive slots from
# the same period. A slot is "available" only
# if AT LEAST ONE eligible professional has no overlapping appointment
# in their personal calendar at that time.
#
# Returns `available_with: [{id, name}]` for each slot so Bea can
# offer the patient by name ("Tenho 9h com Dra. Ana ou Dr. Carlos").
#
# If the requested service has zero professionals linked, returns an
# explicit "no_professionals" payload that tells Bea to escalate —
# the clinic has not configured who does this procedure yet.
#
# Slot stepping uses the service's `duration_minutes` (not the
# clinic-wide slot_interval). So a 40-min service is offered at
# 09:00, 09:40, 10:20… instead of every 15 min.
#
# ARCH-3 (audit 2026-05-19): decomposto em 3 sub-services:
#   - `DateRangeValidator` — parsing + bounds checks da janela de busca
#   - `SlotAllocator`      — geração de slots pra UMA data
#   - `PeriodDistributor`  — coleta multi-dia + balanceamento 2 manhã / 2 tarde
# Tool principal mantém orquestração + pré-carga de eventos (DB) +
# formatação de gap_context / notes pra Bea (lógica de brand/UX).
class AiAgent::Tools::SearchAvailableSlotsTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Busca horários reais disponíveis na agenda PARA UM SERVIÇO específico.
    Use SEMPRE depois de `clinic_info` (que dá o `service_id` certo) e
    antes de `book_appointment`. Retorna de 2 a 3 slots reais que podem
    ser agendados sem conflito, com indicação de QUAL profissional
    está livre em cada um. Quando period="qualquer" (default),
    distribui manhã + tarde (no máx. 3) pra dar flexibilidade ao paciente.

    Parâmetros:
    - service_id: ID do serviço (obrigatório). Pegue de `clinic_info`.
    - from_date: data inicial YYYY-MM-DD. Use as datas absolutas do
      [CONTEXTO ATUAL] (ex: amanhã = a data exata fornecida).
    - to_date: data final YYYY-MM-DD (opcional, default = from_date + 7d).
    - period: filtro opcional ("manha", "tarde", "noite", "qualquer").
    - requested_time: SE o paciente disse explicitamente um horário
      (ex: "às 18h", "umas 6 da tarde", "9 da manhã"), passe aqui no
      formato "HH:MM" 24h. Quando o melhor disponível for diferente,
      o retorno traz `gap_context` com instrução de empatia. NÃO
      invente esse parâmetro se o paciente não falou horário; deixe
      em branco.

    NUNCA chame essa tool sem `service_id`. NUNCA ofereça horário ao
    paciente sem ter chamado essa tool antes.
  DESC

  param :service_id,
        type: :integer,
        desc: 'ID do AgendaService desejado. Pegue de `clinic_info` services[].id. OBRIGATÓRIO.'

  param :from_date,
        type: :string,
        desc: 'Data inicial em YYYY-MM-DD. Use a data ABSOLUTA do contexto atual, não palavras como "amanhã".'

  param :to_date,
        type: :string,
        required: false,
        desc: 'Data final em YYYY-MM-DD. Default: from_date + 7 dias. Janela máxima: 14 dias.'

  param :period,
        type: :string,
        required: false,
        desc: 'Filtro de período: "manha" (5h-11h), "tarde" (12h-17h), "noite" (a partir das 18h), ou "qualquer".'

  param :requested_time,
        type: :string,
        required: false,
        desc: 'Horário que o paciente PEDIU explicitamente, no formato HH:MM (24h). Ex: paciente disse "umas 6 da tarde" → "18:00". Só passe se ele falou; senão deixe em branco.'

  param :only_user_id,
        type: :integer,
        required: false,
        desc: 'ID de um profissional. Use no REAGENDAMENTO pra buscar horários só do mesmo doutor. Omitido = todos os profissionais do serviço.'

  MIN_DURATION = 15
  MAX_DURATION = 240
  BLOCKING_STATUSES = %w[scheduled confirmed arrived in_progress completed].freeze

  def execute(service_id:, from_date:, to_date: nil, period: 'qualquer', requested_time: nil, only_user_id: nil)
    return failure('Módulo de agenda não disponível.') unless defined?(::AgendaSetting) && defined?(::AgendaEvent) && defined?(::AgendaService)

    service = ::AgendaService.where(account_id: account.id).find_by(id: service_id)
    return failure("Serviço #{service_id} não encontrado nesta clínica. Chame clinic_info pra ver os IDs corretos.") if service.nil?

    professionals = service.professionals.to_a
    return no_professionals_result(service) if professionals.empty?

    # Reagendamento: restringe a busca ao MESMO profissional da consulta
    # original (only_user_id), pra não oferecer horário de outro doutor.
    if only_user_id.present?
      professionals = professionals.select { |u| u.id == only_user_id.to_i }
      return wrong_professional_result(service, only_user_id) if professionals.empty?
    end

    setting = ::AgendaSetting.find_by(account_id: account.id)
    return failure('Configurações de agenda não definidas para essa clínica.') if setting.nil? || setting.week_days.blank?

    duration = service.duration_minutes.to_i
    duration = 60 if duration <= 0
    return failure("Duração do serviço inválida (#{duration}min).") unless duration.between?(MIN_DURATION, MAX_DURATION)

    window = DateRangeValidator.call(from_date: from_date, to_date: to_date)
    return failure(window.error_message) if window.error_message

    zone = ActiveSupport::TimeZone.new(AiAgent::ContextBuilder::CLINIC_TIMEZONE)
    now_local = Time.current.in_time_zone(zone)

    blocking_per_user = preload_blocking_events_per_user(professionals, window.from, window.to, zone)
    slots = PeriodDistributor.call(
      period: period, from: window.from, to: window.to, setting: setting, duration: duration,
      zone: zone, now_local: now_local, professionals: professionals, blocking_per_user: blocking_per_user,
      requested_minutes: parse_minutes(requested_time)
    )

    return empty_result(service, window.from, window.to, requested_time, setting, window.from) if slots.empty?

    gap = build_gap_context(requested_time, slots, setting, window.from)

    {
      available: true,
      service: { id: service.id, name: service.name, duration_minutes: duration },
      slots: slots,
      total_found: slots.size,
      searched_window: "#{window.from.strftime('%d/%m/%Y')} → #{window.to.strftime('%d/%m/%Y')}",
      requested_time: requested_time,
      period_requested: period,
      gap_context: gap,
      note_for_bea: build_note_for_bea(gap)
    }
  end

  private

  # Pre-carrega eventos bloqueantes DE CADA profissional na janela.
  # Indexado por user_id pra checagem O(1) durante a iteração.
  def preload_blocking_events_per_user(professionals, from, to, zone)
    window_start = zone.local(from.year, from.month, from.day, 0, 0).utc
    window_end   = zone.local(to.year, to.month, to.day, 23, 59, 59).utc

    events = ::AgendaEvent.kept
             .where(account_id: account.id, status: BLOCKING_STATUSES, user_id: professionals.map(&:id))
             .where('starts_at < ? AND ends_at > ?', window_end, window_start)
             .pluck(:user_id, :starts_at, :ends_at)

    professionals.each_with_object({}) do |u, h|
      h[u.id] = events.select { |row| row[0] == u.id }.map { |row| [row[1], row[2]] }
    end
  end

  def empty_result(service, from, to, requested_time = nil, setting = nil, day = nil)
    gap = closed_window_gap(requested_time, setting, day)
    note = if gap
             "ESPELHO obrigatório: o paciente pediu #{gap[:requested_pretty]}, mas a clínica #{gap[:reason]}. Comece a resposta reconhecendo o pedido dele em UMA frase natural e PROFISSIONAL — sem gírias regionais (não use 'pô', 'tô', 'rola', 'foi mal', 'tipo'). Exemplo de tom: 'Entendi! Mas #{gap[:requested_pretty]} a clínica #{gap[:reason]}.' DEPOIS sugira alargar a janela ou outro período. NUNCA simplesmente liste alternativas sem reconhecer o pedido."
           else
             'Sugira ao paciente alargar a janela (próxima semana, ou outro período) ou ofereça entrar na lista de espera. Use frase natural e PROFISSIONAL, sem gíria, sem listas.'
           end

    {
      available: false,
      service: { id: service.id, name: service.name },
      slots: [],
      searched_window: "#{from.strftime('%d/%m/%Y')} → #{to.strftime('%d/%m/%Y')}",
      requested_time: requested_time,
      gap_context: gap,
      message: 'Nenhum dos profissionais que realizam esse serviço tem horário livre nessa janela.',
      note_for_bea: note
    }
  end

  # Detecta o "gap" entre o horário pedido pelo paciente e o melhor
  # disponível. Retorna nil quando não há requested_time ou quando
  # o pedido está dentro da janela disponível (sem necessidade de
  # espelho — Bea pode oferecer normalmente).
  #
  # Casos detectados:
  #   - Paciente pediu fora do horário da clínica (clinic fechou antes)
  #   - Paciente pediu durante o horário de almoço
  #   - Paciente pediu horário ocupado, mas clínica está aberta
  def build_gap_context(requested_time, slots, setting, day)
    req_min = parse_minutes(requested_time)
    return nil if req_min.nil?
    return nil if slots.empty?

    # Slot exato bate? Sem gap.
    return nil if slots.any? { |s| s[:time] == format('%02d:%02d', req_min / 60, req_min % 60) }

    closed = closed_window_gap(requested_time, setting, day)
    return closed if closed

    nearest = nearest_slot(slots, req_min)
    {
      kind: 'time_unavailable',
      requested: format('%02d:%02d', req_min / 60, req_min % 60),
      requested_pretty: format_pretty_time(req_min),
      nearest_offered: nearest[:time],
      reason: 'esse horário específico já está ocupado, mas tenho outras opções por perto'
    }
  end

  # Quando o paciente pede horário FORA da janela de funcionamento da
  # clínica naquele dia (fechado, antes de abrir, depois de fechar,
  # ou no almoço). Retorna hash com `closing_pretty` pra Bea poder
  # explicar com naturalidade.
  def closed_window_gap(requested_time, setting, day)
    return nil if requested_time.blank? || setting.nil? || day.nil?

    req_min = parse_minutes(requested_time)
    return nil if req_min.nil?

    cfg = PeriodDistributor.find_day_config(setting.week_days, day.wday)
    if cfg.nil? || !cfg['enabled']
      return { kind: 'closed_day', requested_pretty: format_pretty_time(req_min), reason: 'não atende nesse dia da semana',
               closing_pretty: 'nesse dia' }
    end

    open_start = parse_minutes(cfg['start'])
    open_end   = parse_minutes(cfg['end'])
    return nil if open_start.nil? || open_end.nil?

    if req_min < open_start
      return {
        kind: 'before_opening',
        requested: requested_time,
        requested_pretty: format_pretty_time(req_min),
        reason: "abre só às #{format_pretty_time(open_start)} nesse dia",
        closing_pretty: "abre #{format_pretty_time(open_start)}"
      }
    end

    if req_min >= open_end
      return {
        kind: 'after_closing',
        requested: requested_time,
        requested_pretty: format_pretty_time(req_min),
        reason: "fecha às #{format_pretty_time(open_end)} nesse dia",
        closing_pretty: format_pretty_time(open_end)
      }
    end

    lunch_start = parse_minutes(cfg['lunchStart'])
    lunch_end = parse_minutes(cfg['lunchEnd'])
    if !lunch_start.nil? && !lunch_end.nil? && req_min >= lunch_start && req_min < lunch_end
      return {
        kind: 'lunch_break',
        requested: requested_time,
        requested_pretty: format_pretty_time(req_min),
        reason: "está no horário de almoço (#{format_pretty_time(lunch_start)}–#{format_pretty_time(lunch_end)})",
        closing_pretty: "depois das #{format_pretty_time(lunch_end)}"
      }
    end

    nil
  end

  def nearest_slot(slots, req_min)
    slots.min_by do |s|
      h, m = s[:time].split(':').map(&:to_i)
      ((h * 60) + m - req_min).abs
    end
  end

  def parse_minutes(value)
    return nil if value.to_s.empty?

    h, m = value.to_s.split(':').map(&:to_i)
    return nil if h.nil? || m.nil?

    (h * 60) + m
  end

  def format_pretty_time(minutes)
    h = minutes / 60
    m = minutes % 60
    return "#{h}h" if m.zero?

    format('%dh%02d', h, m)
  end

  def build_note_for_bea(gap)
    base = 'Mostre TODOS os horários retornados ao paciente em PROSA NATURAL e PROFISSIONAL (sem listas, sem bullets, sem gíria regional). Quando vier mix de manhã+tarde, agrupa pelos dois períodos pra ficar claro (ex: "Tenho amanhã 9h e 10h da manhã, ou 14h e 15h30 à tarde"). Sempre indique qual profissional está disponível (use available_with). Se houver mais de um profissional livre num slot, ofereça os dois. Depois chame book_appointment passando starts_at + user_id do profissional escolhido.'

    return base if gap.nil?

    case gap[:kind]
    when 'after_closing', 'before_opening', 'closed_day', 'lunch_break'
      "ESPELHO obrigatório: o paciente pediu #{gap[:requested_pretty]}, mas a clínica #{gap[:reason]}. Comece a resposta reconhecendo o pedido dele em UMA frase profissional e calorosa (sem gírias como 'pô', 'tô', 'rola', 'foi mal'). Exemplo de tom: 'Entendi! Mas #{gap[:requested_pretty]} a clínica #{gap[:reason]}.' DEPOIS ofereça os horários disponíveis em prosa. JAMAIS liste horários sem antes reconhecer o que ele pediu."
    when 'time_unavailable'
      "ESPELHO obrigatório: o paciente pediu #{gap[:requested_pretty]}, e #{gap[:reason]} (mais próximo é #{gap[:nearest_offered]}). Reconheça o pedido em UMA frase profissional antes de listar (ex: 'Nesse horário específico não tenho disponibilidade, mas posso te oferecer #{gap[:nearest_offered]} com a mesma profissional.'). Sem gíria, sem 'tô', 'rola', 'pô'. NUNCA jogue a lista de horários direto sem reconhecer."
    else
      base
    end
  end

  def no_professionals_result(service)
    # Serviço sem profissional vinculado = a clínica NÃO atende. Devolve a
    # lista do que ela ATENDE (serviços com profissional) pra Bea informar
    # na hora ("não fazemos implante; atendemos avaliação e limpeza").
    offered = if defined?(::AgendaServiceUser)
                linked = ::AgendaServiceUser.where(account_id: account.id).select(:agenda_service_id)
                ::AgendaService.where(account_id: account.id, id: linked).limit(20).map { |s| { id: s.id, name: s.name } }
              else
                []
              end
    {
      available: false,
      service: { id: service.id, name: service.name },
      slots: [],
      available_services: offered,
      message: "A clínica não atende \"#{service.name}\" (nenhum profissional realiza esse serviço).",
      note_for_bea: "A clínica NÃO atende \"#{service.name}\". NÃO agende e NÃO transfira: diga com leveza que " \
                    'infelizmente esse serviço não é atendido e LISTE os serviços de available_services como alternativa.'
    }
  end

  # O LLM às vezes INVENTA o only_user_id (caso real: passou 1, o Dr. era
  # 721) e, com o erro genérico, traduzia pro paciente como "agenda
  # cheia"/"não tem esse horário" — mentira. Erro AUTO-CORRETIVO: devolve os
  # profissionais válidos (id + nome) e proíbe concluir indisponibilidade.
  def wrong_professional_result(service, wrong_id)
    validos = service.professionals.map { |u| { id: u.id, name: u.name } }
    {
      available: false,
      error: "O user_id #{wrong_id} NÃO realiza o serviço \"#{service.name}\" — você provavelmente passou o ID ERRADO.",
      valid_professionals: validos,
      slots: [],
      note_for_bea: 'ATENÇÃO: isso NÃO significa agenda cheia — você consultou o profissional ERRADO. É PROIBIDO dizer ao ' \
                    'paciente que o horário está ocupado/indisponível por causa deste erro. Re-chame search_available_slots ' \
                    'AGORA com o only_user_id correto da lista valid_professionals (ou sem only_user_id pra buscar todos).'
    }
  end

  def failure(msg)
    { available: false, error: msg, slots: [] }
  end
end
