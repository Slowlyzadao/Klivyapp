# Cron diário (14h SP) — DESPACHANTE. Enfileira 1
# `ProactiveOutreachPerAccountJob` por conta com Bea habilitada.
# A lógica real (RecallFinder + envio + memória update) vive no
# PerAccountJob.
#
# ESC-3 (auditoria 2026-05-18): antes esse cron processava contas
# sequencialmente. Agora Sidekiq paraleliza N workers.
#
# Constantes mantidas neste arquivo pra preservar API externa.
#
# Limitações conhecidas (do design original):
#   - WhatsApp tem janela de 24h fora da qual só template pré-aprovado
#     pode ser enviado. Se o paciente está fora da janela, o envio
#     falha — em piloto isso é aceitável; em produção a Sprint H/I
#     deve adicionar registro de templates Business.
#   - Job é idempotente por dia: se já rodou hoje pra mesma conta,
#     re-rodar não reenfileira ninguém (RecallFinder filtra cooldown).
class AiAgent::ProactiveOutreachJob < ApplicationJob
  queue_as :scheduled_jobs

  DAILY_PER_ACCOUNT_CAP = 30
  RECALL_MESSAGE_KEY = 'last_recall_at'.freeze

  def perform
    account_ids = AiAgent::AccountSetting.where(enabled: true).pluck(:account_id)
    return if account_ids.empty?

    Rails.logger.info(
      "[AiAgent::ProactiveOutreachJob] dispatching #{account_ids.size} per-account jobs"
    )

    account_ids.each do |account_id|
      AiAgent::ProactiveOutreachPerAccountJob.perform_later(account_id)
    end
  end
end
