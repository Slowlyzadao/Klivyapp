module Migration
  class ProcessCsvJob < ApplicationJob
    queue_as :low

    # csv_payload pode ser:
    #   - String (legado: arquivo único — ainda usado por agenda)
    #   - Hash com :patients, :patient_anamnesis, :anamnesis (kind=patients novo)
    #   - Hash com :operations, :dentist_mapping (kind=treatment_operations)
    #   - Hash com :budgets, :payment_headers, :payment_items, :dentist_mapping,
    #     :bank_account_strategy (kind=financial — F-10)
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
      when 'treatment_operations'
        payload = normalize_operations_payload(csv_payload)
        Migration::ClinicorpTreatmentOperationImporter.new(
          run,
          operations_csv: payload[:operations],
          dentist_mapping: payload[:dentist_mapping] || {}
        ).call
      when 'financial'
        payload = normalize_financial_payload(csv_payload)
        Migration::ClinicorpFinancialImporter.new(
          run,
          budgets_csv: payload[:budgets],
          payment_headers_csv: payload[:payment_headers],
          payment_items_csv: payload[:payment_items],
          dentist_mapping: payload[:dentist_mapping] || {},
          bank_account_strategy: payload[:bank_account_strategy] || 'create',
          bank_account_id: payload[:bank_account_id],
          payment_method_mapping: payload[:payment_method_mapping] || {},
          specialty_mapping: payload[:specialty_mapping] || {}
        ).call
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

    def normalize_operations_payload(payload)
      h = payload.is_a?(Hash) ? payload.deep_symbolize_keys : { operations: payload }
      # `dentist_mapping` chega do controller como Hash de strings — preservamos
      # como veio (importer não exige symbol keys nas chaves do mapping).
      mapping = h[:dentist_mapping]
      mapping = mapping.transform_keys(&:to_s) if mapping.is_a?(Hash)
      { operations: h[:operations], dentist_mapping: mapping }
    end

    def normalize_financial_payload(payload)
      h = payload.is_a?(Hash) ? payload.deep_symbolize_keys : {}
      mapping = h[:dentist_mapping]
      mapping = mapping.transform_keys(&:to_s) if mapping.is_a?(Hash)
      pm_mapping = h[:payment_method_mapping]
      pm_mapping = pm_mapping.transform_keys(&:to_s) if pm_mapping.is_a?(Hash)
      sp_mapping = h[:specialty_mapping]
      sp_mapping = sp_mapping.transform_keys(&:to_s) if sp_mapping.is_a?(Hash)
      {
        budgets: h[:budgets],
        payment_headers: h[:payment_headers],
        payment_items: h[:payment_items],
        dentist_mapping: mapping,
        bank_account_strategy: h[:bank_account_strategy],
        bank_account_id: h[:bank_account_id],
        payment_method_mapping: pm_mapping,
        specialty_mapping: sp_mapping
      }
    end
  end
end
