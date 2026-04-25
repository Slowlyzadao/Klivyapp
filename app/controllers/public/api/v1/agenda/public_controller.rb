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

      # Duração do slot
      slot_duration = config&.respond_to?(:slot_duration_minutes) && config.slot_duration_minutes.to_i > 0 ? config.slot_duration_minutes.to_i : 60
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
        event_type: 'consultation'    # Correto para 'Consulta' no frontend
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

  def calculate_slots(date)
    # WorkingHour está associado a um inbox, não diretamente à conta sem inbox
    # Usamos o inbox principal da conta ou qualquer working hour do dia
    working_hour = @account.working_hours
                           .where(day_of_week: date.wday)
                           .where(closed_all_day: false)
                           .first

    return [] unless working_hour
    return [] if working_hour.open_hour.nil? || working_hour.close_hour.nil?

    config   = @account.agenda_online_config
    slots = []

    Time.use_zone('America/Sao_Paulo') do
      min_lead = config&.min_lead_time_minutes.to_i
      earliest_bookable = Time.zone.now + min_lead.minutes

      # Duração do slot em minutos (padrão 60 para bater com a criação)
      slot_duration = config&.respond_to?(:slot_duration_minutes) && config.slot_duration_minutes.to_i > 0 ? config.slot_duration_minutes.to_i : 60

      open_time  = "#{date} #{working_hour.open_hour}:#{format('%02d', working_hour.open_minutes.to_i)}"
      close_time = "#{date} #{working_hour.close_hour}:#{format('%02d', working_hour.close_minutes.to_i)}"

      current_time = Time.zone.parse(open_time)
      end_time     = Time.zone.parse(close_time)

      while current_time < end_time
        slot_end = current_time + slot_duration.minutes

        # Pular horários antes do lead time mínimo
        if current_time < earliest_bookable
          current_time = slot_end
          next
        end

        # Verificar conflito com eventos existentes deste profissional
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
end
