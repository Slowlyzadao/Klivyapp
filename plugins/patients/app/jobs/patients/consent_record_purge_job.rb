# plugins/patients/app/jobs/patients/consent_record_purge_job.rb
#
# Purga definitiva de ConsentRecord soft-deleted após o período de retenção.
# Apaga o blob da assinatura digital armazenado no R2 + destrói record.
#
# Idempotente: se o record já foi destruído ou restaurado, no-op silencioso.

module Patients
  class ConsentRecordPurgeJob < ApplicationJob
    queue_as :patients

    sidekiq_options retry: 3, dead: true

    def perform(consent_record_id)
      consent = ::ConsentRecord.where.not(deleted_at: nil).find_by(id: consent_record_id)
      return unless consent # já foi destruído manualmente OU restaurado

      consent.signature_image.purge_later if consent.signature_image.attached?
      consent.destroy!
      Rails.logger.info("[Patients::ConsentRecordPurgeJob] purged consent_record=#{consent_record_id}")
    end
  end
end
