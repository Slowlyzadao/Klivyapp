# Notifica equipe financeira quando RefundRequest detector pega menção a
# estorno/reembolso/contestação. Bea continua a conversa normalmente —
# esse alerta só dá visibilidade pra alguém checar a situação fiscal.
#
# Dedupe por janela de 1h: paciente pode mencionar estorno várias vezes
# na mesma conversa (insistir, esclarecer); equipe recebe 1 alerta/hora.
class AiAgent::InternalNotifier::RefundRequestAlert
  EVENT_KEY = 'patient_refund_request'.freeze

  def self.call(account:, conversation:, contact:, terms:, summary:)
    new(account, conversation, contact, terms, summary).call
  end

  def initialize(account, conversation, contact, terms, summary)
    @account = account
    @conversation = conversation
    @contact = contact
    @terms = Array(terms)
    @summary = summary.to_s
  end

  def call
    AiAgent::InternalNotifier::Dispatcher.dispatch(
      account: @account,
      event_key: EVENT_KEY,
      vars: build_vars,
      dedupe_key: "#{EVENT_KEY}:#{@conversation&.id || @contact&.id}:#{Time.current.to_i / 3600}"
    )
  end

  private

  def build_vars
    {
      patient_name: @contact&.name || 'Paciente sem nome',
      patient_phone: @contact&.phone_number || 'sem telefone',
      summary: @summary[0, 200],
      conversation_link: conversation_link
    }
  end

  def conversation_link
    return '' unless @conversation

    "/app/accounts/#{@account.id}/conversations/#{@conversation.display_id || @conversation.id}"
  end
end
