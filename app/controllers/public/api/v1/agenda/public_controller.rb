class Public::Api::V1::Agenda::PublicController < ActionController::API
  before_action :fetch_user

  def show
    unless @account.agenda_online_config&.enabled
      render json: { error: 'Online booking is disabled' }, status: :forbidden
      return
    end

    render json: {
      user: {
        name: @user.name,
        display_name: @user.display_name,
        avatar_url: @user.avatar_url
      },
      config: @account.agenda_online_config
    }
  end

  def slots
    date = Date.parse(params[:date])
    slots = calculate_slots(date)
    render json: { slots: slots }
  rescue Date::Error
    render json: { error: 'Invalid date format' }, status: :bad_request
  end

  def book
    unless @account.agenda_online_config&.enabled
      render json: { error: 'Agendamento online desativado.' }, status: :forbidden
      return
    end

    date_iso = params[:date]
    time_str = params[:time]
    patient  = params[:patient]&.to_unsafe_h

    # Validações básicas
    missing = []
    missing << 'data'    if date_iso.blank?
    missing << 'horário' if time_str.blank?
    missing << 'paciente' if patient.blank?

    unless missing.empty?
      render json: { error: "Campos obrigatórios ausentes: #{missing.join(', ')}" }, status: :unprocessable_entity
      return
    end

    # Usar fuso horário de Brasília para interpretar os horários corretamente
    Time.use_zone('America/Sao_Paulo') do
      starts_at = Time.zone.parse("#{date_iso} #{time_str}")

      config = @account.agenda_online_config
      setting = @account.agenda_setting

      # Duração do slot — espelha exatamente o slot_interval_minutes
      # configurado pela clínica em AgendaSetting (mesmo valor que gera a
      # grade de slots em `calculate_slots`). Garante que o evento criado
      # ocupa um slot inteiro do calendário interno, sem sobreposição
      # parcial.
      slot_duration = (setting&.slot_interval_minutes || 60).to_i
      ends_at = starts_at + slot_duration.minutes

      min_lead = config.min_lead_time_minutes.to_i
      if starts_at < Time.zone.now + min_lead.minutes
        render json: { error: "Este horário não está mais disponível. O agendamento deve ser feito com pelo menos #{min_lead} minutos de antecedência." },
               status: :unprocessable_entity
        return
      end

      # Verificar conflito de eventos
      conflict = @account.agenda_events
                         .where(user_id: @user.id)
                         .where('starts_at < ? AND ends_at > ?', ends_at, starts_at)
                         .exists?

      if conflict
        render json: { error: 'Este horário já foi reservado. Por favor, escolha outro horário.' }, status: :conflict
        return
      end

      # Buscar ou criar contato
      phone = patient['phone']&.gsub(/\D/, '')
      email = patient['email'].presence
      cpf   = patient['cpf']&.gsub(/\D/, '')
      first_name = patient['first_name'].to_s.strip
      last_name  = patient['last_name'].to_s.strip
      full_name  = "#{first_name} #{last_name}".strip

      contact = nil

      # Tenta encontrar por CPF primeiro
      contact = @account.contacts.where("custom_attributes->>'cpf' = ?", cpf).first if cpf.present?
      contact ||= @account.contacts.find_by(phone_number: "+55#{phone}") if phone.present?
      contact ||= @account.contacts.find_by(email: email) if email.present?

      unless contact
        unless config.allow_new_patients
          render json: { error: 'Apenas pacientes já cadastrados podem realizar agendamentos online.' }, status: :forbidden
          return
        end

        contact = @account.contacts.create!(
          name: full_name,
          phone_number: "+55#{phone}",
          email: email,
          custom_attributes: { cpf: cpf }
        )
      end

      observations = patient['observations'].presence ? " Observações: #{patient['observations']}" : ""

      # Criar evento na agenda
      event = @account.agenda_events.create!(
        user_id: @user.id,
        contact_id: contact.id,
        title: "Consulta – #{full_name}",
        description: "Agendamento realizado online. CPF: #{cpf}. Telefone: #{phone}.#{observations}",
        starts_at: starts_at,
        ends_at: ends_at,
        status: 'scheduled',
        event_type: 'consultation',   # Correto para 'Consulta' no frontend
        source: 'public_booking'      # Distingue auto-agendamento do paciente vs criação manual da recepção (filtro de Follow-ups)
      )

      render json: {
        success: true,
        event_id: event.id,
        message: "Agendamento confirmado para #{starts_at.strftime('%d/%m/%Y às %H:%M')}."
      }, status: :created
    end

  rescue ActiveRecord::RecordInvalid => e
    render json: { error: "Erro ao salvar: #{e.record.errors.full_messages.join(', ')}" }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error("[AgendaBooking] Erro: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
    render json: { error: 'Erro interno. Tente novamente em alguns instantes.' }, status: :internal_server_error
  end

  private

  def fetch_user
    @user = User.joins(:beclinic_profile).find_by!(beclinic_user_profiles: { agenda_public_id: params[:public_id] })
    @account = @user.accounts.first
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Profissional não encontrado.' }, status: :not_found
  end

  # Generates available time slots for the given date, respecting all
  # AgendaSetting rules configured by the clinic in the dashboard:
  #   - slot_interval_minutes (15/30/60) — grid step AND event duration.
  #   - week_days[].enabled / start / end — working hours per weekday.
  #   - week_days[].lunchStart / lunchEnd + block_lunch_break — skips lunch.
  #   - holidays (status: 'closed') — returns no slots on holidays.
  #   - exceptions (folgas/exceções) — returns no slots inside the range.
  # Falls back to inbox-level WorkingHour only if AgendaSetting is missing,
  # preserving backwards-compat for accounts that haven't configured it yet.
  DOW_KEYS = %w[sun mon tue wed thu fri sat].freeze

  def calculate_slots(date)
    setting = @account.agenda_setting
    config  = @account.agenda_online_config

    open_str, close_str, lunch_start_str, lunch_end_str = working_window_for(date, setting)
    return [] if open_str.blank? || close_str.blank?
    return [] if blocked_by_holiday?(date, setting)
    return [] if blocked_by_exception?(date, setting)

    slot_interval = (setting&.slot_interval_minutes || 60).to_i
    block_lunch   = setting&.block_lunch_break == true

    slots = []

    Time.use_zone('America/Sao_Paulo') do
      min_lead = config&.min_lead_time_minutes.to_i
      earliest_bookable = Time.zone.now + min_lead.minutes

      open_time  = Time.zone.parse("#{date} #{open_str}")
      close_time = Time.zone.parse("#{date} #{close_str}")
      lunch_start = lunch_start_str.present? ? Time.zone.parse("#{date} #{lunch_start_str}") : nil
      lunch_end   = lunch_end_str.present?   ? Time.zone.parse("#{date} #{lunch_end_str}")   : nil

      current_time = open_time

      # Stop the slot generator only after the LAST possible full-length slot
      # has been considered. Using `<=` here so a slot ending exactly on the
      # close time still gets offered.
      while current_time + slot_interval.minutes <= close_time
        slot_end = current_time + slot_interval.minutes

        if current_time < earliest_bookable
          current_time = slot_end
          next
        end

        if block_lunch && lunch_start && lunch_end &&
           current_time < lunch_end && slot_end > lunch_start
          current_time = slot_end
          next
        end

        has_event = @account.agenda_events
                            .where(user_id: @user.id)
                            .where('starts_at < ? AND ends_at > ?', slot_end, current_time)
                            .exists?

        slots << current_time.strftime('%H:%M') unless has_event

        current_time = slot_end
      end
    end

    slots
  end

  # Returns [open_str, close_str, lunch_start_str, lunch_end_str] for the
  # given date, preferring AgendaSetting.week_days (clinic-managed) over
  # the inbox-level WorkingHour fallback.
  def working_window_for(date, setting)
    if setting&.week_days.is_a?(Array)
      day_id = DOW_KEYS[date.wday]
      day_cfg = setting.week_days.find { |d| d['id'] == day_id }
      if day_cfg
        return [nil, nil, nil, nil] unless day_cfg['enabled']
        return [
          day_cfg['start'],
          day_cfg['end'],
          day_cfg['lunchStart'],
          day_cfg['lunchEnd']
        ]
      end
    end

    wh = @account.working_hours
                 .where(day_of_week: date.wday, closed_all_day: false)
                 .first
    return [nil, nil, nil, nil] unless wh
    return [nil, nil, nil, nil] if wh.open_hour.nil? || wh.close_hour.nil?

    [
      "#{wh.open_hour}:#{format('%02d', wh.open_minutes.to_i)}",
      "#{wh.close_hour}:#{format('%02d', wh.close_minutes.to_i)}",
      nil,
      nil
    ]
  end

  def blocked_by_holiday?(date, setting)
    return false unless setting&.holidays.is_a?(Array)
    day_month = "#{date.day.to_s.rjust(2, '0')}/#{date.month.to_s.rjust(2, '0')}"
    setting.holidays.any? do |h|
      h['status'] == 'closed' && h['date'].to_s.start_with?(day_month)
    end
  end

  def blocked_by_exception?(date, setting)
    return false unless setting&.exceptions.is_a?(Array)
    setting.exceptions.any? do |ex|
      next false if ex['start'].blank? || ex['end'].blank?
      ex_start = (Date.parse(ex['start']) rescue nil)
      ex_end   = (Date.parse(ex['end'])   rescue nil)
      next false unless ex_start && ex_end
      date >= ex_start && date <= ex_end
    end
  end
end
