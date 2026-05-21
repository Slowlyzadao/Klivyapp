# plugins/patients/app/jobs/patients/expire_consent_records_job.rb
#
# Detecta consentimentos vencidos (`expires_at < now`) que ainda estão em
# status ativo e marca-os como `vencido`, emitindo evento `consent_expired`
# na timeline do paciente.
#
# Roda diariamente (config/schedule.yml). Idempotente: se um consent já está
# vencido/revogado, é ignorado.

module Patients
  class ExpireConsentRecordsJob < ApplicationJob
    queue_as :scheduled_jobs

    sidekiq_options retry: 3

    # Status que ainda permitem expiração natural (assinados não revogados).
    # Backfill legacy → `signed` rodado em 2026-05-04 — `EXPIRABLE_STATUSES`
    # contém apenas o status canônico.
    EXPIRABLE_STATUSES = %w[signed].freeze

    def perform
      now = Time.current
      scope = ::ConsentRecord
              .where(status: EXPIRABLE_STATUSES)
              .where('expires_at IS NOT NULL AND expires_at < ?', now)

      count = 0
      scope.find_each(batch_size: 200) do |consent|
        # Defensive double-check (race com outro worker)
        next unless EXPIRABLE_STATUSES.include?(consent.status)
        next if consent.expires_at.nil? || consent.expires_at >= now

        ActiveRecord::Base.transaction do
          consent.update_columns(status: 'vencido', updated_at: now)

          PatientTimelineEvent.record!(
            patient: consent.patient,
            account: consent.account,
            event_type: 'consent_expired',
            label: "Consentimento vencido: #{consent.title.presence || consent.consent_type}",
            actor: nil, # automático, sem ator humano
            reference: consent,
            occurred_at: consent.expires_at
          )
        end
        count += 1
      end

      Rails.logger.info("[Patients::ExpireConsentRecordsJob] expired=#{count} at=#{now.iso8601}")
      count
    end
  end
end
