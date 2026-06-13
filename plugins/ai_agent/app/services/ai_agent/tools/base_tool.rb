# Common parent for all Bea tools. Tools are RubyLLM::Tool subclasses
# so the agent can pick them via function calling. The base swallows
# the per-conversation context (account, contact, state) every tool
# needs but isn't part of the LLM-visible signature.
class AiAgent::Tools::BaseTool < RubyLLM::Tool
  attr_reader :context

  # context is an AiAgent::Tools::Context struct; see chat_service.rb.
  def initialize(context)
    @context = context
    super()
  end

  # Use the short class name (snake_case) as the LLM-facing tool name.
  # RubyLLM's default would produce names like
  # "ai_agent--tools--clinic_info" with double dashes, which Gemini's
  # function-calling chokes on (LLM emits a different name and the
  # lookup `tools[name.to_sym]` returns nil → NoMethodError on call).
  # We force a clean name like `clinic_info`, `book_appointment`, etc.
  def name
    klass = self.class.name.to_s.split('::').last.to_s
    klass.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2')
         .gsub(/([a-z\d])([A-Z])/, '\1_\2')
         .downcase
         .delete_suffix('_tool')
  end

  private

  def account
    context.account
  end

  def conversation_state
    context.conversation_state
  end

  def patient_memory
    context.patient_memory
  end

  def contact_id
    context.contact_id
  end

  # SEC-12 (auditoria 2026-05-18): user que invocou o tool. Hoje só é
  # populado no Pipeline B (internal chat — staff que mencionou @bea).
  # No Pipeline A (paciente no WhatsApp) é nil — sem invocador humano,
  # caller é o LLM em nome do paciente, e tools usam outras checagens
  # (rate limit, sem ações privilegiadas etc).
  def invoking_user
    return nil unless context.respond_to?(:invoking_user)

    context.invoking_user
  end

  # Verifica perm Klivy do invoking_user na conta corrente. Retorna
  # `false` se não há invocador humano (Pipeline A) — tools privilegiadas
  # devem usar `require_invoking_user_permission!` em vez disso.
  def invoking_user_can?(mod, action)
    return false if invoking_user.nil?

    # Admin da conta bypassa (mesmo padrão das policies).
    if defined?(::AccountUser)
      account_user = ::AccountUser.find_by(account_id: account.id, user_id: invoking_user.id)
      return true if account_user&.administrator?
    end

    return false unless invoking_user.respond_to?(:beclinic_can?)

    invoking_user.beclinic_can?(account, mod, action)
  end

  # Resolve the Patient row linked to the active Chatwoot contact.
  # Returns nil when no contact is bound or no Patient model exists yet.
  def current_patient
    return nil if contact_id.blank?
    return nil unless defined?(::Patient)

    ::Patient.active.find_by(account_id: account.id, contact_id: contact_id)
  end

  # Delegam pra fonte única AiAgent::AppointmentsLookup (mesma lógica usada
  # pela injeção determinística do chat_service). Cruza contact_id +
  # patient_id, respeita soft-delete (.kept) e ignora cancelados/no_show.
  def contact_patient_ids
    AiAgent::AppointmentsLookup.contact_patient_ids(account, contact_id)
  end

  def upcoming_appointment_events(patient_id: nil, limit: 5)
    AiAgent::AppointmentsLookup.upcoming(account, contact_id, patient_id: patient_id, limit: limit)
  end

  # Posse do agendamento pelo contato ativo: vínculo direto (contact_id)
  # OU pelo paciente (custom_attributes.patient_id ∈ pacientes do contato).
  # Eventos criados pela tela da Agenda vêm com contact_id nil — sem isso,
  # cancelar/remarcar rejeitariam um agendamento legítimo do paciente.
  def owns_appointment?(event)
    return false if event.nil? || contact_id.blank?
    return true if event.contact_id.present? && event.contact_id == contact_id

    pid = (event.custom_attributes || {})['patient_id'].to_s
    pid.present? && contact_patient_ids.include?(pid)
  end
end
