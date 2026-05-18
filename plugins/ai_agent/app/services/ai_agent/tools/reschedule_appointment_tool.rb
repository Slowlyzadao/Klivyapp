module AiAgent
  module Tools
    # Reschedules an existing AgendaEvent to a new starts_at, keeping the
    # same duration, professional, contact, service. Bea must:
    #   1. call list_appointments to get the id of the right appointment
    #   2. call search_available_slots to find a free new time
    #   3. confirm new time with the patient
    #   4. call this tool
    #
    # Guardrails:
    #   - Only reschedules events of the active contact (security)
    #   - Refuses if the event is in the past, cancelled, completed, or no_show
    #   - Refuses if the new time is in the past
    #   - Status returns to `scheduled` even if it was `confirmed` (clinic
    #     re-confirms)
    class RescheduleAppointmentTool < BaseTool
      description <<~DESC
        Remarca uma consulta existente do paciente atual para uma nova
        data/hora. Use quando o paciente pedir pra remarcar/transferir
        uma consulta.

        Sequência obrigatória ANTES de chamar:
          1. list_appointments → pega o id da consulta a remarcar
             (se houver mais de uma futura, pergunte ao paciente qual)
          2. search_available_slots → busca horário novo (use service_id
             se você sabe — pode pegar do título ou perguntar)
          3. Confirme com o paciente o novo horário ANTES de chamar
        Use ISO8601 com timezone -03:00 em new_starts_at.
      DESC

      param :appointment_id,
            type: :integer,
            desc: 'ID da consulta a remarcar. Vem de list_appointments → appointments[].id.'

      param :new_starts_at,
            type: :string,
            desc: 'Novo início em ISO8601 com timezone (ex: 2026-05-13T10:00:00-03:00).'

      param :reason,
            type: :string,
            required: false,
            desc: 'Motivo do reagendamento (opcional, vai pra description).'

      BLOCKED_STATUSES_FOR_RESCHEDULE = %w[cancelled completed no_show].freeze

      def execute(appointment_id:, new_starts_at:, reason: '')
        return failure('Módulo de agenda não disponível.') unless defined?(::AgendaEvent)
        return failure('Paciente não vinculado a esta conversa.') if contact_id.blank?

        event = ::AgendaEvent.where(account_id: account.id).find_by(id: appointment_id)
        return failure("Consulta #{appointment_id} não encontrada.") if event.nil?
        return failure('Essa consulta não pertence a este paciente.') if event.contact_id != contact_id
        return failure("Consulta com status '#{event.status}' não pode ser remarcada.") if BLOCKED_STATUSES_FOR_RESCHEDULE.include?(event.status)
        return failure('Não posso remarcar consulta que já passou.') if event.starts_at < Time.current

        new_starts = Time.zone.parse(new_starts_at) rescue nil
        return failure("Data/hora inválida: #{new_starts_at}") if new_starts.nil?
        return failure('Não posso remarcar para o passado.') if new_starts < Time.current

        duration_minutes = ((event.ends_at - event.starts_at) / 60).to_i
        new_ends = new_starts + duration_minutes.minutes

        old_starts = event.starts_at
        merged_description = [event.description.to_s.strip, reason.present? ? "Reagendado: #{reason}" : nil].compact.reject(&:empty?).join("\n")[0, 1000]

        # Backfill: se o evento foi criado antes do fix de custom_attributes
        # (ou criado direto via SQL/migration), popula vínculo de paciente
        # agora pra que o card no frontend deixe de mostrar "Telefone:
        # Não informado". Não sobrescreve dados manuais.
        existing_attrs = event.custom_attributes || {}
        patient = defined?(::Patient) ? ::Patient.active.find_by(account_id: account.id, contact_id: contact_id) : nil
        backfilled = existing_attrs.merge(
          {
            'patient_id' => existing_attrs['patient_id'].presence || patient&.id,
            'patient_name' => existing_attrs['patient_name'].presence || patient&.try(:full_name).presence || patient&.name,
            'patient_phone' => existing_attrs['patient_phone'].presence || patient&.phone.presence || ::Contact.find_by(id: contact_id)&.phone_number
          }.compact
        )

        # Volta pra `pending_confirmation` mesmo se já estava `scheduled`
        # ou `confirmed`: humano precisa revalidar a nova data, porque
        # quem moveu foi a IA. Notificações ao paciente saem só após
        # aprovação humana (vide AgendaEvent#approved_after_pending?).
        event.update!(
          starts_at: new_starts,
          ends_at: new_ends,
          status: 'pending_confirmation',
          description: merged_description,
          custom_attributes: backfilled,
          category_id: event.category_id || infer_category_id_from_event(event)
        )

        if patient_memory
          patient_memory.append_history(
            event_type: 'appointment_rescheduled',
            summary: "#{event.title}: de #{old_starts.strftime('%d/%m %H:%M')} para #{new_starts.strftime('%d/%m %H:%M')}",
            metadata: { agenda_event_id: event.id, reason: reason.presence }
          )
        end

        {
          rescheduled: true,
          confirmation_pending: true,
          appointment: {
            id: event.id,
            title: event.title,
            old_starts_at: old_starts.iso8601,
            new_starts_at: event.starts_at.iso8601,
            ends_at: event.ends_at.iso8601,
            professional: AiAgent::Formatters::ProfessionalName.format(event.user&.name).presence,
            status: event.status,
            note_for_patient: 'Reserva movida para o novo horário. A clínica vai confirmar e te avisar.'
          }
        }
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message)
      end

      private

      def failure(msg)
        { rescheduled: false, error: msg }
      end

      # Pega `default_category_id` do AgendaService armazenado em
      # custom_attributes['service_id']. Sem fallback por nome — se a
      # clínica não configurou a categoria padrão pro serviço, evento
      # fica sem categoria e recepção decide. Mais previsível.
      def infer_category_id_from_event(event)
        attrs = event.custom_attributes || {}
        service_id = attrs['service_id']
        return nil if service_id.blank?

        ::AgendaService.where(account_id: account.id).where(id: service_id).pick(:default_category_id)
      end
    end
  end
end
