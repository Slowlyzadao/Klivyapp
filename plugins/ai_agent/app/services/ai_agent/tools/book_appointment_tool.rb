module AiAgent
  module Tools
    # Books an AgendaEvent for the active patient with a SPECIFIC
    # professional. Bea must pass `user_id` — pegue do `available_with`
    # retornado por search_available_slots. Creates with status
    # `scheduled` (clinic ainda confirma no calendário antes do dia).
    #
    # Guardrails:
    #   - Refuses if no active contact (anonymous chat)
    #   - Refuses if start time is in the past
    #   - Refuses if duration > 4 hours (likely model hallucination)
    #   - If user_id given, valida que pertence à conta e (se service_id
    #     dado) que esse profissional realmente faz o serviço
    class BookAppointmentTool < BaseTool
      description <<~DESC
        Agenda uma consulta para o paciente atual com um profissional
        específico. Use depois que o paciente escolheu um slot retornado
        por search_available_slots E confirmou data/hora/profissional.

        SEMPRE chame antes:
          1. clinic_info (pra pegar service_id e duração)
          2. search_available_slots (pra pegar user_id de available_with)
          3. Confirme com o paciente data, hora e profissional
          4. Aí sim chame book_appointment

        Use formato ISO8601 nos parâmetros de data/hora
        (ex: "2026-05-06T09:00:00-03:00").
      DESC

      param :starts_at,
            type: :string,
            desc: 'Início do agendamento em ISO8601 com timezone (ex: 2026-05-07T09:00:00-03:00). Use o starts_at exato retornado por search_available_slots.'

      param :duration_minutes,
            type: :integer,
            desc: 'Duração da consulta em minutos. Use a duração retornada por clinic_info para o serviço escolhido.'

      param :title,
            type: :string,
            desc: 'Título curto do agendamento, ex: "Avaliação - Maria" ou "Limpeza".'

      param :user_id,
            type: :integer,
            required: false,
            desc: 'ID do profissional escolhido pelo paciente. Pegue de available_with retornado por search_available_slots. Se omitido, recepção atribui depois (use só se você não conseguiu identificar profissional).'

      param :service_id,
            type: :integer,
            required: false,
            desc: 'ID do serviço (opcional). Se passado, valida que o profissional realmente faz esse serviço.'

      param :notes,
            type: :string,
            desc: 'Observações relevantes do paciente (alergia, sintoma mencionado, etc). Pode ficar vazio.',
            required: false

      param :patient_id,
            type: :integer,
            required: false,
            desc: 'ID do paciente (opcional). Use quando o agendamento NÃO é para a pessoa que está conversando (família WhatsApp: pai agendando pra filho). Pegue do retorno de create_patient_minimal ou find_patient_by_phone. Se omitido, agenda para o paciente padrão vinculado ao Contact desta conversa.'

      def execute(starts_at:, duration_minutes: 60, title:, user_id: nil, service_id: nil, notes: '', patient_id: nil)
        return { booked: false, error: 'Módulo de agenda não disponível.' } unless defined?(::AgendaEvent)
        return { booked: false, error: 'Paciente não vinculado a esta conversa.' } if contact_id.blank?

        starts = Time.zone.parse(starts_at) rescue nil
        return { booked: false, error: "Data/hora inválida: #{starts_at}" } if starts.nil?
        return { booked: false, error: 'Não posso agendar no passado.' } if starts < Time.current
        return { booked: false, error: 'Duração inválida (1–240 min).' } unless duration_minutes.to_i.between?(1, 240)

        # Valida user_id se passado (precisa ser da mesma conta).
        if user_id.present?
          user_in_account = account.users.exists?(id: user_id)
          return { booked: false, error: "Profissional #{user_id} não pertence a essa clínica." } unless user_in_account

          # Se também temos service_id, valida que esse profissional
          # realmente realiza esse serviço.
          if service_id.present? && defined?(::AgendaServiceUser)
            does_service = ::AgendaServiceUser.exists?(user_id: user_id, agenda_service_id: service_id, account_id: account.id)
            return { booked: false, error: "Profissional #{user_id} não realiza o serviço #{service_id}. Confirme com o paciente outro profissional ou outro serviço." } unless does_service
          end
        end

        ends = starts + duration_minutes.to_i.minutes

        # Defesa contra duplicação: o LLM às vezes re-chama book_appointment
        # mesmo após já ter criado o evento (perde o contexto e refaz).
        # Se já existe agendamento ativo do mesmo paciente no mesmo slot
        # com o mesmo profissional, devolve o existente em vez de criar
        # outro. Idempotência salva o paciente do "agendou 3 vezes".
        active_match = ::AgendaEvent.where(account_id: account.id, contact_id: contact_id, starts_at: starts)
                                    .where.not(status: %w[cancelled no_show])
        active_match = active_match.where(user_id: user_id) if user_id.present?
        duplicate = active_match.first

        if duplicate
          return {
            booked: false,
            duplicate: true,
            error: 'Já existe um agendamento ativo do paciente nesse horário com esse profissional. Não foi criada uma duplicata.',
            appointment: {
              id: duplicate.id,
              starts_at: duplicate.starts_at.iso8601,
              ends_at: duplicate.ends_at.iso8601,
              title: duplicate.title,
              status: duplicate.status,
              user_id: duplicate.user_id
            }
          }
        end

        # "Cancelei e mudei de ideia" — caso comum: paciente acabou de
        # cancelar a consulta e logo em seguida pediu pra remarcar no
        # mesmo horário. Em vez de criar uma 2ª linha no calendário,
        # REATIVA a cancelada que está aqui há pouco tempo. Janela de
        # 60min cobre conversas reais (paciente decide em poucos
        # minutos); cancelados antigos não viram cobaia de reativação.
        recently_cancelled = ::AgendaEvent.where(
          account_id: account.id,
          contact_id: contact_id,
          starts_at: starts,
          status: 'cancelled'
        ).where('updated_at > ?', 60.minutes.ago)
        recently_cancelled = recently_cancelled.where(user_id: user_id) if user_id.present?
        reactivated = recently_cancelled.order(updated_at: :desc).first

        if reactivated
          merged_description = [reactivated.description.to_s.strip.gsub(/\nMotivo:.*\z/m, '').strip, notes.to_s.strip].reject(&:empty?).join("\n")[0, 1000]
          # Mesma resolução de Patient + Categoria do caminho de criação,
          # pra que a reativação não regrida o card pra "Telefone: Não informado".
          # Respeita patient_id explícito (família WhatsApp).
          reactivated_patient = if defined?(::Patient)
                                  if patient_id.present?
                                    ::Patient.active.find_by(account_id: account.id, id: patient_id)
                                  else
                                    ::Patient.active.find_by(account_id: account.id, contact_id: contact_id)
                                  end
                                end
          reactivated_custom = (reactivated.custom_attributes || {}).merge(
            'patient_id' => reactivated_patient&.id,
            'patient_name' => reactivated_patient&.try(:full_name).presence || reactivated_patient&.name,
            'patient_phone' => reactivated_patient&.phone.presence || ::Contact.find_by(id: contact_id)&.phone_number,
            'service_id' => service_id
          ).compact
          reactivated_title = (reactivated_patient&.try(:full_name).presence || reactivated_patient&.name || title.to_s.strip)[0, 200]
          reactivated.update!(
            status: 'pending_confirmation',
            title: reactivated_title,
            description: merged_description,
            ends_at: ends,
            category_id: resolve_category_id(service_id),
            custom_attributes: reactivated_custom,
            source: 'ai_agent'
          )

          if patient_memory
            patient_memory.append_history(
              event_type: 'appointment_reactivated',
              summary: "#{title} em #{starts.strftime('%d/%m/%Y %H:%M')} reativada (após cancelamento recente)",
              metadata: { agenda_event_id: reactivated.id }
            )
          end

          professional_name = user_id.present? ? AiAgent::Formatters::ProfessionalName.format(account.users.find_by(id: user_id)&.name) : nil
        professional_name = nil if professional_name.to_s.empty?
          return {
            booked: true,
            reactivated: true,
            confirmation_pending: true,
            appointment: {
              id: reactivated.id,
              starts_at: reactivated.starts_at.iso8601,
              ends_at: reactivated.ends_at.iso8601,
              title: reactivated.title,
              status: reactivated.status,
              user_id: reactivated.user_id,
              professional_name: professional_name,
              note_for_patient: professional_name.present? ?
                "Reabri sua reserva com #{professional_name}. A clínica vai confirmar e te avisar." :
                'Reabri sua reserva. A clínica vai confirmar e te avisar.'
            }
          }
        end

        # Resolve Patient (prontuário) e Categoria pra popular o evento
        # exatamente como a recepção popularia via UI. Sem isso, frontend
        # mostra "Telefone: Não informado" e Categoria fica em branco.
        # Se `patient_id` foi passado (família WhatsApp: pai agenda pra
        # filho), usa esse paciente — mas valida que pertence ao mesmo
        # Contact desta conversa, senão é vazamento entre conversas.
        patient = if defined?(::Patient)
                    if patient_id.present?
                      candidate = ::Patient.active.find_by(account_id: account.id, id: patient_id)
                      if candidate.nil? || candidate.contact_id != contact_id
                        return { booked: false, error: "Paciente #{patient_id} não pertence a este WhatsApp." }
                      end
                      candidate
                    else
                      ::Patient.active.find_by(account_id: account.id, contact_id: contact_id)
                    end
                  end
        category_id = resolve_category_id(service_id)

        # Título do evento = nome do paciente apenas (convenção da clínica
        # alinhada com cadastro manual da recepção). O serviço fica
        # estruturado em custom_attributes.service_id e a categoria em
        # category_id — não precisa repetir no título.
        event_title = (patient&.try(:full_name).presence || patient&.name || title.to_s.strip)[0, 200]

        custom_attrs = {
          'patient_id' => patient&.id,
          'patient_name' => patient&.try(:full_name).presence || patient&.name,
          'patient_phone' => patient&.phone.presence || ::Contact.find_by(id: contact_id)&.phone_number,
          'service_id' => service_id
        }.compact

        event = ::AgendaEvent.create!(
          account_id: account.id,
          contact_id: contact_id,
          user_id: user_id,
          category_id: category_id,
          title: event_title,
          description: notes.to_s.strip[0, 1000],
          starts_at: starts,
          ends_at: ends,
          custom_attributes: custom_attrs,
          # `pending_confirmation`: humano da clínica precisa validar antes
          # de virar `scheduled`. Decisão D-16 do plano: em piloto, toda
          # criação por IA passa por humano. Notificação ao paciente só
          # dispara quando humano aprovar (vide AgendaEvent#approved_after_pending?).
          status: 'pending_confirmation',
          # 'consultation' (UI: "Consulta") é o tipo correto pra agendamento
          # com paciente. 'appointment' renderiza como "Compromisso" e é
          # reservado a bloqueios de agenda sem paciente vinculado.
          event_type: 'consultation',
          # Marca origem pra que regras de Follow-up possam filtrar por
          # quem agendou (Bea/humano/ambos). Single point of write —
          # qualquer outra rota que crie evento fica como 'manual' por default.
          source: 'ai_agent'
        )

        if patient_memory
          patient_memory.append_history(
            event_type: 'appointment_booked',
            summary: "#{title} em #{starts.strftime('%d/%m/%Y %H:%M')}",
            metadata: { agenda_event_id: event.id }
          )
        end

        professional_name = user_id.present? ? AiAgent::Formatters::ProfessionalName.format(account.users.find_by(id: user_id)&.name) : nil
        professional_name = nil if professional_name.to_s.empty?

        {
          booked: true,
          confirmation_pending: true,
          appointment: {
            id: event.id,
            starts_at: event.starts_at.iso8601,
            ends_at: event.ends_at.iso8601,
            title: event.title,
            status: event.status,
            user_id: event.user_id,
            professional_name: professional_name,
            note_for_patient: professional_name.present? ?
              "Reserva feita com #{professional_name}. A clínica vai confirmar e te avisar." :
              'A reserva foi feita e a clínica vai confirmar o profissional e te avisar.'
          }
        }
      rescue ActiveRecord::RecordInvalid => e
        { booked: false, error: e.message }
      end

      private

      # Pega a categoria padrão configurada no AgendaService (campo
      # `default_category_id`, definido pela clínica em /agenda/serviços
      # → "Categoria padrão"). Não há mais fallback por nome — se a
      # clínica não configurou, evento fica sem categoria e recepção
      # decide. Mais previsível que mapeamento mágico.
      def resolve_category_id(service_id)
        return nil if service_id.blank?

        ::AgendaService.where(account_id: account.id).where(id: service_id).pick(:default_category_id)
      end
    end
  end
end
