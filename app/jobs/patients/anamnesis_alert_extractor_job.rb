# app/jobs/patients/anamnesis_alert_extractor_job.rb
#
# Job assíncrono para processamentos pesados após finalização da anamnese.
# Executado em background pelo Sidekiq após AnamnesisFinalizerService.

module Patients
  class AnamnesisAlertExtractorJob < ApplicationJob
    queue_as :patients

    # Sidekiq options
    sidekiq_options retry: 3, dead: false

    def perform(anamnesis_id)
      anamnesis = Anamnesis.find_by(id: anamnesis_id)
      return unless anamnesis

      # Placeholder para integrações futuras (ex: CID-10 lookup, interações de medicamentos)
      Rails.logger.info("[AnamnesisAlertExtractorJob] Processado: anamnese ##{anamnesis_id}")
    end
  end
end
