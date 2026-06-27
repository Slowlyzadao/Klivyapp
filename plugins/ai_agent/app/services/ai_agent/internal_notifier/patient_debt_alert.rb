# Notifica equipe financeira quando paciente com débito aberto consegue
# marcar agendamento via Bea. Roda APÓS o booking (não bloqueia) — equipe
# decide o que fazer (cobrar antes da consulta, autorizar, etc.).
#
# Plugado no `BookAppointmentToolPrepend` quando `result[:booked] == true`.
# Dedupe: 1 alerta por paciente por dia (evita spam se Bea fizer 2+
# agendamentos no mesmo dia pra mesmo paciente).
class AiAgent::InternalNotifier::PatientDebtAlert
  EVENT_KEY = 'patient_with_debt_booking'.freeze

  def self.call(account:, contact_id:, debt_result:)
    new(account, contact_id, debt_result).call
  end

  def initialize(account, contact_id, debt_result)
    @account = account
    @contact_id = contact_id
    @debt = debt_result
  end

  def call
    return unless @debt&.has_debt

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

  def build_vars(contact)
    patient = defined?(::Patient) ? ::Patient.find_by(contact_id: contact.id, account_id: @account.id) : nil
    {
      patient_name: patient&.name || contact.name || 'Paciente',
      patient_phone: patient&.phone.presence || contact.phone_number || 'sem telefone',
      debt_amount: format_amount(@debt.total_cents),
      debt_summary: @debt.summary.to_s
    }
  end

  def format_amount(cents)
    "R$ #{format('%.2f', cents.to_f / 100).tr('.', ',')}"
  end
end
