# Agenda::NotificationTemplateService
#
# Substitui as variáveis de template da mensagem com dados reais do evento.
#
# Variáveis suportadas:
#   {nome_paciente}     → contato.name
#   {nome_clinica}      → account.name
#   {nome_profissional} → agent (user) atribuído ao evento
#   {data_agendada}     → event.starts_at (DD/MM/AAAA)
#   {horario_consulta}  → event.starts_at (HH:MM)
#   {link_confirmacao}  → placeholder (integração futura)
#
# Uso:
#   service = Agenda::NotificationTemplateService.new(event: event, rule: rule)
#   message = service.render
#   # "Olá Gabriel, sua consulta é amanhã às 14:30."

class Agenda::NotificationTemplateService
  def initialize(event:, rule:)
    @event   = event
    @rule    = rule
    @account = event.account
  end

  def render
    template = @rule.message_template.dup
    variables.each do |key, value|
      template.gsub!("{#{key}}", value.to_s)
    end
    template
  end

  private

  def variables
    {
      'nome_paciente'     => patient_name,
      'nome_clinica'      => clinic_name,
      'nome_profissional' => professional_name,
      'data_agendada'     => event_date,
      'horario_consulta'  => event_time,
      'link_confirmacao'  => confirmation_link,
    }
  end

  def patient_name
    @event.contact&.name ||
      @event.custom_attributes&.dig('patient_name') ||
      'Paciente'
  end

  def clinic_name
    @account.name
  end

  def professional_name
    @event.user&.name || 'Profissional'
  end

  def event_date
    return '' unless @event.starts_at

    @event.starts_at.in_time_zone(account_timezone).strftime('%d/%m/%Y')
  end

  def event_time
    return '' unless @event.starts_at

    @event.starts_at.in_time_zone(account_timezone).strftime('%H:%M')
  end

  def confirmation_link
    # Placeholder — pode ser integrado com um sistema de confirmação futuro
    "https://#{ENV.fetch('FRONTEND_URL', 'beclinic.com.br')}/confirmar/#{confirmation_token}"
  end

  def confirmation_token
    # Token simples baseado no event id para confirmação futura
    Base64.urlsafe_encode64("#{@event.id}:#{@event.starts_at&.to_i}", padding: false)
  end

  def account_timezone
    # Usa timezone do Rails (configurável por conta futuramente)
    'America/Sao_Paulo'
  end
end
