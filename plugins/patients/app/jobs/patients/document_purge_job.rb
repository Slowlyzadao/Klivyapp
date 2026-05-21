# plugins/patients/app/jobs/patients/document_purge_job.rb
#
# Purga definitiva de Document soft-deleted após o período de retenção.
# Espelha o padrão de Patients::ExamMediaPurgeJob.
#
# Idempotente: se o record já foi destruído ou restaurado, no-op silencioso.

module Patients
  class DocumentPurgeJob < ApplicationJob
    queue_as :patients

    sidekiq_options retry: 3, dead: true

    def perform(document_id)
      document = ::Document.where.not(deleted_at: nil).find_by(id: document_id)
      return unless document # já foi destruído manualmente OU restaurado

      document.file.purge_later if document.file.attached?
      document.destroy!
      Rails.logger.info("[Patients::DocumentPurgeJob] purged document=#{document_id}")
    end
  end
end
