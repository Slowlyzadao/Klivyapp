# Dispara quando BookAppointmentTool retorna `{ booked: false }` por uma
# razão NÃO-trivial — Bea tentou agendar pro paciente e ficou bloqueada.
# Equipe precisa saber pra eventualmente intervir manualmente.
#
# NÃO notifica pra:
#   - duplicate (não é falha — Bea acertou em não duplicar)
#   - sem contact (problema de config, não de negócio)
#   - módulo de agenda indisponível (problema de infra)
#   - data no passado (provável erro do LLM, não bloqueio real)
#   - duração inválida (idem)
#
# Notifica pra:
#   - profissional não realiza esse serviço
#   - patient_id não bate com contact (raro, mas é sinal que LLM se confundiu)
#   - outros bloqueios de negócio
#
# Dedupe por contact + dia: máximo 1 alerta de booking_failed por paciente
# por dia (evita spam se LLM ficar tentando seguidamente).
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F)
class AiAgent::InternalNotifier::AppointmentBookingFailed
  EVENT_KEY = 'appointment_booking_failed'.freeze

  INFRA_ERRORS = [
    /M[oó]dulo de agenda/i,
    /Paciente n[aã]o vinculado/i,
    %r{Data/hora inv[aá]lida}i,
    /n[aã]o posso agendar no passado/i,
    /Dura[cç][aã]o inv[aá]lida/i
  ].freeze

  def self.call(account:, contact_id:, result:)
    new(account, contact_id, result).call
  end

  def initialize(account, contact_id, result)
    @account = account
    @contact_id = contact_id
    @result = result || {}
  end

  def call
    return unless notifiable?

    contact = ::Contact.find_by(id: @contact_id, account_id: @account.id)
    return unless contact

    AiAgent::InternalNotifier::Dispatcher.dispatch(
      account: @account,
      event_key: EVENT_KEY,
      vars: build_vars(contact),
      dedupe_key: "#{EVENT_KEY}:#{@contact_id}:#{Date.current}"
    )
  end

  private

  def notifiable?
    return false if @result[:booked] || @result['booked']
    return false if @result[:duplicate] || @result['duplicate']
    return false if @contact_id.blank?

    error_text = (@result[:error] || @result['error']).to_s
    return false if error_text.blank?
    return false if INFRA_ERRORS.any? { |re| re.match?(error_text) }

    true
  end

  def build_vars(contact)
    patient = defined?(::Patient) ? ::Patient.find_by(contact_id: contact.id, account_id: @account.id) : nil
    {
      patient_name: patient&.name || contact.name || 'Paciente',
      patient_phone: patient&.phone.presence || contact.phone_number || 'sem telefone',
      reason: (@result[:error] || @result['error']).to_s.strip[0, 300]
    }
  end
end
