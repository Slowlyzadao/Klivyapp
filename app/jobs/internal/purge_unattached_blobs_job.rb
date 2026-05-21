# app/jobs/internal/purge_unattached_blobs_job.rb
#
# Garbage collector mensal de ActiveStorage::Blob órfãos.
#
# "Órfão" aqui = blob criado e nunca attached a nenhum record (drafts abortados,
# uploads cancelados pelo browser, criação interrompida no meio). NÃO é o caso
# de blobs cujo attachment foi destroyed — esses são purgados pelos jobs
# específicos por domínio (DocumentPurgeJob, ConsentRecordPurgeJob, etc.).
#
# Janela de segurança: blobs criados há menos de 24h ficam (podem estar em
# transação aberta de upload). Conservador para evitar apagar algo em
# upload-in-progress.
#
# Agendado em config/schedule.yml — primeiro dia do mês, 04h UTC.

module Internal
  class PurgeUnattachedBlobsJob < ApplicationJob
    queue_as :housekeeping

    SAFETY_WINDOW = 24.hours

    def perform
      cutoff = SAFETY_WINDOW.ago
      scope = ActiveStorage::Blob.unattached.where('created_at < ?', cutoff)

      total = scope.count
      Rails.logger.info("[PurgeUnattachedBlobsJob] candidatos: #{total} blobs (criados antes de #{cutoff})")

      purged = 0
      scope.find_each do |blob|
        blob.purge_later
        purged += 1
      end

      Rails.logger.info("[PurgeUnattachedBlobsJob] enfileirou #{purged} purges")
    end
  end
end
