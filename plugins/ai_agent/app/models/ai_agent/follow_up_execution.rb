# Audit + idempotência de cada follow-up disparado. O dispatcher cria
# a row em `pending`, o sender promove pra `sent` (ou `skipped`/
# `failed`). O índice único garante que mesmo (rule + alvo + horário)
# nunca rode duas vezes — cron duplo, retry, click duplo de operador
# caem no mesmo lugar.
class AiAgent::FollowUpExecution < ApplicationRecord
  self.table_name = 'ai_agent_follow_up_executions'

  STATUSES = %w[pending sent skipped failed].freeze

  belongs_to :account
  belongs_to :rule, class_name: 'AiAgent::FollowUpRule', inverse_of: :executions
  # Passo da cadência que originou a execução. Nil quando o disparo veio
  # do passo 1 (a própria regra) — sem FK constraint pra preservar o
  # histórico mesmo se o passo for removido depois.
  belongs_to :step, class_name: 'AiAgent::FollowUpStep', optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :target_at, presence: true

  scope :pending, -> { where(status: 'pending') }
  scope :sent, -> { where(status: 'sent') }
end
