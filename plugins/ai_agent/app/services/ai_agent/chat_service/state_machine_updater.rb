# Lê o resultado da tool (Hash) e atualiza o `ctx_state` (pending_offer,
# last_completed, active_service, active_patient). Pure function —
# recebe ctx_state, key da tool e o result, devolve nada. Sem state
# interno, sem dependência de @account ou @contact_id.
#
# Extraído de `AiAgent::ChatService.record_state_from_result`
# (Fase 4 / BE-1) pra reduzir tamanho do orquestrador. O ChatService
# mantém um alias `self.record_state_from_result` delegando pra cá
# por compat com qualquer caller externo eventual.
class AiAgent::ChatService::StateMachineUpdater
  def self.record(ctx_state, key, result)
    return unless result.is_a?(Hash)

    case key
    when 'list_appointments'
      # Se a tool retornou EXATAMENTE 1 agendamento, marca como
      # candidato de remarcação. Se vierem múltiplos, deixa o LLM
      # perguntar qual antes de oferecer slot novo.
      appts = result[:appointments]
      if appts.is_a?(Array) && appts.size == 1
        ctx_state.remember_listed_appointment!(appts.first[:id])
      elsif appts.is_a?(Array) && appts.size > 1
        # 2+ consultas = não sabemos QUAL o paciente quer mexer. Marca como
        # AMBÍGUO: o "Sim" determinístico fica proibido (caso real: criou um
        # 3º agendamento às 09:00 em vez de remarcar a consulta discutida).
        ctx_state.remember_ambiguous_listing!
      end
    when 'search_available_slots'
      # Marca active_service mesmo que a busca venha vazia — o
      # paciente está no fluxo desse serviço, e turnos ambíguos
      # subsequentes ("agende pra depois de amanhã") devem continuar
      # nele, não saltar pra outro.
      if result.dig(:service, :id) && result.dig(:service, :name)
        ctx_state.set_active_service!(id: result[:service][:id], name: result[:service][:name], period: result[:period_requested])
      end

      return unless result[:available] && result[:slots].is_a?(Array) && result[:slots].any?

      # Slot PRIMÁRIO da oferta: se a busca foi por um horário específico
      # (requested_time) e ele voltou na lista, a oferta é ESSE slot — não o
      # primeiro da lista. Caso real: paciente pediu 15h, slots vieram
      # [09h, 15h, 17h], o "Sim" bookou 09h.
      requested = result[:requested_time].to_s
      first = nil
      if requested.present?
        first = result[:slots].find { |s| s[:time].to_s == requested }
      end
      first ||= result[:slots].first
      first_pro = (first[:available_with] || []).first
      # Captura TODOS os slots oferecidos como `alternatives` pra que
      # o pré-LLM matcher consiga disparar book direto quando o
      # paciente mencionar um horário específico ("Podemos as 11h?").
      # Sem isso, só "Sim" plain dispara — qualquer outra forma de
      # aceite força o LLM a decidir e ele às vezes alucina
      # "esse horário acabou de ser preenchido".
      alternatives = result[:slots].map do |slot|
        pro = (slot[:available_with] || []).first
        {
          'starts_at' => slot[:starts_at],
          'user_id' => pro&.dig(:id),
          'professional_name' => pro&.dig(:name),
          'time' => slot[:time],
          'date' => slot[:date]
        }
      end
      # Se list_appointments rodou no mesmo turno e retornou 1
      # consulta, search_available_slots subsequente é parte de um
      # fluxo de REMARCAÇÃO. Marca o offer com target_appointment_id
      # pra que a confirmação ("Sim") dispare reschedule, não book.
      target_id = ctx_state.recent_listed_appointment_id
      ctx_state.offer_slot!(
        starts_at: first[:starts_at],
        duration_minutes: result.dig(:service, :duration_minutes) || 60,
        service_id: result.dig(:service, :id),
        service_name: result.dig(:service, :name),
        user_id: first_pro&.dig(:id),
        professional_name: first_pro&.dig(:name),
        target_appointment_id: target_id,
        alternatives: alternatives,
        ambiguous_reschedule: ctx_state.recent_listing_ambiguous?
      )
    when 'create_patient_minimal'
      # Quando uma ficha de TERCEIRO é criada (pai agendando pra filho),
      # rastreia esse paciente como alvo do fluxo. O book_appointment
      # subsequente usa esse estado pra auto-injetar patient_id se o
      # LLM esquecer (bug clássico de perda de contexto após N turnos).
      return unless result[:created] && result.dig(:patient, :id)

      patient_data = result[:patient]
      if patient_data[:is_third_party]
        ctx_state.set_active_patient!(
          id: patient_data[:id],
          name: patient_data[:name],
          is_third_party: true,
          is_minor: patient_data[:is_minor] || false
        )
      end
    when 'book_appointment'
      return unless result[:booked]

      appt = result[:appointment] || {}
      ctx_state.mark_completed!(
        type: 'booked',
        summary: "#{appt[:title]} para #{appt[:starts_at]} com #{appt[:professional_name]}"
      )
      ctx_state.clear_active_service!
      ctx_state.clear_active_patient!
    when 'reschedule_appointment'
      return unless result[:rescheduled]

      appt = result[:appointment] || {}
      ctx_state.mark_completed!(
        type: 'rescheduled',
        summary: "#{appt[:title]} remarcada para #{appt[:new_starts_at]}"
      )
      ctx_state.clear_active_service!
    when 'cancel_appointment'
      return unless result[:cancelled]

      appt = result[:appointment] || {}
      ctx_state.mark_completed!(
        type: 'cancelled',
        summary: "#{appt[:title]} cancelada (era para #{appt[:was_scheduled_for]})"
      )
      ctx_state.clear_active_service!
    end
  end
end
