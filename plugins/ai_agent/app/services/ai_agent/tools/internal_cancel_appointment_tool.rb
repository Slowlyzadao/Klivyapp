# Versão "interna" do CancelAppointmentTool — pra Pipeline B (Bea
# responde no Chat Interno). Recebe `agenda_event_id` direto e valida
# que o evento pertence à conta da Bea.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
class AiAgent::Tools::InternalCancelAppointmentTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Cancela uma consulta agendada. Use APENAS depois que a equipe interna
    CONFIRMAR explicitamente o cancelamento (ver regra de "propor antes
    de executar" no system prompt).

    Sequência obrigatória:
      1. internal_search_patient → encontra patient_id
      2. internal_list_patient_appointments → encontra agenda_event_id
      3. PROPONHA no texto: "Posso cancelar X de Y. Confirma?"
      4. ESPERE a equipe responder "sim" / "confirma" / "pode"
      5. SÓ AÍ chame essa tool

    NUNCA chame essa tool sem o passo 4.
  DESC

  param :agenda_event_id,
        type: :integer,
        desc: 'ID do AgendaEvent a cancelar. Vem de internal_list_patient_appointments.'

  param :reason,
        type: :string,
        required: false,
        desc: 'Motivo do cancelamento (opcional, vai pra description).'

  ALREADY_CLOSED = %w[cancelled completed no_show].freeze

  def execute(agenda_event_id:, reason: '')
    return failure('Módulo de agenda não disponível.') unless defined?(::AgendaEvent)
    # SEC-12: gate por perm `agenda:cancel_event` do staff que invocou
    # Bea. Bloqueia recepcionista sem perm de tentar cancelar via @bea.
    return permission_denied unless invoking_user_can?(:agenda, :cancel_event)

    event = ::AgendaEvent.where(account_id: account.id).find_by(id: agenda_event_id)
    return failure("Consulta #{agenda_event_id} não encontrada nesta clínica.") if event.nil?
    return failure("Consulta já está como '#{event.status}'.") if ALREADY_CLOSED.include?(event.status)
    return failure('Não posso cancelar consulta que já passou.') if event.starts_at < Time.current

    merged_description = [event.description.to_s.strip,
                          reason.present? ? "Cancelado (Bea via chat interno): #{reason}" : 'Cancelado pela Bea via chat interno'].compact.reject(&:empty?).join("\n")[0, 1000]

    event.update!(
      status: 'cancelled',
      description: merged_description
    )

    {
      cancelled: true,
      appointment: {
        id: event.id,
        title: event.title,
        was_scheduled_for: event.starts_at.iso8601,
        professional: event.user&.name,
        status: event.status,
        note_for_team: 'Cancelado. Paciente NÃO foi notificado automaticamente — equipe decide se avisa.'
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    failure(e.message)
  end

  private

  def failure(msg)
    { cancelled: false, error: msg }
  end

  def permission_denied
    {
      cancelled: false,
      permission_denied: true,
      note_for_bea: 'Quem mencionou você não tem permissão pra cancelar consultas. ' \
                    'Avise educadamente que só admins ou usuários com permissão de agenda podem fazer isso.'
    }
  end
end
