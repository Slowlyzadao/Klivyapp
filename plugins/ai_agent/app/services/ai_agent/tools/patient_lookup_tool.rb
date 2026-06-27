# Resolves the Patient record (from plugins/patients) linked to the
# current Chatwoot contact. Use this to ground replies in the patient's
# actual record — name, status, critical alerts, responsible professional.
class AiAgent::Tools::PatientLookupTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Busca dados do paciente atual (a pessoa que está nesta conversa) no
    prontuário da clínica. Use quando precisar confirmar nome, status,
    alergias declaradas, profissional responsável ou outros dados do
    paciente para personalizar a resposta.
  DESC

  def execute
    patient = current_patient
    return { found: false, message: 'Paciente não encontrado no prontuário.' } if patient.nil?

    {
      found: true,
      patient: {
        id: patient.id,
        name: patient.try(:full_name) || patient.try(:name),
        status: patient.patient_status,
        sex: patient.sex,
        responsible_professional: patient.try(:responsible_professional)&.name,
        critical_alerts: patient.respond_to?(:critical_alerts) ? patient.critical_alerts.limit(5).pluck(:title) : []
      }
    }
  end
end
