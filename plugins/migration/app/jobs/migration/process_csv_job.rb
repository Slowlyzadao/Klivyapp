module Migration
  class ProcessCsvJob < ApplicationJob
    queue_as :low

    # csv_payload pode ser:
    #   - String (legado: arquivo único — ainda usado por agenda)
    #   - Hash com :patients, :patient_anamnesis, :anamnesis (kind=patients novo)
    def perform(migration_run_id, csv_payload)
      run = MigrationRun.find(migration_run_id)
      run.mark_processing!

      case run.kind
      when 'patients'
        payload = normalize_patients_payload(csv_payload)
        Migration::ClinicorpPatientImporter.new(
          run,
          patients_csv: payload[:patients],
          patient_anamnesis_csv: payload[:patient_anamnesis],
          anamnesis_csv: payload[:anamnesis]
        ).call
      when 'agenda'
        Migration::ClinicorpAgendaImporter.new(run, csv_payload).call
      else
        raise NotImplementedError, "Importer for kind=#{run.kind} not implemented yet"
      end

      run.reload
      run.mark_completed!
    rescue StandardError => e
      Rails.logger.error("[Migration::ProcessCsvJob] failed for run=#{migration_run_id}: #{e.class}: #{e.message}")
      run&.mark_failed!("#{e.class}: #{e.message}")
      raise
    end

    private

    def normalize_patients_payload(payload)
      return { patients: payload, patient_anamnesis: nil, anamnesis: nil } if payload.is_a?(String)

      h = payload.deep_symbolize_keys
      { patients: h[:patients], patient_anamnesis: h[:patient_anamnesis], anamnesis: h[:anamnesis] }
    end
  end
end
