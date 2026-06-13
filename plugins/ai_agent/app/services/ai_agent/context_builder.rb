# Builds the per-turn context block injected as a PREFIX to the user's
# message at every turn. Different from PromptBuilder — that one assembles
# the cached system prompt (static across turns). This one intentionally
# contains values that change every turn (datetime, clinic status, patient
# context) and therefore MUST NOT go into the system prompt or it would
# invalidate the prompt cache on every request.
#
# Single rule: freeze the clock at construction time. Don't call
# Time.current inside this class. The caller passes `now:` so the same
# value is used across every helper, and so tests can fix time.
class AiAgent::ContextBuilder
  # Default clinic timezone. Will become a per-account setting in a later
  # sprint; for now every Klivy clinic is in Brazil.
  CLINIC_TIMEZONE = 'America/Sao_Paulo'.freeze

  # Wday → label without "-feira" suffix. Used to match against
  # AgendaSetting.week_days[*]['label'].
  DAY_SHORT_LABELS = {
    0 => 'domingo',
    1 => 'segunda',
    2 => 'terça',
    3 => 'quarta',
    4 => 'quinta',
    5 => 'sexta',
    6 => 'sábado'
  }.freeze

  DAY_FULL_LABELS = {
    0 => 'domingo',
    1 => 'segunda-feira',
    2 => 'terça-feira',
    3 => 'quarta-feira',
    4 => 'quinta-feira',
    5 => 'sexta-feira',
    6 => 'sábado'
  }.freeze

  HOLIDAY_LOOKAHEAD_DAYS = 30

  def initialize(account:, now:, patient_memory: nil, contact_id: nil)
    @account = account
    @now = now.in_time_zone(CLINIC_TIMEZONE)
    @today = @now.to_date
    @patient_memory = patient_memory
    @contact_id = contact_id
  end

  # Returns the formatted context block, ready to prepend to the user's
  # message. Sections are joined with blank lines so the LLM sees them as
  # distinct chunks.
  def block
    sections = ['[CONTEXTO ATUAL — não mostrar ao paciente]']
    ci = clinic_identity_section
    sections << ci if ci
    sections << datetime_section
    cs = clinic_status_section
    sections << cs if cs
    sections << reference_dates_section
    ps = patient_section
    sections << ps if ps
    sections.join("\n\n")
  end

  private

  # Nome da clínica SEMPRE presente no contexto — sem isso a Bia só conhece o
  # nome se chamar clinic_info, e na saudação ela às vezes pula a tool e abre
  # com "Aqui é a Bia, da clínica." (genérico). Fonte = fantasy_name do
  # cadastro da clínica (mesma fonte do clinic_info).
  def clinic_identity_section
    name = @account.custom_attributes&.dig('fantasy_name').to_s.strip
    name = @account.name.to_s.strip if name.empty?
    return nil if name.empty?

    "Nome da clínica: #{name}\n  - Ao se apresentar, diga SEMPRE \"Aqui é a Bia, da #{name}\" (nunca \"da clínica\" genérico)."
  end

  def datetime_section
    [
      'Data e hora locais da clínica:',
      "  - Agora: #{DAY_FULL_LABELS[@today.wday]}, #{@today.strftime('%d/%m/%Y')}, #{@now.strftime('%H:%M')} (#{CLINIC_TIMEZONE})",
      "  - Período do dia: #{period_of_day}",
      "  - Saudação adequada agora: #{greeting_for_period}"
    ].join("\n")
  end

  def period_of_day
    h = @now.hour
    return 'madrugada' if h.between?(0, 4)
    return 'manhã' if h.between?(5, 11)
    return 'tarde' if h.between?(12, 17)

    'noite'
  end

  # Saudação pronta pra Bia usar. Evita o bug de ela espelhar o "bom dia" do
  # paciente quando na verdade é madrugada/noite. É dado variável → fica aqui
  # no prefixo do turno, NUNCA no system prompt (que precisa ficar cacheado).
  def greeting_for_period
    case period_of_day
    when 'madrugada' then 'boa madrugada'
    when 'manhã' then 'bom dia'
    when 'tarde' then 'boa tarde'
    else 'boa noite'
    end
  end

  # Returns "Status da clínica:" + one line, or nil if AgendaSetting isn't
  # available (Agenda plugin not loaded, or no settings row for this
  # account yet — in which case Bea simply won't have this hint).
  def clinic_status_section
    return nil unless defined?(::AgendaSetting)

    setting = ::AgendaSetting.find_by(account_id: @account.id)
    return nil if setting.nil? || setting.week_days.blank?

    today_cfg = find_day_config(setting.week_days, @today.wday)
    line = clinic_status_line(today_cfg, setting.week_days)
    "Status da clínica:\n#{line}"
  end

  def clinic_status_line(today_cfg, week_days)
    return "  - Clínica AGORA: fechada hoje#{next_open_suffix(week_days)}" if today_cfg.nil? || !today_cfg['enabled']

    start_min = parse_time_to_minutes(today_cfg['start'])
    end_min   = parse_time_to_minutes(today_cfg['end'])
    return '  - Clínica AGORA: horário não configurado para hoje' if start_min.nil? || end_min.nil?

    now_min = (@now.hour * 60) + @now.min

    return "  - Clínica AGORA: ainda fechada (abre hoje às #{today_cfg['start']})" if now_min < start_min
    return "  - Clínica AGORA: já fechou hoje#{next_open_suffix(week_days)}"        if now_min >= end_min

    lunch_line = on_lunch_break?(today_cfg, now_min)
    return "  - Clínica AGORA: em horário de almoço (volta às #{today_cfg['lunchEnd']})" if lunch_line

    "  - Clínica AGORA: aberta (fecha às #{today_cfg['end']})"
  end

  def on_lunch_break?(cfg, now_min)
    return false if cfg['lunchStart'].to_s.empty? || cfg['lunchEnd'].to_s.empty?

    lunch_start = parse_time_to_minutes(cfg['lunchStart'])
    lunch_end   = parse_time_to_minutes(cfg['lunchEnd'])
    return false if lunch_start.nil? || lunch_end.nil?

    now_min >= lunch_start && now_min < lunch_end
  end

  def next_open_suffix(week_days)
    next_open = next_opening(week_days)
    next_open ? " (próxima abertura: #{next_open})" : ''
  end

  # Walks forward 1..7 days looking for the next enabled day. Returns a
  # human label like "amanhã (07/05) às 08:00" or nil if no day is enabled
  # at all (clinic with empty schedule).
  def next_opening(week_days)
    (1..7).each do |delta|
      target = @today + delta
      cfg = find_day_config(week_days, target.wday)
      next if cfg.nil? || !cfg['enabled'] || cfg['start'].to_s.empty?

      relative = delta == 1 ? 'amanhã' : DAY_FULL_LABELS[target.wday]
      return "#{relative} (#{target.strftime('%d/%m')}) às #{cfg['start']}"
    end
    nil
  end

  def find_day_config(week_days, wday)
    target_label = DAY_SHORT_LABELS[wday]
    week_days.find do |d|
      normalized = d['label'].to_s.downcase.sub(/-feira$/, '').strip
      normalized.start_with?(target_label)
    end
  end

  def parse_time_to_minutes(value)
    return nil if value.to_s.empty?

    h, m = value.to_s.split(':').map(&:to_i)
    return nil if h.nil? || m.nil?

    (h * 60) + m
  end

  def reference_dates_section
    tomorrow      = @today + 1
    day_after     = @today + 2
    yesterday     = @today - 1
    next_monday   = next_weekday(1)
    next_saturday = next_weekday(6)

    lines = [
      'Datas de referência (use quando o paciente disser "amanhã", "ontem", "depois de amanhã", "próxima semana"):',
      "  - Hoje:             #{format_date_with_day(@today)}",
      "  - Amanhã:           #{format_date_with_day(tomorrow)}",
      "  - Depois de amanhã: #{format_date_with_day(day_after)}",
      "  - Ontem:            #{format_date_with_day(yesterday)}",
      "  - Próxima segunda:  #{next_monday.strftime('%d/%m/%Y')}",
      "  - Próximo sábado:   #{next_saturday.strftime('%d/%m/%Y')}"
    ]

    holiday = AiAgent::HolidayCalendar.next_within(@today, days: HOLIDAY_LOOKAHEAD_DAYS)
    lines << "  - Próximo feriado:  #{holiday[:date].strftime('%d/%m')} (#{holiday[:name]}) — em #{holiday[:days_away]} dias" if holiday

    lines.join("\n")
  end

  def format_date_with_day(date)
    "#{date.strftime('%d/%m/%Y')} (#{DAY_FULL_LABELS[date.wday]})"
  end

  # If today is Monday and target is Monday, "next monday" means 7 days
  # away — never "today".
  def next_weekday(target_wday)
    delta = (target_wday - @today.wday) % 7
    delta = 7 if delta.zero?
    @today + delta
  end

  # Minimal patient context for Sprint A: name and most recent semantic
  # memory entry (if any). Sprint D will deepen this with full timeline
  # consolidation. Returning nil when there's nothing useful keeps the
  # block lean for unidentified contacts.
  #
  # Order of precedence pro nome conhecido:
  #   1. Patient (prontuário) vinculado a este contact_id — fonte canônica.
  #   2. PatientMemory.preferences['name'] — fallback se Patient não carregou.
  # Sem isso, a Bea não sabe o nome do paciente na primeira mensagem
  # (ex: "Olá, tudo bem?") e responde genérico em vez de "Olá Leandro,
  # tudo bem por aqui...". O nome do prontuário é mais confiável que a
  # memória semantic destilada.
  def patient_section
    lines = ['Contexto do paciente:']
    added = false

    linked_name = patient_name_from_record
    if linked_name.present?
      lines << "  - Nome conhecido: #{linked_name}"
      lines << '  - Já identificado nesta conversa: SIM (não precisa pedir nome nem confirmar identidade — use o nome na saudação e siga direto)'
      added = true
    else
      # Fallback: paciente NÃO está vinculado a este Contact ainda
      # (cadastro de balcão sem WhatsApp, ou vínculo nunca feito).
      # Se houver exatamente 1 candidato por phone-match, presume e
      # diz pra Bea usar o nome na saudação MAS confirmar identidade
      # antes de qualquer ação irreversível (agendamento etc).
      presumed = presumed_patient_by_phone
      if presumed.present?
        lines << "  - Nome conhecido (presumido por telefone): #{presumed[:name]}"
        lines << '  - Já identificado nesta conversa: NÃO — apenas 1 paciente cadastrado com este telefone. Use o primeiro nome na saudação (humaniza a abertura), MAS quando o paciente pedir agendamento confirme a identidade via fluxo normal (find_patient_by_phone → caso C). Se o paciente negar ser essa pessoa, escala humano.'
        added = true
      elsif @patient_memory && @patient_memory.preferences.is_a?(Hash) && @patient_memory.preferences['name'].to_s.strip.present?
        lines << "  - Nome conhecido (memória semantic): #{@patient_memory.preferences['name']}"
        added = true
      end
    end

    if @patient_memory
      history = @patient_memory.history
      if history.is_a?(Array) && history.last.is_a?(Hash)
        last = history.last
        if last['summary'].to_s.strip.present?
          stamp = last['at'].to_s.presence || 'sem data'
          lines << "  - Última nota: [#{stamp}] #{last['summary']}"
          added = true
        end
      end
    end

    added ? lines.join("\n") : nil
  end

  def patient_name_from_record
    return nil if @contact_id.blank?
    return nil unless defined?(::Patient)

    patient = ::Patient.active.find_by(account_id: @account.id, contact_id: @contact_id)
    patient&.try(:full_name).presence || patient&.name
  end

  # Procura paciente por phone-match quando não há vínculo direto.
  # Reusa a mesma lógica de suffix de 8 dígitos do find_patient_by_phone.
  # Retorna { id:, name: } SOMENTE se houver EXATAMENTE 1 candidato e
  # ele não estiver vinculado a outro contato — qualquer ambiguidade
  # (família compartilhando número, ou Patient já vinculado a outro
  # Contact) faz o fallback retornar nil pra evitar saudar com nome
  # errado.
  def presumed_patient_by_phone
    return nil if @contact_id.blank?
    return nil unless defined?(::Patient)
    return nil unless defined?(::Contact)

    contact = ::Contact.find_by(id: @contact_id, account_id: @account.id)
    return nil if contact.nil?

    digits = contact.phone_number.to_s.gsub(/\D/, '')
    return nil if digits.length < 8

    suffix = digits.last(8)
    candidates = ::Patient.active.where(account_id: @account.id)
                          .where("REGEXP_REPLACE(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", "%#{suffix}")
                          .limit(2)
                          .to_a

    return nil if candidates.size != 1

    patient = candidates.first
    return nil if patient.contact_id.present? && patient.contact_id != @contact_id

    { id: patient.id, name: patient.try(:full_name).presence || patient.name }
  end
end
