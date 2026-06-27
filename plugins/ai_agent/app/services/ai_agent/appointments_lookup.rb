# Fonte ÚNICA da busca de agendamentos futuros de um contato.
#
# Cruza contact_id E custom_attributes.patient_id porque os eventos criados
# pela tela "Novo Evento" da Agenda vêm com contact_id NULO (vínculo do
# paciente só em custom_attributes.patient_id). Respeita o soft-delete
# (`AgendaEvent.kept` → deleted_at IS NULL) e ignora cancelados/no_show.
#
# Usado por:
#   - tools (find_patient_by_phone / list_appointments via BaseTool);
#   - chat_service (injeção DETERMINÍSTICA no contexto do turno, pra a Bea
#     reconhecer e mencionar a consulta MESMO quando o LLM não chama a tool).
module AiAgent::AppointmentsLookup
  module_function

  # IDs (string) dos Patients ligados ao contato — por vínculo direto
  # (contact_id) OU pelo telefone (suffix-match de 8 dígitos).
  def contact_patient_ids(account, contact_id)
    return [] if contact_id.blank? || !defined?(::Patient)

    contact = ::Contact.find_by(id: contact_id, account_id: account.id)
    digits = contact&.phone_number.to_s.gsub(/\D/, '')
    suffix = digits.length >= 8 ? digits.last(8) : digits
    rel = ::Patient.where(account_id: account.id)
    rel = if suffix.present?
            rel.where("contact_id = ? OR REGEXP_REPLACE(COALESCE(phone, ''), '\\D', '', 'g') LIKE ?", contact_id, "%#{suffix}")
          else
            rel.where(contact_id: contact_id)
          end
    rel.pluck(:id).map(&:to_s)
  end

  # AgendaEvents futuros (kept, não cancelados) do contato. Filtra por
  # patient_id quando passado (dependente); senão cruza contact_id + pacientes.
  def upcoming(account, contact_id, patient_id: nil, limit: 5)
    return [] if contact_id.blank? || !defined?(::AgendaEvent)

    scope = ::AgendaEvent.kept
                         .where(account_id: account.id)
                         .where.not(status: %w[cancelled no_show])
                         .where('starts_at >= ?', Time.current)
                         .order(:starts_at)
    scope = if patient_id.present?
              scope.where("custom_attributes->>'patient_id' = ?", patient_id.to_s)
            else
              pids = contact_patient_ids(account, contact_id)
              if pids.any?
                scope.where("agenda_events.contact_id = :cid OR custom_attributes->>'patient_id' IN (:pids)", cid: contact_id, pids: pids)
              else
                scope.where(contact_id: contact_id)
              end
            end
    scope.limit(limit).to_a
  end
end
