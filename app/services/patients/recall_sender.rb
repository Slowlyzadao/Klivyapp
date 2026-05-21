# app/services/patients/recall_sender.rb
#
# Serviço que monta e "dispara" o payload de recall via WhatsApp.
# Não se conecta diretamente ao gateway — devolve o payload estruturado
# para o gateway existente do Chatwoot processar, mantendo o padrão do projeto.

module Patients
  class RecallSender
    Result = Struct.new(:success?, :payload, :error, keyword_init: true)

    def self.call(patient:, actor:, account:, message_override: nil)
      new(patient: patient, actor: actor, account: account, message_override: message_override).call
    end

    def initialize(patient:, actor:, account:, message_override: nil)
      @patient          = patient
      @actor            = actor
      @account          = account
      @message_override = message_override
    end

    def call
      phone = resolve_phone
      return Result.new(success?: false, payload: nil, error: 'Paciente sem número de telefone/WhatsApp cadastrado') unless phone

      message = build_message

      # Marca o recall como enviado no paciente
      patient.update(needs_recall: false)

      # Registra o recall no event de timeline
      dispatch_timeline_event

      payload = {
        phone: phone,
        whatsapp_message: message,
        patient_id: patient.id,
        patient_name: patient.name,
        note: 'Recall de retorno — use o gateway WhatsApp da BeClinic para completar o envio'
      }

      Result.new(success?: true, payload: payload, error: nil)
    rescue StandardError => e
      Rails.logger.error("[RecallSender] Erro ao preparar recall para paciente #{patient.id}: #{e.message}")
      Result.new(success?: false, payload: nil, error: e.message)
    end

    private

    attr_reader :patient, :actor, :account, :message_override

    def resolve_phone
      # Prioridade: whatsapp > phone do cadastro > contato linkado
      patient.whatsapp.presence ||
        patient.phone.presence ||
        patient.contacts&.first&.dig('value')
    end

    def build_message
      return message_override if message_override.present?

      last_appointment = patient.patient_appointments
                                .active
                                .done
                                .order(scheduled_at: :desc)
                                .first

      last_visit_text = last_appointment&.scheduled_at&.strftime('%d/%m/%Y')

      lines = [
        "Olá, #{patient.name}! 👋",
        '',
        "Percebemos que faz um tempo desde sua última visita à #{account.name}.",
        (last_visit_text ? "📅 Sua última consulta foi em #{last_visit_text}." : nil),
        '',
        'Gostaríamos de agendar seu retorno para darmos continuidade ao seu tratamento.',
        'Entre em contato conosco ou responda esta mensagem! 😊'
      ].compact

      lines.join("\n")
    end

    def dispatch_timeline_event
      Patients::RecordTimelineEventJob.perform_later(
        patient_id: patient.id,
        account_id: account.id,
        actor_id: actor.id,
        event_type: 'recall_sent',
        label: 'Lembrete de retorno enviado via WhatsApp',
        reference_type: 'Patient',
        reference_id: patient.id,
        metadata: { sent_by: actor.name }
      )
    end
  end
end
