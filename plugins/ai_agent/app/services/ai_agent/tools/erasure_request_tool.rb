# LGPD art. 18 VI — direito de eliminação dos dados pessoais.
#
# Decisão D-23 do plano: Bea NÃO apaga dados sozinha. Em vez disso:
#   1. Registra um AuditLog com escopo `erasure_request`
#   2. Cria uma nota interna prioridade alta na conversa (notify_staff)
#   3. Devolve confirmação pro paciente com prazo legal de 15 dias
#
# Razão: destruição de dados é ação irreversível com impacto regulatório
# (CFM exige retenção de prontuário 20 anos). Decisão técnica do humano,
# não do LLM. Bea só abre o ticket e direciona pro responsável.
#
# Quando a equipe humana aprovar o pedido, executa-se via:
#
#   AiAgent::Lgpd::ErasureExecutor.call(
#     account_id: ..., contact_id: ..., actor: current_user, reason: 'Ticket #X'
#   )
#
# O executor apaga PatientMemory, Trace, Feedback e ConversationState do
# contato. `Patient` (prontuário) NÃO é apagado — CFM 1.821/2007 manda
# manter por 20 anos.
class AiAgent::Tools::ErasureRequestTool < AiAgent::Tools::BaseTool
  description <<~DESC
    Registra um pedido formal de exclusão de dados pessoais do paciente
    (LGPD art. 18 VI). Use quando o paciente disser claramente que quer
    apagar seus dados, ser esquecido, deletar conta/cadastro, exercer
    direito ao esquecimento.

    IMPORTANTE: esta tool NÃO apaga nada automaticamente. Ela registra
    o pedido em auditoria e abre ticket interno pra equipe responsável.
    Resposta padrão: "Seu pedido foi registrado. Por exigência legal
    (CFM), parte do prontuário precisa ser retida — a equipe responsável
    vai te explicar em até 15 dias úteis quais dados podem ser apagados
    e quais precisam permanecer."

    Use APENAS quando o paciente pedir explicitamente. Não infira de
    frustração ou pedido de cancelamento de consulta.
  DESC

  param :reason,
        type: :string,
        required: false,
        desc: 'Texto curto descrevendo o motivo do pedido (parafrase do que o paciente disse). Pode ficar vazio se não há motivo declarado.'

  param :scope,
        type: :string,
        required: false,
        desc: 'Escopo do pedido percebido: "all" (apagar tudo), "contact_only" (só dados de contato/marketing), "specific" (algo específico mencionado). Default: "all".'

  def execute(reason: '', scope: 'all')
    return { recorded: false, error: 'Paciente não vinculado a esta conversa.' } if contact_id.blank?

    # SEC-13 (defesa em profundidade): contact_id vem do tool context, não
    # de argumento LLM (BaseTool#contact_id lê context.contact_id —
    # ChatService injeta), então o LLM não consegue passar contact_id
    # arbitrário. Mas defendemos contra contexto corrompido (contact
    # deletado, reatribuído a outra conta): exige que Contact realmente
    # exista e pertença ao mesmo account da conversa antes de registrar
    # pedido de erasure. Erasure é ação regulatória — não pode rodar com
    # contact_id órfão ou cross-tenant.
    return { recorded: false, error: 'Paciente não pôde ser validado.' } unless contact_belongs_to_account?

    scope_normalized = %w[all contact_only specific].include?(scope.to_s) ? scope.to_s : 'all'

    # Registra na trilha de auditoria (append-only). Usa escopo
    # `account` por reaproveitamento da taxonomia existente — o
    # discriminador é `action: lgpd_erasure_requested` no changes.
    if defined?(AiAgent::AuditLog)
      AiAgent::AuditLog.record(
        scope: 'account',
        action: 'lgpd_erasure_requested',
        account_id: account.id,
        actor: nil,
        ip: nil,
        changes: {
          contact_id: contact_id,
          conversation_id: conversation_state&.conversation_id,
          scope: scope_normalized,
          reason: reason.to_s.strip[0, 500],
          opened_at: Time.current.iso8601,
          source: 'bea_chat'
        }
      )
    end

    # Notify staff — privada, alta prioridade. Equipe verá no painel
    # da conversa antes do humano assumir.
    post_internal_note(scope_normalized, reason)

    patient_memory&.append_history(
      event_type: 'erasure_requested',
      summary: "Pedido de exclusão de dados (escopo: #{scope_normalized})",
      metadata: { reason: reason.to_s.strip[0, 200], scope: scope_normalized }
    )

    {
      recorded: true,
      scope: scope_normalized,
      message_for_patient: 'Seu pedido de exclusão de dados foi registrado e vai ser tratado por uma pessoa da nossa equipe. Por exigência legal (CFM 1.821/2007), parte do prontuário precisa ser mantida em arquivo. A equipe vai te retornar em até 15 dias úteis explicando exatamente o que pode ser apagado e o que precisa ser preservado, conforme a LGPD.',
      handoff_required: true
    }
  rescue StandardError => e
    Rails.logger.error("[AiAgent::ErasureRequestTool] falhou: #{e.class}: #{e.message}")
    { recorded: false, error: 'Não foi possível registrar o pedido. Vou avisar a equipe pra te ajudar manualmente.' }
  end

  private

  def contact_belongs_to_account?
    return false unless defined?(::Contact)

    ::Contact.exists?(id: contact_id, account_id: account.id)
  end

  def post_internal_note(scope, reason)
    state = conversation_state
    return unless state

    conversation = ::Conversation.find_by(id: state.conversation_id, account_id: account.id)
    return unless conversation

    body = "🔒 [Bea — LGPD] Paciente solicitou exclusão de dados (escopo: #{scope})."
    body += " Motivo: \"#{reason.to_s.strip[0, 300]}\"" if reason.to_s.strip.present?
    body += ' Procedimento: validar identidade, identificar dados retidos por exigência CFM (prontuário 20 anos), retornar ao paciente em até 15 dias úteis com plano de execução.'

    conversation.messages.create!(
      message_type: :outgoing,
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      sender: AiAgent::AgentBotIdentity.ensure!,
      private: true,
      content: body
    )
  end
end
