# Fase 2: renderiza a mensagem FIXA de um follow-up estático, interpolando
# variáveis `{{nome}}`, `{{data}}`, `{{hora}}`, `{{profissional}}`,
# `{{clinica}}` a partir do contexto disponível. SEM LLM — é só
# substituição de string, custo zero e 100% previsível.
#
# Variáveis sem valor (ex: `{{data}}` num follow-up sem consulta) viram
# string vazia, nunca o literal `{{data}}` — não vaza placeholder pro
# paciente. Tokens desconhecidos também são removidos.
class AiAgent::FollowUps::StaticRenderer
  TZ = 'America/Sao_Paulo'.freeze
  TOKEN = /\{\{\s*(\w+)\s*\}\}/

  def self.call(...)
    new(...).call
  end

  def initialize(body:, contact: nil, agenda_event: nil, account: nil)
    @body = body.to_s
    @contact = contact
    @agenda_event = agenda_event
    @account = account
  end

  def call
    rendered = @body.gsub(TOKEN) { vars[Regexp.last_match(1).downcase] || '' }
    rendered.strip
  end

  private

  def vars
    @vars ||= {
      'nome' => contact_name,
      'data' => event_at&.strftime('%d/%m'),
      'hora' => event_at&.strftime('%H:%M'),
      'profissional' => professional_name,
      'clinica' => clinic_name
    }
  end

  def contact_name
    @contact&.name.to_s.strip
  end

  def professional_name
    @agenda_event&.user&.name.to_s.strip.presence
  end

  def clinic_name
    @account&.name.to_s.strip.presence
  end

  def event_at
    @agenda_event&.starts_at&.in_time_zone(TZ)
  end
end
