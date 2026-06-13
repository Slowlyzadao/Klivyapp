# Cron a cada 1 min — DESPACHANTE. Enfileira 1
# `FollowUpDispatcherPerAccountJob` por conta com pelo menos 1 rule
# habilitada. A lógica real (CandidateFinder + cooldown + criação de
# Execution) vive no PerAccountJob.
#
# ESC-1 (auditoria 2026-05-18): antes esse cron processava todas as
# rules globais sequencialmente. Em escala (1000+ tenants), execução
# excedia o intervalo de 1 minuto e backlog acumulava. Agora despacha
# N jobs paralelos (1 por conta) e Sidekiq paraleliza.
#
# Constantes mantidas neste arquivo (vs movidas pro PerAccountJob)
# pra preservar pontos de extensão pro frontend de configuração que
# referencia `AiAgent::FollowUpDispatcherJob::MAX_PER_ACCOUNT_PER_RUN`.
class AiAgent::FollowUpDispatcherJob < ApplicationJob
  queue_as :scheduled_jobs

  MAX_PER_ACCOUNT_PER_RUN = 200

  # Janela mínima entre 2 follow-ups pra um mesmo contato. Sem isso,
  # múltiplas regras overlapping (pré-consulta + recall + lembrete +
  # pesquisa + reativação) podem mandar 5 mensagens em sequência.
  # Conservador por design — paciente recebe no máximo 1 follow-up
  # automático a cada 2h.
  PER_CONTACT_COOLDOWN = 2.hours

  def perform
    account_ids = AiAgent::FollowUpRule.enabled.distinct.pluck(:account_id)
    return if account_ids.empty?

    Rails.logger.info(
      "[AiAgent::FollowUpDispatcherJob] dispatching #{account_ids.size} per-account jobs"
    )

    account_ids.each do |account_id|
      AiAgent::FollowUpDispatcherPerAccountJob.perform_later(account_id)
    end
  end
end
