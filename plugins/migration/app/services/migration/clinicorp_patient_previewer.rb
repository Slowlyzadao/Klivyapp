require 'csv'

module Migration
  # Read-only "what-would-happen-if-I-imported" analyzer for the patients
  # importer. Reuses the exact same parsing/mapping/match-and-merge logic as
  # `ClinicorpPatientImporter` so the preview is a faithful preview, not a
  # second implementation that drifts.
  #
  # Returns a hash:
  #   {
  #     summary: { total:, would_create:, would_update:, would_skip:, errors:, warnings: },
  #     rows: [{ line:, action:, name:, cpf:, clinicorp_id:, reason:, fields: {...} }, ...] (cap 100),
  #     anamneses: { total:, linked:, unlinked: } (only if anamnesis CSV provided),
  #     warnings: [ { line:, message: }, ... ] (cap 50)
  #   }
  class ClinicorpPatientPreviewer
    SAMPLE_LIMIT = 100
    WARNING_LIMIT = 50

    def initialize(account, patients_csv:, patient_anamnesis_csv: nil, anamnesis_csv: nil)
      @account = account
      @patients_csv = patients_csv
      @patient_anamnesis_csv = patient_anamnesis_csv
      @anamnesis_csv = anamnesis_csv
      # Reuse the importer's mapping helpers — we instantiate it but never
      # call `.call`, so nothing is persisted.
      @importer = ClinicorpPatientImporter.new(
        OpenStruct.new(account: account),
        patients_csv: patients_csv,
        patient_anamnesis_csv: patient_anamnesis_csv,
        anamnesis_csv: anamnesis_csv
      )
    end

    def call
      rows = parse_csv(@patients_csv)
      summary = { total: rows.size, would_create: 0, would_update: 0, would_skip: 0, errors: 0, warnings: 0 }
      sample = []
      warnings = []
      seen_clinicorp_keys = {} # for in-memory collision detection across the preview

      rows.each_with_index do |row, idx|
        line = idx + 2
        mapped = importer_call(:map_row, row)

        if mapped[:name].blank?
          summary[:would_skip] += 1
          summary[:errors] += 1
          push_sample(sample, line: line, action: 'skip', name: nil, mapped: mapped, reason: 'Nome em branco — linha será ignorada.')
          next
        end

        existing = importer_call(:find_existing_patient, mapped)
        action, reason = decide_action(existing, mapped)
        case action
        when 'create' then summary[:would_create] += 1
        when 'update' then summary[:would_update] += 1
        when 'skip'   then summary[:would_skip]   += 1
        end
        push_sample(sample, line: line, action: action, name: mapped[:name], mapped: mapped, reason: reason, existing: existing)

        next unless mapped[:clinicorp_id].present?

        keys = [mapped[:clinicorp_id], importer_call(:scientific_truncation, mapped[:clinicorp_id])].compact.uniq
        keys.each do |key|
          prev = seen_clinicorp_keys[key]
          if prev && prev != mapped[:clinicorp_id] && warnings.size < WARNING_LIMIT
            summary[:warnings] += 1
            warnings << { line: line, message: "Chave '#{key}' colide entre 2+ pacientes (precisão do Excel)." }
            seen_clinicorp_keys[key] = :collision
          else
            seen_clinicorp_keys[key] ||= mapped[:clinicorp_id]
          end
        end
      end

      result = { summary: summary, rows: sample, warnings: warnings }
      result[:anamneses] = preview_anamneses(seen_clinicorp_keys) if @anamnesis_csv.present?
      result
    end

    private

    # We don't want to copy/paste 100 lines of mapping logic. The importer
    # exposes the helpers as private methods; `send` is the simplest way to
    # reuse them without breaking encapsulation everywhere.
    def importer_call(method, *args)
      @importer.send(method, *args)
    end

    def parse_csv(content)
      str = content.to_s.sub(/\A\xEF\xBB\xBF/, '')
      delim = first_line_max_count(str)
      CSV.parse(str, headers: true, col_sep: delim, liberal_parsing: true).map(&:to_h)
    end

    def first_line_max_count(content)
      first_line = content.lines.first.to_s
      counts = { ',' => first_line.count(','), ';' => first_line.count(';'), "\t" => first_line.count("\t") }
      counts.max_by { |_, v| v }.first
    end

    # Mirrors `decide_merge` in the importer but returns ('create'|'update'|'skip', reason)
    # instead of mutating counters.
    def decide_action(existing, mapped)
      return ['create', nil] if existing.nil?

      existing_score = importer_call(:score_existing, existing)
      incoming_score = importer_call(:score_mapped, mapped)
      legacy_cleanup = importer_call(:legacy_pinned_to_migrate?, existing)

      if legacy_cleanup
        ['update', "Já existe paciente '#{existing.name}' (id=#{existing.id}). Vai mover pinned_note legado pra Observações."]
      elsif incoming_score > existing_score
        diff = describe_merge_diff(existing, mapped)
        ['update', "Já existe paciente '#{existing.name}' (id=#{existing.id}). #{diff}"]
      else
        ['skip', "Já existe paciente '#{existing.name}' (id=#{existing.id}) com mais ou igual informação."]
      end
    end

    def describe_merge_diff(existing, mapped)
      filled = ClinicorpPatientImporter::PATIENT_FIELDS.select do |f|
        existing.public_send(f).blank? && mapped[f].present?
      end
      filled << :address if existing.address.blank? && mapped[:address].present?
      filled << :insurance if existing.insurance.blank? && mapped[:insurance].present?
      return 'Será atualizado com novos dados.' if filled.empty?

      "Vai preencher campos vazios: #{filled.join(', ')}."
    end

    def push_sample(sample, line:, action:, name:, mapped:, reason: nil, existing: nil)
      return if sample.size >= SAMPLE_LIMIT

      sample << {
        line: line,
        action: action,
        name: name,
        cpf: mapped[:cpf],
        clinicorp_id: mapped[:clinicorp_id],
        existing_id: existing&.id,
        reason: reason,
        fields: {
          email: mapped[:email],
          phone: mapped[:phone],
          birthdate: mapped[:birthdate]&.iso8601,
          city: mapped.dig(:address, 'city'),
          insurance_plan: mapped.dig(:insurance, 'plan_name'),
          notes_preview: mapped[:notes].to_s.truncate(80)
        }.compact_blank
      }
    end

    def preview_anamneses(seen_clinicorp_keys)
      anamnesis_rows = parse_csv(@anamnesis_csv)
      total = anamnesis_rows.size
      linked = 0
      unlinked = 0
      anamnesis_rows.each do |row|
        patient_key = row['Patient_PersonId'].to_s.strip
        target = seen_clinicorp_keys[patient_key]
        if target.is_a?(String) # patient was matched
          linked += 1
        else
          unlinked += 1
        end
      end
      { total: total, linked: linked, unlinked: unlinked }
    rescue StandardError => e
      { total: 0, linked: 0, unlinked: 0, error: "#{e.class}: #{e.message}" }
    end
  end
end
