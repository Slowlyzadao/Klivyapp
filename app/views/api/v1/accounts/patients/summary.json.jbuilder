# Endpoint Estrela — payload consolidado do prontuário
# GET /api/v1/accounts/:account_id/patients/:id/summary
# GET /api/v1/accounts/:account_id/patients/by_contact?contact_id=X

json.payload do
  # Dados básicos do paciente
  json.partial! 'api/v1/accounts/patients/patient', patient: @patient

  # Informações demográficas extras
  json.rg             @patient.rg
  json.billing_info   @patient.billing_info
  json.contact_preferences @patient.contact_preferences
  json.communication_opt_ins @patient.communication_opt_ins
  json.lgpd_consent   @patient.lgpd_consent
  json.contacts       @patient.contacts

  # Último agendamento
  json.last_appointment do
    if @last_appointment
      json.id         @last_appointment.id
      json.title      @last_appointment.title
      json.start_time @last_appointment.starts_at&.iso8601
      json.end_time   @last_appointment.ends_at&.iso8601
      json.status     @last_appointment.status
    end
  end

  # Próximo agendamento
  json.next_appointment do
    if @next_appointment
      json.id         @next_appointment.id
      json.title      @next_appointment.title
      json.start_time @next_appointment.starts_at&.iso8601
      json.end_time   @next_appointment.ends_at&.iso8601
      json.status     @next_appointment.status
    end
  end

  # Resumo clínico — da anamnese mais recente finalizada (ou a mais recente)
  latest_anamnesis = @patient.anamneses
                             .where(deleted_at: nil)
                             .order(finalized_at: :desc, created_at: :desc)
                             .first

  json.clinical_summary do
    if latest_anamnesis
      # Alergias: array de {name:}
      allergies_list = Array(latest_anamnesis.allergies).filter_map { |a| a.is_a?(Hash) ? a['name'] : a.to_s }.reject(&:blank?)
      json.allergies allergies_list

      # Medicamentos em uso: array de {name:}
      meds_list = Array(latest_anamnesis.current_medications).filter_map { |m| m.is_a?(Hash) ? m['name'] : m.to_s }.reject(&:blank?)
      json.current_medications meds_list

      # Histórico médico: hash com boolean flags
      medical_history = latest_anamnesis.medical_history || {}
      json.conditions do
        json.diabetes       medical_history['diabetes'].present? && medical_history['diabetes']
        json.hypertension   medical_history['hypertension'].present? && medical_history['hypertension']
        json.oncology       medical_history['oncology'].present? && medical_history['oncology']
        json.hepatitis      medical_history['hepatitis'].present? && medical_history['hepatitis']
        json.has_implants   medical_history['has_implants'].present? && medical_history['has_implants']
        json.bleeding_disorder medical_history['bleeding_disorder'].present? && medical_history['bleeding_disorder']
        json.pregnant       medical_history['pregnant'].present? && medical_history['pregnant']
        json.other          medical_history['other'].presence
      end

      # Contraindicações: array ou texto
      ci = latest_anamnesis.contraindications
      ci_list = ci.is_a?(Array) ? ci.filter_map { |c| c.is_a?(Hash) ? c['name'] : c.to_s }.reject(&:blank?) : [ci.to_s].reject(&:blank?)
      json.contraindications ci_list
    else
      json.allergies []
      json.current_medications []
      json.conditions do
        json.diabetes false; json.hypertension false; json.oncology false
        json.hepatitis false; json.has_implants false; json.bleeding_disorder false
        json.pregnant false; json.other nil
      end
      json.contraindications []
    end
  end

  # Resumo financeiro real
  transactions = @patient.transactions.where(deleted_at: nil)
  estimates    = @patient.financial_estimates.where(deleted_at: nil, status: 'aprovado')

  total_approved = estimates.sum { |e| e.total.to_f }
  total_paid     = transactions.where(status: 'pago').sum { |t| t.amount.to_f }
  total_open     = transactions.where(status: 'pendente').where('due_date >= ? OR due_date IS NULL', Date.today).sum { |t| t.amount.to_f }
  total_overdue  = transactions.where(status: 'pendente').where('due_date < ?', Date.today).sum { |t| t.amount.to_f }
  credit_balance = transactions.where(status: 'credito').sum { |t| t.amount.to_f }

  json.financial_status do
    json.total_approved total_approved
    json.total_paid     total_paid
    json.total_open     total_open
    json.total_overdue  total_overdue
    json.credit_balance credit_balance
  end

  # Consentimentos pendentes
  json.urgent_consent_required @urgent_consents.any?
  json.pending_consents_count  @urgent_consents.size
end
