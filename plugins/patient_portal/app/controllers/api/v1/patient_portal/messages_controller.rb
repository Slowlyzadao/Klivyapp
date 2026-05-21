# Mensagens entre paciente e clínica (PRD §12).
#
# Reuso de `Conversation`/`Message` do Chatwoot via `MessagingBridge`.
# Endpoints:
#   GET  /messages         → conversa ativa + lista paginada de mensagens
#   POST /messages         → envia mensagem (com triagem urgente)
#   POST /messages/triage  → consulta-only: a mensagem é urgente? (front
#                            chama antes de enviar pra decidir se mostra modal)
class Api::V1::PatientPortal::MessagesController < Api::V1::PatientPortal::BaseController
  def index
    return render_disabled if disabled?
    return render_no_contact unless current_patient.contact_id.present?

    bridge = PatientPortal::MessagingBridge.new(account: current_account, patient: current_patient)
    conv = bridge.conversation
    msgs = bridge.messages(limit: 100)

    render json: {
      data: {
        conversation: serialize_conversation(conv),
        messages:     msgs.map { |m| serialize_message(m) }
      }
    }
  end

  def create
    return render_disabled if disabled?
    return render_no_contact unless current_patient.contact_id.present?

    # Sprint H — bloqueio progressivo por inadimplência.
    restriction = PatientPortal::OverdueRestrictionChecker.new(
      account: current_account, patient: current_patient
    ).call
    if restriction.blocks_messaging?
      return render_error(
        "Mensagens temporariamente restritas. Quite suas pendências para voltar a conversar.",
        status: :unprocessable_entity, code: 'overdue_blocks_messaging'
      )
    end

    content = params[:content].to_s.strip
    return render_error('Mensagem vazia.') if content.blank?
    return render_error('Mensagem muito longa (máx 4000 caracteres).') if content.length > 4000

    bridge = PatientPortal::MessagingBridge.new(account: current_account, patient: current_patient)
    triage = PatientPortal::UrgentTriage.new(account: current_account, text: content)

    msg = bridge.send_message!(content: content, urgent: triage.urgent?)
    log!('create', msg)

    render json: {
      data: {
        message: serialize_message(msg),
        urgent:  triage.urgent?,
        urgent_keywords: triage.matched_keywords
      }
    }, status: :created
  rescue StandardError => e
    render_error(e.message)
  end

  # Consultivo — front pode perguntar "essa mensagem é urgente?" antes de
  # enviar, pra mostrar modal "ligue ao invés".
  def triage
    content = params[:content].to_s
    t = PatientPortal::UrgentTriage.new(account: current_account, text: content)
    render json: {
      data: {
        urgent:        t.urgent?,
        keywords:      t.matched_keywords,
        clinic_phone:  t.clinic_phone
      }
    }
  end

  private

  def disabled?
    val = current_account.patient_portal_setting&.messaging&.dig('messaging_enabled')
    val == false
  end

  def render_disabled
    render_error('A clínica desabilitou o envio de mensagens pelo portal.',
                 status: :forbidden, code: 'messaging_disabled')
  end

  def render_no_contact
    render_error('Conta sem contato vinculado — fale com a clínica.',
                 status: :unprocessable_entity, code: 'no_contact')
  end

  def serialize_conversation(c)
    {
      id:           c.id,
      display_id:   c.display_id,
      status:       c.status,
      last_activity_at: c.last_activity_at,
      assignee:     c.assignee ? { id: c.assignee.id, name: c.assignee.name } : nil
    }
  end

  def serialize_message(m)
    {
      id:           m.id,
      content:      m.content,
      message_type: m.message_type, # 'incoming' = paciente · 'outgoing' = clínica
      sent_by_me:   m.message_type == 'incoming',
      created_at:   m.created_at,
      sender_name:  sender_label(m),
      urgent:       m.additional_attributes&.dig('urgent') == true
    }
  end

  def sender_label(m)
    case m.sender_type
    when 'User'    then m.sender&.name || 'Equipe da clínica'
    when 'Contact' then 'Você'
    else 'Sistema'
    end
  end

  def log!(action, message)
    PatientPortalAccessLog.log!(
      account: current_account, patient: current_patient,
      action: action, resource: message,
      ip: request.remote_ip, user_agent: request.user_agent,
      metadata: { message_id: message.id, conversation_id: message.conversation_id }
    )
  end
end
