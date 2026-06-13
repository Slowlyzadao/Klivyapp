# Executa de fato um pedido LGPD de eliminação de dados (art. 18 VI).
#
# Esta classe NÃO é chamada pela Bea — ela existe pro humano aprovar
# depois de validar identidade do paciente. A Bea só abre o ticket
# (ver `AiAgent::Tools::ErasureRequestTool`, decisão D-23).
#
# Apaga apenas dados sob responsabilidade da Bea (memória, traces,
# feedback, estado de conversa). **NÃO toca em `Patient` nem
# `PatientAuditLog`** — esses ficam preservados por exigência CFM
# 1.821/2007 (prontuário 20 anos). Quem quiser apagar prontuário
# precisa fazer pela área clínica, não por aqui.
#
# Retorna um Hash `{ ok: true, counts: { ... }, executed_at: ... }`
# com o que foi apagado, pra registro em audit log.
#
# Uso:
#
#   result = AiAgent::Lgpd::ErasureExecutor.call(
#     account_id: 1,
#     contact_id: 42,
#     actor: current_user,        # opcional, vai pro audit log
#     reason: 'Aprovado em ticket #123'
#   )
class AiAgent::Lgpd::ErasureExecutor
  Result = Struct.new(:ok, :counts, :executed_at, :error, keyword_init: true) do
    def to_h
      { ok: ok, counts: counts, executed_at: executed_at&.iso8601, error: error }.compact
    end
  end

  def self.call(account_id:, contact_id:, actor: nil, reason: nil)
    new(account_id: account_id, contact_id: contact_id, actor: actor, reason: reason).call
  end

  def initialize(account_id:, contact_id:, actor: nil, reason: nil)
    @account_id = account_id
    @contact_id = contact_id
    @actor = actor
    @reason = reason
  end

  def call
    counts = {}

    ActiveRecord::Base.transaction do
      counts[:patient_memories] = destroy_patient_memories
      counts[:traces]            = destroy_traces
      counts[:feedbacks]         = destroy_feedbacks
      counts[:conversation_states] = destroy_conversation_states
    end

    record_audit(counts)
    Result.new(ok: true, counts: counts, executed_at: Time.current)
  rescue StandardError => e
    Rails.logger.error("[AiAgent::Lgpd::ErasureExecutor] account=#{@account_id} contact=#{@contact_id} falhou: #{e.class}: #{e.message}")
    Result.new(ok: false, error: "#{e.class}: #{e.message}")
  end

  private

  def destroy_patient_memories
    AiAgent::PatientMemory.where(account_id: @account_id, contact_id: @contact_id).destroy_all.size
  end

  def destroy_traces
    AiAgent::Trace.where(account_id: @account_id, contact_id: @contact_id).delete_all
  end

  def destroy_feedbacks
    return 0 unless defined?(AiAgent::Feedback)

    AiAgent::Feedback.where(account_id: @account_id, contact_id: @contact_id).delete_all
  end

  # ConversationState fica vinculado a `conversation_id`, não `contact_id`.
  # Precisamos descobrir as conversas do contato e apagar estados delas.
  def destroy_conversation_states
    conv_ids = ::Conversation.where(account_id: @account_id, contact_id: @contact_id).pluck(:id)
    return 0 if conv_ids.empty?

    AiAgent::ConversationState.where(account_id: @account_id, conversation_id: conv_ids).delete_all
  end

  def record_audit(counts)
    return unless defined?(AiAgent::AuditLog)

    AiAgent::AuditLog.record(
      scope: 'account',
      action: 'lgpd_erasure_executed',
      account_id: @account_id,
      actor: @actor,
      ip: nil,
      changes: {
        contact_id: @contact_id,
        counts: counts,
        reason: @reason.to_s.strip[0, 500],
        executed_at: Time.current.iso8601
      }
    )
  end
end
