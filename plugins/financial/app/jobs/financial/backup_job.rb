module Financial
  # Cron diário às 03:00 UTC — gera dump do banco e aplica retenção.
  # Canon F-32 §"Cron diário às 03:00".
  #
  # Configurado em `config/schedule.yml` (sidekiq-cron). Também pode ser
  # disparado manualmente via UI (botão "Backup agora" em v2 · Backups).
  class BackupJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      result = Financial::CreateBackup.call
      if result.success?
        Rails.logger.info(
          "[Financial::BackupJob] OK path=#{result.path} size=#{result.size_bytes}B " \
          "duration=#{result.duration_seconds}s pruned=#{result.pruned_count}"
        )
      else
        Rails.logger.error("[Financial::BackupJob] falha: #{result.error}")
        # TODO canon F-32: notificar ADMIN se backup falhar. Por enquanto
        # registramos no log (Sentry/AppSignal capturam o erro).
      end
    end
  end
end
