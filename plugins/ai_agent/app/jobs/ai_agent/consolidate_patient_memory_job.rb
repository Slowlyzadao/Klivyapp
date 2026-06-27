# Cron noturno (4h SP) — DESPACHANTE. Enfileira 1
# `ConsolidatePatientMemoryPerAccountJob` por conta com Bea habilitada.
# A lógica real (Distiller + merge prefs + purge TTL 12m) vive no
# PerAccountJob.
#
# ESC-2 (auditoria 2026-05-18): antes esse cron processava contas
# sequencialmente, gastando ~3s LLM × pacientes × contas. Em 1000
# contas excedia a janela noturna. Agora Sidekiq paraleliza N workers.
#
# Constantes mantidas neste arquivo pra preservar API externa
# (`AiAgent::ConsolidatePatientMemoryJob::DAILY_CAP_PER_ACCOUNT` etc).
class AiAgent::ConsolidatePatientMemoryJob < ApplicationJob
  queue_as :scheduled_jobs

  DAILY_CAP_PER_ACCOUNT = 100
  MIN_HISTORY_ENTRIES = 5
  ACTIVE_WINDOW = 24.hours
  RECONSOLIDATE_AFTER = 23.hours
  PURGE_TTL = 12.months

  def perform
    account_ids = AiAgent::AccountSetting.where(enabled: true).pluck(:account_id)
    return if account_ids.empty?

    Rails.logger.info(
      "[AiAgent::ConsolidatePatientMemoryJob] dispatching #{account_ids.size} per-account jobs"
    )

    account_ids.each do |account_id|
      AiAgent::ConsolidatePatientMemoryPerAccountJob.perform_later(account_id)
    end
  end
end
