# Versão "interna" do BookAppointmentTool — pra Pipeline B (Bea
# responde no Chat Interno). Recebe `patient_id` explícito (sem
# depender de `contact_id` da sessão).
#
# Cria evento em `pending_confirmation` (mesma decisão D-16) — equipe
# valida na agenda. NÃO notifica paciente automaticamente.
#
# Spec: docs/01-product/ai-agent-configuration-plan.md (Apêndice F.3)
class AiAgent::Tools::InternalBookAppointmentTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Cria um NOVO agendamento pra um paciente existente. Use APENAS depois
    que a equipe interna CONFIRMAR explicitamente o agendamento (ver regra
    de "propor antes de executar" no system prompt).

    Sequência obrigatória:
      1. internal_search_patient → encontra patient_id
      2. clinic_info → confirma serviços + duração + profissionais que atendem
      3. PROPONHA no texto: "Posso agendar X com Dra. Y no dia DD/MM às HH:MM. Confirma?"
      4. ESPERE a equipe responder "sim" / "confirma" / "pode"
      5. SÓ AÍ chame essa tool

    NUNCA chame essa tool sem o passo 4. Se a equipe não especificou
    profissional ou serviço, PERGUNTE no passo 3 antes de propor.
  DESC

  param :patient_id,
        type: :integer,
        desc: 'ID do paciente. Vem de internal_search_patient.'

  param :starts_at,
        type: :string,
        desc: 'Início ISO8601 com timezone (ex: 2026-05-14T11:00:00-03:00).'

  param :duration_minutes,
        type: :integer,
        required: false,
        desc: 'Duração em minutos (padrão 60). Use a duração do serviço escolhido em clinic_info.'

  param :user_id,
        type: :integer,
        required: false,
        desc: 'ID do profissional. Pega dos `professionals[]` retornados em clinic_info pra cada serviço. Se equipe não disse, pergunte antes de propor.'

  param :service_id,
        type: :integer,
        required: false,
        desc: 'ID do serviço (opcional). Se passado, valida que profissional realiza esse serviço.'

  param :title,
        type: :string,
        required: false,
        desc: 'Título da consulta (opcional). Se vazio, usa o nome do paciente.'

  param :notes,
        type: :string,
        required: false,
        desc: 'Observações relevantes (opcional).'

  def execute(patient_id:, starts_at:, duration_minutes: 60, user_id: nil, service_id: nil, title: '', notes: '')
    return failure('Módulo de agenda não disponível.') unless defined?(::AgendaEvent)
    return failure('Módulo de pacientes não disponível.') unless defined?(::Patient)
    # SEC-12: gate por perm `agenda:create_event` do staff que invocou.
    return permission_denied unless invoking_user_can?(:agenda, :create_event)

    patient = ::Patient.active.find_by(account_id: account.id, id: patient_id)
    return failure("Paciente #{patient_id} não encontrado.") if patient.nil?
    return failure('Paciente sem contact_id vinculado — não dá pra criar agendamento sem ponte com Chatwoot.') if patient.contact_id.blank?

    starts = begin
      Time.zone.parse(starts_at)
    rescue StandardError
      nil
    end
    return failure("Data/hora inválida: #{starts_at}") if starts.nil?
    return failure('Não posso agendar no passado.') if starts < Time.current
    return failure('Duração inválida (1–240 min).') unless duration_minutes.to_i.between?(1, 240)

    if user_id.present?
      return failure("Profissional #{user_id} não pertence a essa clínica.") unless account.users.exists?(id: user_id)

      if service_id.present? && defined?(::AgendaServiceUser) && !::AgendaServiceUser.exists?(user_id: user_id, agenda_service_id: service_id,
                                                                                              account_id: account.id)
        return failure("Profissional #{user_id} não realiza o serviço #{service_id}.")
      end
    end

    ends = starts + duration_minutes.to_i.minutes

    # Mesma defesa de duplicação do BookAppointmentTool original
    active_match = ::AgendaEvent.where(account_id: account.id, contact_id: patient.contact_id,
                                       starts_at: starts).where.not(status: %w[cancelled no_show])
    active_match = active_match.where(user_id: user_id) if user_id.present?
    if (duplicate = active_match.first)
      return {
        booked: false,
        duplicate: true,
        error: 'Já existe agendamento ativo do paciente nesse horário.',
        appointment: { id: duplicate.id, starts_at: duplicate.starts_at.iso8601, status: duplicate.status }
      }
    end

    event_title = (title.presence || patient.try(:full_name).presence || patient.name).to_s[0, 200]

    custom_attrs = {
      'patient_id' => patient.id,
      'patient_name' => patient.try(:full_name).presence || patient.name,
      'patient_phone' => patient.phone.presence || ::Contact.find_by(id: patient.contact_id)&.phone_number,
      'service_id' => service_id
    }.compact

    category_id = if service_id.present? && defined?(::AgendaService)
                    ::AgendaService.where(account_id: account.id, id: service_id).pick(:default_category_id)
                  end

    event = ::AgendaEvent.create!(
      account_id: account.id,
      contact_id: patient.contact_id,
      user_id: user_id,
      category_id: category_id,
      title: event_title,
      description: notes.to_s.strip[0, 1000],
      starts_at: starts,
      ends_at: ends,
      custom_attributes: custom_attrs,
      status: 'pending_confirmation',
      event_type: 'consultation',
      source: 'ai_agent'
    )

    {
      booked: true,
      appointment: {
        id: event.id,
        title: event.title,
        starts_at: event.starts_at.iso8601,
        ends_at: event.ends_at.iso8601,
        professional: event.user&.name,
        status: event.status,
        note_for_team: 'Agendado em pending_confirmation. Equipe valida na agenda. Paciente NÃO foi notificado.'
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    failure(e.message)
  rescue ActiveRecord::RecordNotUnique => e
    # BE-7: race condition resolvida pelo unique index
    # `idx_agenda_events_unique_active_slot_per_patient`. Outro tool call
    # concorrente ganhou — re-busca o vencedor.
    Rails.logger.info(
      "[AiAgent::InternalBookAppointmentTool] race condition handled via unique index: #{e.message}"
    )
    winner = ::AgendaEvent
             .where(account_id: account.id, contact_id: patient.contact_id, starts_at: starts, deleted_at: nil)
             .where.not(status: %w[cancelled no_show])
             .where(user_id: user_id).order(created_at: :asc).first
    if winner
      {
        booked: false,
        duplicate: true,
        race_resolved: true,
        appointment: { id: winner.id, starts_at: winner.starts_at.iso8601, status: winner.status }
      }
    else
      failure('Não consegui confirmar o agendamento (race). Tente de novo.')
    end
  end

  private

  def failure(msg)
    { booked: false, error: msg }
  end

  def permission_denied
    {
      booked: false,
      permission_denied: true,
      note_for_bea: 'Quem mencionou você não tem permissão pra criar consultas. ' \
                    'Avise educadamente que só admins ou usuários com permissão de agenda podem agendar.'
    }
  end
end
