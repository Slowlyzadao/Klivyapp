module AiAgent
  module Health
    # Cron a cada 10min. Pega snapshot via Checker e delega pro Notifier
    # — toda a lógica de dedup, decisão de status e canal vive lá.
    # Este job é só o entry point assíncrono.
    class MonitorJob < ApplicationJob
      queue_as :scheduled_jobs

      def perform
        snapshot = AiAgent::Health::Checker.call
        return if snapshot.alerts.empty?

        AiAgent::Health::Notifier.call(snapshot)
      end
    end
  end
end
