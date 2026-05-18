module AiAgent
  module Tools
    # Confirma que o `patient_id` é de fato o paciente desta conversa e
    # vincula `Patient.contact_id` ao Contact ativo (se ainda não estiver).
    # Use depois que o paciente confirmou textualmente ("sim, sou eu",
    # "isso", "pode ser") na pergunta da Bea — nunca antes.
    #
    # Auto-link retroativo: a partir desta tool, futuras conversas do mesmo
    # contato encontram o paciente direto via patient_lookup, sem precisar
    # buscar por telefone.
    class ConfirmPatientIdentityTool < BaseTool
      description <<~DESC
        Confirma identidade do paciente e vincula a ficha ao Contact desta
        conversa. Use SOMENTE depois que o paciente confirmou textualmente
        que é a pessoa que aparece em find_patient_by_phone.candidates.

        Se o paciente disse explicitamente que NÃO é a pessoa do cadastro
        (ex: "não, sou outra pessoa", "esse celular é da minha mãe"), NÃO
        chame esta tool — chame transfer_to_human pra recepção resolver.

        Após sucesso, prossiga normalmente pra clinic_info /
        search_available_slots / book_appointment.
      DESC

      param :patient_id,
            type: :integer,
            desc: 'ID do paciente que o usuário confirmou ser. Use um dos IDs retornados em candidates por find_patient_by_phone.'

      def execute(patient_id:)
        return { confirmed: false, error: 'Sem contato vinculado a esta conversa.' } if contact_id.blank?

        patient = ::Patient.active.find_by(id: patient_id, account_id: account.id)
        return { confirmed: false, error: "Paciente #{patient_id} não encontrado nesta clínica." } if patient.nil?

        # Bloqueio defensivo: se o Patient já está vinculado a OUTRO contato
        # do Chatwoot, não sobrescreve sozinho — recepção precisa decidir
        # se é troca de número ou cadastro errado.
        if patient.contact_id.present? && patient.contact_id != contact_id
          return {
            confirmed: false,
            error: 'Esse paciente está vinculado a outro contato no sistema.',
            note_for_bea: 'Esse paciente já está com outro WhatsApp cadastrado. Chame transfer_to_human pra recepção verificar.'
          }
        end

        already_linked = patient.contact_id == contact_id
        patient.update!(contact_id: contact_id) unless already_linked

        {
          confirmed: true,
          newly_linked: !already_linked,
          patient: {
            id: patient.id,
            name: patient.try(:full_name) || patient.name,
            status: patient.patient_status
          },
          note_for_bea: already_linked ?
            'Paciente já estava vinculado. Pode seguir pro agendamento.' :
            'Vinculei a ficha ao WhatsApp deste paciente. Pode seguir pro agendamento.'
        }
      rescue ActiveRecord::RecordInvalid => e
        { confirmed: false, error: e.message }
      end
    end
  end
end
