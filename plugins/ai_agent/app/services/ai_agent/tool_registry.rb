module AiAgent
  # Resolves tool keys (strings stored in AiAgent::ToolDefinition.key and in
  # the per-account whitelist) to actual Ruby classes that the chat service
  # can instantiate. New tools are added here in one place.
  module ToolRegistry
    BUILTIN = {
      'search_knowledge'    => 'AiAgent::Tools::SearchKnowledgeTool',
      'transfer_to_human'   => 'AiAgent::Tools::TransferToHumanTool',
      'patient_lookup'      => 'AiAgent::Tools::PatientLookupTool',
      'list_appointments'   => 'AiAgent::Tools::ListAppointmentsTool',
      'financial_status'    => 'AiAgent::Tools::FinancialStatusTool',
      'notify_staff'        => 'AiAgent::Tools::NotifyStaffTool',
      'clinic_info'             => 'AiAgent::Tools::ClinicInfoTool',
      'book_appointment'        => 'AiAgent::Tools::BookAppointmentTool',
      'search_available_slots'  => 'AiAgent::Tools::SearchAvailableSlotsTool',
      'reschedule_appointment'  => 'AiAgent::Tools::RescheduleAppointmentTool',
      'cancel_appointment'      => 'AiAgent::Tools::CancelAppointmentTool',
      'erasure_request'         => 'AiAgent::Tools::ErasureRequestTool',
      'find_patient_by_phone'   => 'AiAgent::Tools::FindPatientByPhoneTool',
      'confirm_patient_identity' => 'AiAgent::Tools::ConfirmPatientIdentityTool',
      'create_patient_minimal'  => 'AiAgent::Tools::CreatePatientMinimalTool'
    }.freeze

    def self.lookup(keys)
      Array(keys).filter_map { |k| BUILTIN[k.to_s]&.constantize }
    end

    def self.all_classes
      BUILTIN.values.map(&:constantize)
    end

    def self.all_keys
      BUILTIN.keys
    end
  end
end
