module AiAgent
  module Tools
    # Returns up to 4 real bookable slots for a specific service,
    # respecting which professionals offer it and each professional's own
    # agenda. When period='qualquer' (default), distributes 2 morning + 2
    # afternoon to give the patient real flexibility instead of dumping 4
    # consecutive slots from the same period. A slot is "available" only
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
    class SearchAvailableSlotsTool < BaseTool
      description <<~DESC
        Busca horários reais disponíveis na agenda PARA UM SERVIÇO específico.
        Use SEMPRE depois de `clinic_info` (que dá o `service_id` certo) e
        antes de `book_appointment`. Retorna até 4 slots reais que podem
        ser agendados sem conflito, com indicação de QUAL profissional
        está livre em cada um. Quando period="qualquer" (default),
        distribui 2 manhã + 2 tarde pra dar flexibilidade real ao paciente.

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

      DAY_FULL_LABELS = {
        0 => 'domingo',
        1 => 'segunda-feira',
        2 => 'terça-feira',
        3 => 'quarta-feira',
        4 => 'quinta-feira',
        5 => 'sexta-feira',
        6 => 'sábado'
      }.freeze

      DAY_SHORT_LABELS = {
        0 => 'domingo',
        1 => 'segunda',
        2 => 'terça',
        3 => 'quarta',
        4 => 'quinta',
        5 => 'sexta',
        6 => 'sábado'
      }.freeze

      MAX_RESULTS = 4
      MAX_PER_PERIOD = 2  # Quando period=qualquer, distribui 2 manhã + 2 tarde
      MAX_WINDOW_DAYS = 14
      MIN_DURATION = 15
      MAX_DURATION = 240
      BLOCKING_STATUSES = %w[scheduled confirmed arrived in_progress completed].freeze

      def execute(service_id:, from_date:, to_date: nil, period: 'qualquer', requested_time: nil)
        return failure('Módulo de agenda não disponível.') unless defined?(::AgendaSetting) && defined?(::AgendaEvent) && defined?(::AgendaService)

        service = ::AgendaService.where(account_id: account.id).find_by(id: service_id)
        return failure("Serviço #{service_id} não encontrado nesta clínica. Chame clinic_info pra ver os IDs corretos.") if service.nil?

        professionals = service.users.to_a
        return no_professionals_result(service) if professionals.empty?

        setting = ::AgendaSetting.find_by(account_id: account.id)
        return failure('Configurações de agenda não definidas para essa clínica.') if setting.nil? || setting.week_days.blank?

        duration = service.duration_minutes.to_i
        duration = 60 if duration <= 0
        return failure("Duração do serviço inválida (#{duration}min).") unless duration.between?(MIN_DURATION, MAX_DURATION)

        from, to, err = parse_window(from_date, to_date)
        return err if err

        zone = ActiveSupport::TimeZone.new(AiAgent::ContextBuilder::CLINIC_TIMEZONE)
        now_local = Time.current.in_time_zone(zone)

        blocking_per_user = preload_blocking_events_per_user(professionals, from, to, zone)
        slots = collect_slots(
          from: from, to: to, setting: setting, service: service, duration: duration,
          period: normalize_period(period), zone: zone, now_local: now_local,
          professionals: professionals, blocking_per_user: blocking_per_user
        )

        return empty_result(service, from, to, requested_time, setting, from) if slots.empty?

        gap = build_gap_context(requested_time, slots, setting, from)

        {
          available: true,
          service: { id: service.id, name: service.name, duration_minutes: duration },
          slots: slots,
          total_found: slots.size,
          searched_window: "#{from.strftime('%d/%m/%Y')} → #{to.strftime('%d/%m/%Y')}",
          requested_time: requested_time,
          gap_context: gap,
          note_for_bea: build_note_for_bea(gap)
        }
      end

      private

      def parse_window(from_date, to_date)
        from = Date.parse(from_date.to_s)
        to   = to_date.present? ? Date.parse(to_date.to_s) : from + 7
        from = Date.current if from < Date.current
        return [nil, nil, failure('Data final no passado.')] if to < Date.current
        return [nil, nil, failure("Janela maior que #{MAX_WINDOW_DAYS} dias — quebre a busca em pedaços.")] if (to - from) > MAX_WINDOW_DAYS

        [from, to, nil]
      rescue ArgumentError
        [nil, nil, failure('Data inválida. Use formato YYYY-MM-DD.')]
      end

      # Pre-carrega eventos bloqueantes DE CADA profissional na janela.
      # Indexado por user_id pra checagem O(1) durante a iteração.
      def preload_blocking_events_per_user(professionals, from, to, zone)
        window_start = zone.local(from.year, from.month, from.day, 0, 0).utc
        window_end   = zone.local(to.year, to.month, to.day, 23, 59, 59).utc

        events = ::AgendaEvent
                 .where(account_id: account.id, status: BLOCKING_STATUSES, user_id: professionals.map(&:id))
                 .where('starts_at < ? AND ends_at > ?', window_end, window_start)
                 .pluck(:user_id, :starts_at, :ends_at)

        professionals.each_with_object({}) do |u, h|
          h[u.id] = events.select { |row| row[0] == u.id }.map { |row| [row[1], row[2]] }
        end
      end

      def collect_slots(from:, to:, setting:, service:, duration:, period:, zone:, now_local:, professionals:, blocking_per_user:)
        # Quando o paciente NÃO especificou período (period=qualquer), oferece
        # uma distribuição balanceada 2 manhã + 2 tarde. Se um lado tem
        # menos, completa com o outro até totalizar MAX_RESULTS. Isso evita
        # despejar 4 slots todos da manhã quando o paciente quer flexibilidade.
        return collect_balanced_slots(from: from, to: to, setting: setting, duration: duration, zone: zone, now_local: now_local, professionals: professionals, blocking_per_user: blocking_per_user) if period == 'qualquer'

        slots = []
        cursor = from

        while cursor <= to && slots.size < MAX_RESULTS
          day_cfg = find_day_config(setting.week_days, cursor.wday)
          slots.concat(slots_for_day(
                         date: cursor, cfg: day_cfg, duration: duration, period: period,
                         zone: zone, now_local: now_local, professionals: professionals,
                         blocking_per_user: blocking_per_user, remaining: MAX_RESULTS - slots.size
                       ))
          cursor = cursor.next_day
        end

        slots
      end

      # Coleta separada por período (manhã + tarde), depois balanceia
      # 2+2. Se um período tem menos, complementa com o outro até MAX_RESULTS.
      # Ordena o resultado final por starts_at pra apresentar em ordem
      # cronológica natural.
      def collect_balanced_slots(from:, to:, setting:, duration:, zone:, now_local:, professionals:, blocking_per_user:)
        morning = collect_period_slots(period: 'manha', limit: MAX_PER_PERIOD * 2,
                                       from: from, to: to, setting: setting, duration: duration,
                                       zone: zone, now_local: now_local, professionals: professionals,
                                       blocking_per_user: blocking_per_user)
        afternoon = collect_period_slots(period: 'tarde', limit: MAX_PER_PERIOD * 2,
                                         from: from, to: to, setting: setting, duration: duration,
                                         zone: zone, now_local: now_local, professionals: professionals,
                                         blocking_per_user: blocking_per_user)

        morning_pick = morning.take(MAX_PER_PERIOD)
        afternoon_pick = afternoon.take(MAX_PER_PERIOD)

        deficit_m = MAX_PER_PERIOD - morning_pick.size
        deficit_a = MAX_PER_PERIOD - afternoon_pick.size
        afternoon_pick.concat(afternoon.drop(MAX_PER_PERIOD).take(deficit_m)) if deficit_m.positive?
        morning_pick.concat(morning.drop(MAX_PER_PERIOD).take(deficit_a)) if deficit_a.positive?

        (morning_pick + afternoon_pick).sort_by { |s| s[:starts_at] }
      end

      def collect_period_slots(period:, limit:, from:, to:, setting:, duration:, zone:, now_local:, professionals:, blocking_per_user:)
        slots = []
        cursor = from

        while cursor <= to && slots.size < limit
          day_cfg = find_day_config(setting.week_days, cursor.wday)
          slots.concat(slots_for_day(
                         date: cursor, cfg: day_cfg, duration: duration, period: period,
                         zone: zone, now_local: now_local, professionals: professionals,
                         blocking_per_user: blocking_per_user, remaining: limit - slots.size
                       ))
          cursor = cursor.next_day
        end

        slots
      end

      # Step pela DURAÇÃO do serviço (não pelo slot_interval). Slot é
      # válido se pelo menos 1 profissional está livre — `available_with`
      # carrega quem.
      def slots_for_day(date:, cfg:, duration:, period:, zone:, now_local:, professionals:, blocking_per_user:, remaining:)
        return [] if cfg.nil? || !cfg['enabled']

        open_start = parse_minutes(cfg['start'])
        open_end   = parse_minutes(cfg['end'])
        return [] if open_start.nil? || open_end.nil?

        lunch_start = parse_minutes(cfg['lunchStart'])
        lunch_end   = parse_minutes(cfg['lunchEnd'])

        out = []
        slot_min = open_start

        while slot_min + duration <= open_end && out.size < remaining
          unless skip_slot?(slot_min, duration, lunch_start, lunch_end, period)
            slot_time = zone.local(date.year, date.month, date.day, slot_min / 60, slot_min % 60)

            if slot_time >= now_local
              available_with = professionals.reject do |u|
                overlaps?(slot_time, duration, blocking_per_user[u.id] || [])
              end
              out << format_slot(slot_time, date, available_with) if available_with.any?
            end
          end
          slot_min += duration
        end

        out
      end

      def skip_slot?(slot_min, duration, lunch_start, lunch_end, period)
        return true if in_lunch?(slot_min, duration, lunch_start, lunch_end)
        return true unless period_match?(slot_min, period)

        false
      end

      def in_lunch?(slot_min, duration, lunch_start, lunch_end)
        return false if lunch_start.nil? || lunch_end.nil?

        slot_min < lunch_end && (slot_min + duration) > lunch_start
      end

      def period_match?(slot_min, period)
        return true if period == 'qualquer'

        hour = slot_min / 60
        case period
        when 'manha' then hour.between?(5, 11)
        when 'tarde' then hour.between?(12, 17)
        when 'noite' then hour >= 18
        else true
        end
      end

      def overlaps?(slot_time, duration, intervals)
        slot_end = slot_time + duration.minutes
        intervals.any? { |evt_start, evt_end| slot_time < evt_end && slot_end > evt_start }
      end

      def format_slot(slot_time, date, available_with)
        {
          starts_at: slot_time.iso8601,
          date: slot_time.strftime('%d/%m/%Y'),
          time: slot_time.strftime('%H:%M'),
          weekday: DAY_FULL_LABELS[date.wday],
          available_with: available_with.map { |u| { id: u.id, name: AiAgent::Formatters::ProfessionalName.format(u.name) } }
        }
      end

      def find_day_config(week_days, wday)
        target = DAY_SHORT_LABELS[wday]
        week_days.find do |d|
          normalized = d['label'].to_s.downcase.sub(/-feira$/, '').strip
          normalized.start_with?(target)
        end
      end

      def parse_minutes(value)
        return nil if value.to_s.empty?

        h, m = value.to_s.split(':').map(&:to_i)
        return nil if h.nil? || m.nil?

        (h * 60) + m
      end

      def normalize_period(period)
        period.to_s.downcase.tr('ãâá', 'aaa').strip
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

        cfg = find_day_config(setting.week_days, day.wday)
        return { kind: 'closed_day', requested_pretty: format_pretty_time(req_min), reason: 'não atende nesse dia da semana', closing_pretty: 'nesse dia' } if cfg.nil? || !cfg['enabled']

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
        {
          available: false,
          service: { id: service.id, name: service.name },
          slots: [],
          message: "A clínica ainda não cadastrou profissionais para o serviço \"#{service.name}\".",
          note_for_bea: 'NÃO ofereça agendamento desse serviço. Avise o paciente que vai transferir pra equipe humana e chame transfer_to_human.'
        }
      end

      def failure(msg)
        { available: false, error: msg, slots: [] }
      end
    end
  end
end
