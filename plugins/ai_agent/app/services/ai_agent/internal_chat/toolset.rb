module AiAgent
  module InternalChat
    # Toolset enxuto pra Pipeline B. Por design só inclui tools que:
    #   - são read-only (sem mutação)
    #   - NÃO dependem de contact_id (não há paciente vinculado a uma sala
    #     do chat interno)
    #
    # Hoje: apenas `clinic_info`. À medida que houver tools "internas" mais
    # sofisticadas (ex: search_patient_by_name pra "@bea Maria Silva tem
    # consulta marcada?"), adicionar aqui.
    #
    # Excluídos por design: book_appointment / reschedule / cancel
    # (ações sensíveis exigem UI da clínica), transfer_to_human / notify_staff
    # (já está no chat com staff), patient_lookup (depende de contact_id).
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
    module Toolset
      ENABLED_TOOL_CLASSES = [
        ::AiAgent::Tools::ClinicInfoTool,
        ::AiAgent::Tools::InternalSearchPatientTool,
        ::AiAgent::Tools::InternalListPatientAppointmentsTool,
        ::AiAgent::Tools::InternalBookAppointmentTool,
        ::AiAgent::Tools::InternalRescheduleAppointmentTool,
        ::AiAgent::Tools::InternalCancelAppointmentTool
      ].freeze

      # Context simplificado pra inicializar tools sem patient_memory /
      # conversation_state. Tools que tentarem acessar esses campos via
      # `context.patient_memory` recebem nil — comportamento aceitável pra
      # tools read-only nesta lista.
      InternalContext = Struct.new(:account, :contact_id, :conversation_state, :patient_memory, keyword_init: true)

      def self.tools_for(account)
        ctx = InternalContext.new(
          account: account,
          contact_id: nil,
          conversation_state: nil,
          patient_memory: nil
        )
        ENABLED_TOOL_CLASSES.map { |klass| klass.new(ctx) }
      end
    end
  end
end
