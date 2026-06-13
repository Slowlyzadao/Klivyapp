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
class AiAgent::Tools::BookAppointmentTool < AiAgent::Tools::BaseTool
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
        desc: 'OBRIGATÓRIO. ID do profissional escolhido. Pegue de available_with retornado por search_available_slots (ou professionals do clinic_info). NUNCA invente um número.'

  param :service_id,
        type: :integer,
        desc: 'OBRIGATÓRIO. ID do serviço, da lista de services do clinic_info. Se o serviço pedido não está na lista, a clínica NÃO atende — não agende.'

  param :notes,
        type: :string,
        desc: 'Observações relevantes do paciente (alergia, sintoma mencionado, etc). Pode ficar vazio.',
        required: false

  param :patient_id,
        type: :integer,
        required: false,
        desc: 'ID do paciente (opcional). Use quando o agendamento NÃO é para a pessoa que está conversando (família WhatsApp: pai agendando pra filho). Pegue do retorno de create_patient_minimal ou find_patient_by_phone. Se omitido, agenda para o paciente padrão vinculado ao Contact desta conversa.'

  def execute(starts_at:, title:, duration_minutes: 60, user_id: nil, service_id: nil, notes: '', patient_id: nil)
    return { booked: false, error: 'Módulo de agenda não disponível.' } unless defined?(::AgendaEvent)
    return { booked: false, error: 'Paciente não vinculado a esta conversa.' } if contact_id.blank?

    starts = begin
      Time.zone.parse(starts_at)
    rescue StandardError
      nil
    end
    return { booked: false, error: "Data/hora inválida: #{starts_at}" } if starts.nil?
    return { booked: false, error: 'Não posso agendar no passado.' } if starts < Time.current
    return { booked: false, error: 'Duração inválida (1–240 min).' } unless duration_minutes.to_i.between?(1, 240)

    # service_id e user_id são OBRIGATÓRIOS: sem eles a validação
    # profissional×serviço não roda e dá pra agendar um serviço que ninguém
    # da clínica realiza. Os ids vêm de clinic_info / search_available_slots.
    if service_id.blank?
      return { booked: false, needs_service: true,
               note_for_bea: 'NÃO agende sem service_id: chame clinic_info, confirme que o serviço pedido está na lista ' \
                             '(se não estiver, a clínica NÃO atende — informe e liste o que ela atende) e re-chame com o id.' }
    end
    if user_id.blank?
      return { booked: false, needs_professional: true,
               note_for_bea: 'NÃO agende sem user_id do profissional: use o id que veio em available_with do ' \
                             'search_available_slots (ou em professionals do clinic_info) e re-chame.' }
    end

    user_in_account = account.users.exists?(id: user_id)
    return { booked: false, error: "Profissional #{user_id} não pertence a essa clínica." } unless user_in_account

    # O profissional precisa REALMENTE realizar esse serviço — nunca agendar
    # um par profissional×serviço que não existe no cadastro da clínica.
    if defined?(::AgendaServiceUser)
      does_service = ::AgendaServiceUser.exists?(user_id: user_id, agenda_service_id: service_id, account_id: account.id)
      unless does_service
        validos = ::AgendaService.find_by(account_id: account.id, id: service_id)
                                 &.professionals&.map { |u| { id: u.id, name: u.name } } || []
        return { booked: false,
                 valid_professionals: validos,
                 error: "Profissional #{user_id} não realiza o serviço #{service_id}.",
                 note_for_bea: if validos.any?
                                 'Profissional ERRADO pra esse serviço — re-chame com um dos ids de valid_professionals.'
                               else
                                 'NENHUM profissional realiza esse serviço — a clínica NÃO o atende. Informe com leveza e ' \
                                 'liste os serviços do clinic_info como alternativa. NÃO agende.'
                               end }
      end
    end

    ends = starts + duration_minutes.to_i.minutes

    # Defesa contra duplicação: o LLM às vezes re-chama book_appointment
    # mesmo após já ter criado o evento (perde o contexto e refaz).
    # Se já existe agendamento ativo do mesmo paciente no mesmo slot
    # com o mesmo profissional, devolve o existente em vez de criar
    # outro. Idempotência salva o paciente do "agendou 3 vezes".
    active_match = ::AgendaEvent.kept.where(account_id: account.id, contact_id: contact_id, starts_at: starts)
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
    recently_cancelled = ::AgendaEvent.kept.where(
      account_id: account.id,
      contact_id: contact_id,
      starts_at: starts,
      status: 'cancelled'
    ).where('updated_at > ?', 60.minutes.ago)
    recently_cancelled = recently_cancelled.where(user_id: user_id) if user_id.present?
    reactivated = recently_cancelled.order(updated_at: :desc).first

    if reactivated
      merged_description = [reactivated.description.to_s.strip.gsub(/\nMotivo:.*\z/m, '').strip, notes.to_s.strip].reject(&:empty?).join("\n")[0,
                                                                                                                                               1000]
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
        status: 'scheduled',
        title: reactivated_title,
        description: merged_description,
        ends_at: ends,
        category_id: resolve_category_id(service_id),
        custom_attributes: reactivated_custom,
        source: 'ai_agent'
      )

      patient_memory&.append_history(
        event_type: 'appointment_reactivated',
        summary: "#{title} em #{starts.strftime('%d/%m/%Y %H:%M')} reativada (após cancelamento recente)",
        metadata: { agenda_event_id: reactivated.id }
      )

      professional_name = user_id.present? ? AiAgent::Formatters::ProfessionalName.format(account.users.find_by(id: user_id)&.name) : nil
      professional_name = nil if professional_name.to_s.empty?
      return {
        booked: true,
        reactivated: true,
        confirmation_pending: false,
        appointment: {
          id: reactivated.id,
          starts_at: reactivated.starts_at.iso8601,
          ends_at: reactivated.ends_at.iso8601,
          title: reactivated.title,
          status: reactivated.status,
          user_id: reactivated.user_id,
          professional_name: professional_name,
          note_for_patient: booking_success_note(
            professional_name.present? ? "Reabri e CONFIRMEI sua reserva com #{professional_name}." : 'Reabri e CONFIRMEI sua reserva.'
          )
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

    # Safety net: NUNCA agenda sem ficha de paciente. Se não há cadastro pra
    # este contato, a Bea pulou o create_patient_minimal — recusa e manda criar
    # a ficha ANTES. Sem isso o evento fica órfão (paciente "agendou" mas não
    # foi cadastrado, sem prontuário). CPF é obrigatório no cadastro, então não
    # dá pra auto-criar aqui — a Bea precisa pedir nome + CPF.
    if patient.nil?
      return {
        booked: false,
        needs_patient: true,
        note_for_bea: 'NÃO há ficha de paciente vinculada a este contato. ANTES de agendar, crie a ficha ' \
                      'com create_patient_minimal (peça nome completo + CPF ao paciente). É PROIBIDO agendar sem cadastro.'
      }
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
      # `scheduled`: o agendamento da IA já entra CONFIRMADO/ativo, igual ao
      # cadastro manual da recepção (decisão do dono: a Bia fecha sozinha,
      # sem etapa de validação humana — supersede o piloto D-16). Status
      # válido no AgendaEvent, visível na agenda e contado nos relatórios.
      status: 'scheduled',
      # 'consultation' (UI: "Consulta") é o tipo correto pra agendamento
      # com paciente. 'appointment' renderiza como "Compromisso" e é
      # reservado a bloqueios de agenda sem paciente vinculado.
      event_type: 'consultation',
      # Marca origem pra que regras de Follow-up possam filtrar por
      # quem agendou (Bea/humano/ambos). Single point of write —
      # qualquer outra rota que crie evento fica como 'manual' por default.
      source: 'ai_agent'
    )

    patient_memory&.append_history(
      event_type: 'appointment_booked',
      summary: "#{title} em #{starts.strftime('%d/%m/%Y %H:%M')}",
      metadata: { agenda_event_id: event.id }
    )

    professional_name = user_id.present? ? AiAgent::Formatters::ProfessionalName.format(account.users.find_by(id: user_id)&.name) : nil
    professional_name = nil if professional_name.to_s.empty?

    {
      booked: true,
      confirmation_pending: false,
      appointment: {
        id: event.id,
        starts_at: event.starts_at.iso8601,
        ends_at: event.ends_at.iso8601,
        title: event.title,
        status: event.status,
        user_id: event.user_id,
        professional_name: professional_name,
        note_for_patient: booking_success_note(
          professional_name.present? ? "Agendamento CONFIRMADO com #{professional_name}." : 'Agendamento CONFIRMADO.'
        )
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    { booked: false, error: e.message }
  rescue ActiveRecord::RecordNotUnique => e
    # BE-7 (auditoria 2026-05-18): race condition fechada por unique index
    # `idx_agenda_events_unique_active_slot_per_patient`. Duas calls
    # simultâneas do tool no mesmo slot: o check Ruby de duplicata passa
    # pra ambas (linhas 96-115), mas só uma sobrevive ao INSERT — a outra
    # explode aqui. Re-busca o vencedor e devolve duplicate-friendly em
    # vez de erro técnico.
    Rails.logger.info(
      "[AiAgent::BookAppointmentTool] race condition handled via unique index: #{e.message}"
    )
    winner = ::AgendaEvent
             .where(account_id: account.id, contact_id: contact_id, starts_at: starts, deleted_at: nil)
             .where.not(status: %w[cancelled no_show])
             .where(user_id: user_id).order(created_at: :asc).first
    if winner
      {
        booked: false,
        duplicate: true,
        race_resolved: true,
        appointment: {
          id: winner.id,
          starts_at: winner.starts_at.iso8601,
          ends_at: winner.ends_at.iso8601,
          title: winner.title,
          status: winner.status,
          user_id: winner.user_id
        },
        note_for_bea: 'Outro pedido concorrente reservou esse mesmo horário primeiro. Mostre o agendamento existente ao paciente.'
      }
    else
      # Race extremamente improvável: vencedor sumiu (cancelled na mesma janela)
      { booked: false, error: 'Não consegui confirmar o agendamento. Por favor, tente novamente.' }
    end
  end

  private

  # Nota de sucesso do book: manda o resumo E o FECHAMENTO obrigatório
  # (como conheceu → update_patient_record; e "posso te ajudar em mais
  # alguma coisa?"). Sem isso a Bea parava no resumo e não encerrava.
  def booking_success_note(prefix)
    "#{prefix} Confirme e mande o resumo (dia, horário, endereço + Maps do clinic_info). " \
      'DEPOIS pergunte como o paciente conheceu a clínica (registre com update_patient_record) ' \
      'e SEMPRE feche perguntando se pode te ajudar em mais alguma coisa.'
  end

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
