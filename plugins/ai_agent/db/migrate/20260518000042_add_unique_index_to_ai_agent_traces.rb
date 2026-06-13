class AddUniqueIndexToAiAgentTraces < ActiveRecord::Migration[7.1]
  # Race condition: dois jobs do ChatResponseJob podem rodar em paralelo
  # pra mesma mensagem (retry do Sidekiq, ou listener disparado 2x). Antes
  # da idempotência ser feita só com SELECT, ambos podiam criar Traces
  # duplicados. Este índice único parcial garante no nível do banco que
  # uma message só tem 1 Trace bem-sucedido (error_message IS NULL).
  # Traces com erro podem coexistir — eles existem pra auditar tentativas
  # falhas e não devem bloquear retry.
  def change
    add_index :ai_agent_traces, :message_id,
              unique: true,
              where: 'message_id IS NOT NULL AND error_message IS NULL',
              name: 'idx_ai_agent_traces_unique_message_success'
  end
end
