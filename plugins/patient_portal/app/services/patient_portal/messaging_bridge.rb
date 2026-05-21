# Ponte entre o portal e o sistema de mensageria do Chatwoot (PRD §12).
#
# Decisão arquitetural: NÃO criamos modelos novos de mensagem. Reusamos
# `Inbox` + `Conversation` + `Message` do core (que já tem assignee, sidebar
# omnichannel, métricas, notificações pro atendente, etc.). O portal é apenas
# mais um canal — tipo `Channel::Api` — que entrega mensagens.
#
# Estratégia:
#   1. Há UM `Inbox` por Account dedicado ao portal — channel_type='Channel::Api',
#      identificável via `additional_attributes['source']='patient_portal'`.
#   2. Cada paciente tem 1 `Conversation` aberta por vez (lock_to_single_conversation).
#   3. Mensagens do paciente: message_type=:incoming, sender=patient.contact.
#   4. Mensagens da clínica respondidas no painel Chatwoot: message_type=:outgoing,
#      sender=User (recepcionista) — viram visíveis automaticamente pro portal.
module PatientPortal
  class MessagingBridge
    INBOX_NAME      = 'Portal do Paciente'.freeze
    INBOX_SOURCE    = 'patient_portal'.freeze

    def initialize(account:, patient:)
      @account = account
      @patient = patient
    end

    # Garante que o Inbox de portal existe na account, criando se faltar.
    def inbox
      @inbox ||= find_or_create_portal_inbox
    end

    # Garante que o paciente tem um Contact (via patient.contact_id) e que
    # esse contact está linkado ao inbox via ContactInbox.
    def contact_inbox
      @contact_inbox ||= ensure_contact_inbox
    end

    # Conversa ativa (open|pending) do paciente neste inbox. Cria nova se
    # nenhuma estiver aberta.
    def conversation
      @conversation ||= find_or_create_open_conversation
    end

    # Envia mensagem do paciente. Retorna o Message criado.
    def send_message!(content:, urgent: false)
      msg = Message.create!(
        account_id:      @account.id,
        inbox_id:        inbox.id,
        conversation_id: conversation.id,
        sender:          @patient.contact,
        message_type:    :incoming,
        content:         content.to_s,
        additional_attributes: { source: 'patient_portal', urgent: urgent ? true : nil }.compact
      )

      # Re-abre a conversa se estava resolvida
      conversation.update!(status: :open) if conversation.resolved?

      msg
    rescue StandardError => e
      Rails.logger.error("[MessagingBridge] send_message falhou: #{e.message}")
      raise
    end

    # Mensagens da conversa atual, ordenadas cronologicamente, paginadas.
    def messages(limit: 50)
      return [] unless @patient.contact_id.present?

      conversation.messages
                  .where.not(message_type: :activity) # esconde events de sistema
                  .order(created_at: :asc)
                  .last(limit)
    end

    private

    def find_or_create_portal_inbox
      inbox = Inbox.where(account_id: @account.id, channel_type: 'Channel::Api')
                   .find { |i| i.channel&.additional_attributes&.dig('source') == INBOX_SOURCE }
      return inbox if inbox

      channel = Channel::Api.create!(
        account_id: @account.id,
        webhook_url: nil,
        hmac_mandatory: false,
        additional_attributes: { 'source' => INBOX_SOURCE }
      )
      Inbox.create!(
        account_id:   @account.id,
        channel:      channel,
        name:         INBOX_NAME,
        greeting_enabled: false,
        sender_name_type: 'professional'
      )
    end

    def ensure_contact_inbox
      raise 'Paciente sem contact_id — vincule um Contact antes de mensagear.' if @patient.contact_id.blank?

      ContactInbox.find_or_create_by!(
        contact_id: @patient.contact_id,
        inbox_id:   inbox.id
      ) do |ci|
        # source_id é único por inbox — usamos um derivativo previsível.
        ci.source_id = "portal:#{@patient.id}"
      end
    end

    def find_or_create_open_conversation
      ci = contact_inbox
      existing = Conversation.where(account_id: @account.id, inbox_id: inbox.id,
                                     contact_id: @patient.contact_id)
                              .where(status: [:open, :pending, :snoozed])
                              .order(created_at: :desc).first
      return existing if existing

      Conversation.create!(
        account_id:        @account.id,
        inbox_id:          inbox.id,
        contact_id:        @patient.contact_id,
        contact_inbox_id:  ci.id,
        status:            :open,
        additional_attributes: { 'source' => INBOX_SOURCE, 'patient_id' => @patient.id }
      )
    end
  end
end
