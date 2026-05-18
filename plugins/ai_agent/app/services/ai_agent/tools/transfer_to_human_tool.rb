module AiAgent
  module Tools
    # Hand-off lever. The agent calls this when the user explicitly asks for
    # a human, when sentiment is too negative, or when a high-stakes topic
    # comes up that the agent shouldn't try to resolve alone (formal
    # complaint, refund request, medical concern).
    #
    # The hard wiring with Chatwoot's AgentBot (un-assign bot, assign human,
    # post note) lives in Phase 4. For now we mark the conversation state as
    # escalated and append a memory entry — that's enough for the LLM loop
    # to stop trying.
    class TransferToHumanTool < BaseTool
      description <<~DESC
        Transfere a conversa para um atendente humano. Use quando: o paciente
        pedir explicitamente, demonstrar frustração persistente, ou tocar em
        tema sensível (reclamação formal, reembolso, queixa médica).
      DESC

      param :reason,
            type: :string,
            desc: 'Motivo curto da transferência (ex.: "paciente pediu humano", "reclamação de reembolso", "frustração").'

      param :urgency,
            type: :string,
            desc: 'Urgência percebida: low, normal ou high.',
            required: false

      def execute(reason:, urgency: 'normal')
        conversation_state.escalate!(reason: reason)

        # Find a Chatwoot conversation row and assign a human agent so the
        # transfer is real, not just a state flag. Picks the first
        # administrator/agent of the account that has availability "online";
        # falls back to any administrator if no one is online.
        assigned_user = nil
        conversation = ::Conversation.find_by(id: conversation_state.conversation_id)
        if conversation
          available_agents = account.administrators.where(availability: 'online').to_a
          available_agents = account.administrators.to_a if available_agents.empty?
          assigned_user = available_agents.first

          if assigned_user
            conversation.update(assignee_id: assigned_user.id)
            conversation.messages.create!(
              account_id: account.id,
              inbox_id: conversation.inbox_id,
              message_type: :outgoing,
              private: true,
              sender: AiAgent::AgentBotIdentity.ensure!,
              content: "🤖 Bea transferiu para você. Motivo: #{reason}. Urgência: #{urgency}."
            )
          end
        end

        if patient_memory
          patient_memory.append_history(
            event_type: 'escalated_to_human',
            summary: reason,
            metadata: { urgency: urgency, assigned_user_id: assigned_user&.id }
          )
        end

        {
          handoff: true,
          reason: reason,
          urgency: urgency,
          assigned_user_id: assigned_user&.id,
          assigned_user_name: assigned_user&.name,
          message_for_user: 'Vou transferir você para um atendente agora.'
        }
      end
    end
  end
end
