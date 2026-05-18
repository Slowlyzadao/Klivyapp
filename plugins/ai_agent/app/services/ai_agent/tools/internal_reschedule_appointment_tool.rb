module AiAgent
  module Tools
    # Versão "interna" do RescheduleAppointmentTool — pra Pipeline B (Bea
    # responde no Chat Interno). Recebe `agenda_event_id` direto (sem
    # depender de `contact_id` da sessão) e valida que o evento pertence
    # à conta da Bea.
    #
    # Mantém o mesmo comportamento do tool original: volta status pra
    # `pending_confirmation` (humano valida antes do paciente saber),
    # NÃO dispara WhatsApp pro paciente, soft-update via custom_attributes.
    #
    # Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
    class InternalRescheduleAppointmentTool < BaseTool
      description <<~DESC
        Reagenda uma consulta existente pra nova data/hora. Use APENAS depois
        que a equipe interna CONFIRMAR explicitamente o reagendamento (ver
        regra de "propor antes de executar" no system prompt).

        Sequência obrigatória:
          1. internal_search_patient → encontra patient_id
          2. internal_list_patient_appointments → encontra agenda_event_id
          3. PROPONHA no texto: "Posso reagendar X de Y pra Z. Confirma?"
          4. ESPERE a equipe responder "sim" / "confirma" / "pode"
          5. SÓ AÍ chame essa tool

        NUNCA chame essa tool sem o passo 4.
      DESC

      param :agenda_event_id,
            type: :integer,
            desc: 'ID do AgendaEvent a reagendar. Vem de internal_list_patient_appointments.'

      param :new_starts_at,
            type: :string,
            desc: 'Novo início ISO8601 com timezone (ex: 2026-05-13T14:00:00-03:00).'

      param :reason,
            type: :string,
            required: false,
            desc: 'Motivo do reagendamento (opcional, vai pra description).'

      BLOCKED_STATUSES = %w[cancelled completed no_show].freeze

      def execute(agenda_event_id:, new_starts_at:, reason: '')
        return failure('Módulo de agenda não disponível.') unless defined?(::AgendaEvent)

        event = ::AgendaEvent.where(account_id: account.id).find_by(id: agenda_event_id)
        return failure("Consulta #{agenda_event_id} não encontrada nesta clínica.") if event.nil?
        return failure("Consulta com status '#{event.status}' não pode ser reagendada.") if BLOCKED_STATUSES.include?(event.status)
        return failure('Não posso reagendar consulta que já passou.') if event.starts_at < Time.current

        new_starts = Time.zone.parse(new_starts_at) rescue nil
        return failure("Data/hora inválida: #{new_starts_at}") if new_starts.nil?
        return failure('Não posso reagendar pro passado.') if new_starts < Time.current

        duration_minutes = ((event.ends_at - event.starts_at) / 60).to_i
        new_ends = new_starts + duration_minutes.minutes

        old_starts = event.starts_at
        merged_description = [event.description.to_s.strip,
                              reason.present? ? "Reagendado (Bea via chat interno): #{reason}" : 'Reagendado pela Bea via chat interno'].compact.reject(&:empty?).join("\n")[0, 1000]

        # Volta pra pending_confirmation pra que a equipe revalide na agenda
        # (NÃO dispara notificação automática ao paciente).
        event.update!(
          starts_at: new_starts,
          ends_at: new_ends,
          status: 'pending_confirmation',
          description: merged_description
        )

        {
          rescheduled: true,
          appointment: {
            id: event.id,
            title: event.title,
            old_starts_at: old_starts.iso8601,
            new_starts_at: event.starts_at.iso8601,
            ends_at: event.ends_at.iso8601,
            professional: event.user&.name,
            status: event.status,
            note_for_team: 'Reagendado. Status voltou pra pending_confirmation — equipe revalida na agenda. Paciente NÃO foi notificado automaticamente.'
          }
        }
      rescue ActiveRecord::RecordInvalid => e
        failure(e.message)
      end

      private

      def failure(msg)
        { rescheduled: false, error: msg }
      end
    end
  end
end
