module AiAgent
  module Tools
    # Posts a private note on the conversation flagging staff. Used when:
    #   - the patient mentioned something the receptionist should know
    #     ("vou chegar atrasado", "estou com dor forte")
    #   - Bea solved the request but staff needs a heads-up
    # The note is not visible to the patient and not part of Bea's reply.
    class NotifyStaffTool < BaseTool
      description <<~DESC
        Cria uma nota interna (não visível ao paciente) na conversa atual
        avisando a equipe sobre algo relevante. Use quando o paciente
        mencionar informação operacional importante (atraso, sintoma,
        urgência, troca de contato) que precisa estar registrada para a
        recepção sem interromper a conversa com ele.
      DESC

      param :note,
            type: :string,
            desc: 'O texto da nota interna (curto e objetivo, em português).'

      param :priority,
            type: :string,
            desc: 'Prioridade percebida: low, normal ou high.',
            required: false

      def execute(note:, priority: 'normal')
        state = conversation_state
        return { posted: false, error: 'no conversation state' } if state.nil?

        conversation = ::Conversation.find_by(id: state.conversation_id, account_id: account.id)
        return { posted: false, error: 'conversation not found' } if conversation.nil?

        prefix = priority == 'high' ? '🔴 [Bea — atenção] ' : 'ℹ️ [Bea] '

        message = conversation.messages.create!(
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          sender: AiAgent::AgentBotIdentity.ensure!,
          private: true,
          content: "#{prefix}#{note}"
        )

        if patient_memory
          patient_memory.append_history(
            event_type: 'staff_notified',
            summary: note,
            metadata: { priority: priority }
          )
        end

        { posted: true, message_id: message.id, priority: priority }
      end
    end
  end
end
