# Returns the clinic's operational info pulled from AgendaSetting +
# AgendaService — horários de funcionamento, serviços oferecidos,
# regras (block_outside_working_hours, slot_interval). Bea uses this
# to answer questions like "que horas vocês abrem?", "quais serviços
# vocês fazem?", "quanto custa X?".
#
# No RAG / embeddings — direct AR query.
class AiAgent::Tools::ClinicInfoTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Retorna as informações operacionais da clínica: horário de
    funcionamento por dia da semana, exceções/feriados, lista de
    serviços oferecidos com duração e preço, e regras gerais. Use
    sempre que o paciente perguntar sobre horários, serviços, valores
    ou disponibilidade da clínica.
  DESC

  def execute
    return { available: false, message: 'Módulo de agenda não disponível.' } unless defined?(::AgendaSetting)

    setting = ::AgendaSetting.find_by(account_id: account.id)
    # Bea SÓ enxerga serviços com pelo menos 1 profissional vinculado.
    # Serviço sem profissional cadastrado é como se não existisse —
    # impede a Bea de oferecer agendamento que ela não conseguiria
    # cumprir. Subquery via `where(id: ...select)` em vez de
    # `joins.distinct` porque User tem colunas json que não suportam
    # DISTINCT com igualdade no Postgres. `includes(:professionals)` evita
    # N+1 ao listar `professionals` depois.
    services = if defined?(::AgendaService) && defined?(::AgendaServiceUser)
                 linked_ids = ::AgendaServiceUser.where(account_id: account.id).select(:agenda_service_id)
                 ::AgendaService.where(account_id: account.id, id: linked_ids)
                                .includes(:professionals)
                                .limit(50)
               else
                 []
               end

    {
      available: true,
      clinic: clinic_address,
      working_hours: format_week_days(setting&.week_days),
      holidays: setting&.holidays || [],
      rules: {
        block_outside_working_hours: setting&.block_outside_working_hours,
        block_lunch_break: setting&.block_lunch_break,
        slot_interval_minutes: setting&.slot_interval_minutes,
        block_past_dates: setting&.block_past_dates
      },
      # Esta lista já foi pré-filtrada — só serviços com pelo menos
      # 1 profissional cadastrado. Logo, `professionals` nunca vem
      # vazio aqui. Se o paciente pedir um serviço que não está
      # nessa lista, ASSUMA que a clínica não oferece (não tente
      # adivinhar pelo nome).
      services: services.map do |s|
        {
          id: s.id,
          name: s.name,
          duration_minutes: s.duration_minutes,
          price: (s.respond_to?(:price) ? s.price.to_f : nil),
          professionals: s.professionals.map { |u| { id: u.id, name: AiAgent::Formatters::ProfessionalName.format(u.name) } }
        }
      end,
      note_for_bea: 'Esta é a LISTA COMPLETA de serviços que a clínica pode realmente agendar (já filtrada — só inclui serviços com profissional cadastrado). Se o paciente pedir algo que NÃO está aqui, a clínica NÃO oferece: diga com leveza que infelizmente não atende esse serviço e LISTE o que a clínica atende (os nomes desta lista). NÃO tente agendar nem transferir por isso.'
    }
  end

  private

  def format_week_days(week_days)
    return [] if week_days.blank?

    # week_days is a jsonb hash like { "monday" => { "open" => "08:00", "close" => "18:00", "closed" => false }, ... }
    # Pass through as-is so the LLM can interpret. Add labels for readability.
    labels = { 'monday' => 'segunda', 'tuesday' => 'terça', 'wednesday' => 'quarta',
               'thursday' => 'quinta', 'friday' => 'sexta', 'saturday' => 'sábado', 'sunday' => 'domingo' }

    week_days.map do |day, info|
      { day: labels[day.to_s] || day, **(info.is_a?(Hash) ? info.symbolize_keys : { value: info }) }
    end
  end

  # Dados da clínica (nome/telefone/endereço) gravados em
  # account.custom_attributes pelo ClinicProfileController ("Dados da
  # clínica"). A Bia usa pra fechar o agendamento: manda o endereço por
  # extenso + um link do Google Maps pronto (evita ela inventar). Retorna
  # nil quando o endereço não foi configurado — aí a Bia NÃO deve chutar.
  def clinic_address
    ca = account.custom_attributes || {}
    street = ca['address_street'].to_s.strip
    city   = ca['address_city'].to_s.strip
    return nil if street.blank? && city.blank?

    number       = ca['address_number'].to_s.strip
    complement   = ca['address_complement'].to_s.strip
    neighborhood = ca['address_neighborhood'].to_s.strip
    state        = ca['address_state'].to_s.strip
    zip          = ca['address_zip'].to_s.strip
    name         = ca['fantasy_name'].to_s.strip

    line = street.dup
    line << ", #{number}"     if number.present?
    line << " (#{complement})" if complement.present?
    city_uf = [city.presence, state.presence].compact.join('/')
    text = [line.presence, neighborhood.presence, city_uf.presence, (zip.present? ? "CEP #{zip}" : nil)].compact.join(' - ')

    query = [name, street, number, neighborhood, city, state, zip].reject(&:blank?).join(', ')
    {
      name: name.presence,
      phone: ca['phone'].to_s.strip.presence,
      address_text: text,
      maps_url: "https://www.google.com/maps/search/?api=1&query=#{CGI.escape(query)}"
    }
  end
end
