require 'csv'

module Migration
  class ClinicorpPatientImporter
    BATCH_SIZE = 250

    SEX_MAP = {
      'm' => 'masculino',
      'masc' => 'masculino',
      'masculino' => 'masculino',
      'f' => 'feminino',
      'fem' => 'feminino',
      'feminino' => 'feminino'
    }.freeze

    MARITAL_MAP = {
      'single'    => 'solteiro', 'solteiro' => 'solteiro', 'solteira' => 'solteiro',
      'married'   => 'casado',   'casado'   => 'casado',   'casada'   => 'casado',
      'divorced'  => 'divorciado', 'divorciado' => 'divorciado', 'divorciada' => 'divorciado',
      'widowed'   => 'viuvo',    'viuvo' => 'viuvo', 'viuva' => 'viuvo',
      'viúvo' => 'viuvo', 'viúva' => 'viuvo'
    }.freeze

    # Maps Clinicorp anamnesis question text → field on our Anamnesis model.
    # Anything not mapped here goes to `additional_notes` (observações
    # confidenciais), preserving the Q/A as a labeled line so a future reviewer
    # can read it. Compared loosely (case + accent insensitive substring match).
    ANAMNESIS_QUESTION_MAP = [
      { match: 'motivo da consulta',          field: :chief_complaint, kind: :text },
      { match: 'último tratamento odontoló',  field: :additional_notes, kind: :qa },
      { match: 'tratamento médico',           field: :medical_history,  kind: :jsonb_yn },
      { match: 'tomando algum medicamento',   field: :current_medications, kind: :jsonb_yn },
      { match: 'alergia a algum medicamento', field: :allergies,        kind: :jsonb_yn },
      { match: 'reação a anestesia',          field: :contraindications, kind: :jsonb_yn },
      { match: 'sensibilidade nos dentes',    field: :additional_notes, kind: :qa },
      { match: 'range os dentes',             field: :relevant_habits,  kind: :jsonb_yn },
      { match: 'rotina de higiene',           field: :additional_notes, kind: :qa },
      { match: 'usa fio dental',              field: :additional_notes, kind: :qa },
      { match: 'gengiva sangra',              field: :additional_notes, kind: :qa },
      { match: 'algum hábito',                field: :relevant_habits,  kind: :jsonb_yn },
      { match: 'fuma',                        field: :relevant_habits,  kind: :jsonb_yn },
      { match: 'diabético',                   field: :family_history,   kind: :text },
      { match: 'corta, sangra muito',         field: :medical_history,  kind: :jsonb_yn },
      { match: 'problema cardíaco',           field: :medical_history,  kind: :jsonb_yn },
      { match: 'dores de cabeça',             field: :additional_notes, kind: :qa },
      { match: 'desmaio',                     field: :medical_history,  kind: :jsonb_yn },
      { match: 'pressão arterial',            field: :medical_history,  kind: :jsonb_yn },
      { match: 'grávida',                     field: :pregnancy,        kind: :jsonb_yn }
    ].freeze

    def initialize(migration_run, patients_csv:, patient_anamnesis_csv: nil, anamnesis_csv: nil)
      @run = migration_run
      @patients_csv = patients_csv
      @patient_anamnesis_csv = patient_anamnesis_csv
      @anamnesis_csv = anamnesis_csv
      @account = migration_run.account
      @errors = []
      @counters = {
        created: 0, updated: 0, skipped: 0, errors: 0, processed: 0, warnings: 0,
        anamneses_created: 0, anamneses_skipped: 0, anamneses_errors: 0
      }
      # exact_clinicorp_id (string) → patient_id
      @clinicorp_id_to_patient = {}
    end

    def call
      patient_rows = parse_csv(@patients_csv)

      total = patient_rows.size
      total += 1 if @anamnesis_csv.present?  # one extra "step" for the anamnesis pass
      @run.update!(total_rows: total, processed_rows: 0)

      patient_rows.each_slice(BATCH_SIZE).with_index do |slice, batch_index|
        slice.each_with_index do |row, idx|
          line_number = (batch_index * BATCH_SIZE) + idx + 2
          process_row(row, line_number)
          @counters[:processed] += 1
        end
        flush_progress!
      end

      if @anamnesis_csv.present?
        process_anamneses!
        @counters[:processed] += 1
        flush_progress!
      end

      flush_progress!(final: true)
      @counters
    end

    private

    def parse_csv(content)
      str = content.to_s.sub(/\A\xEF\xBB\xBF/, '')
      delim = detect_delimiter(str)
      CSV.parse(str, headers: true, col_sep: delim, liberal_parsing: true).map(&:to_h)
    end

    def detect_delimiter(content)
      first_line = content.lines.first.to_s
      counts = { ',' => first_line.count(','), ';' => first_line.count(';'), "\t" => first_line.count("\t") }
      counts.max_by { |_, v| v }.first
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Patient pass
    # ─────────────────────────────────────────────────────────────────────────

    def process_row(row, line_number)
      mapped = map_row(row)

      if mapped[:name].blank?
        @counters[:skipped] += 1
        log_error(line_number, 'Nome em branco — linha ignorada.')
        return
      end

      patient = find_existing_patient(mapped)
      if patient
        decide_merge(patient, mapped, line_number)
      else
        patient = create_patient(mapped, line_number)
      end

      register_clinicorp_id(patient, mapped[:clinicorp_id], line_number) if patient && mapped[:clinicorp_id].present?
    rescue StandardError => e
      @counters[:errors] += 1
      log_error(line_number, "#{e.class}: #{e.message}")
    end

    def map_row(row)
      h = row.transform_keys { |k| k.to_s.strip.downcase.gsub(/\s+/, '') }
      pick = ->(canonical) { h[canonical.downcase] }

      birthdate = parse_date(pick.call('BirthDate'))
      sex = SEX_MAP[pick.call('Sex').to_s.strip.downcase]
      marital_status = MARITAL_MAP[pick.call('CivilStatus').to_s.strip.downcase]
      cpf = pick.call('OtherDocumentId').to_s.gsub(/\D/, '').then { |d| d.length == 11 ? d : nil }
      rg = pick.call('DocumentId')&.strip.presence

      # Notes from Clinicorp ('Notes' column) are clinical/medical history
      # ("Plano Odonto 300092714, nega problemas de saúde, toma puran t4..."),
      # so they go into the general `notes` field — NOT `pinned_note`, which
      # is the visually prominent sticky-note for short reminders only.
      # IndicationSource ("Como conheceu") is a separate flow already.
      notes = pick.call('Notes')&.strip.presence

      {
        name: pick.call('Name')&.strip,
        nickname: pick.call('NickName')&.strip,
        birthdate: birthdate,
        sex: sex,
        marital_status: marital_status,
        email: normalize_email(pick.call('Email')),
        phone: normalize_phone(pick.call('MobilePhone') || pick.call('Landline')),
        cpf: cpf,
        rg: rg,
        clinicorp_id: pick.call('id')&.to_s&.strip.presence,
        notes: notes,
        address: {
          'street' => pick.call('Address')&.strip,
          'number' => pick.call('AddressNumber')&.strip,
          'complement' => pick.call('AddressComplement')&.strip,
          'neighborhood' => pick.call('Neighborhood')&.strip,
          'city' => pick.call('City')&.strip,
          'state' => pick.call('state')&.strip,
          'zip_code' => normalize_zip(pick.call('Zip'))
        }.compact_blank,
        insurance: {
          'plan_name' => pick.call('insurancePlanName')&.strip,
          'plan_number' => pick.call('insurancePlanNumber')&.strip
        }.compact_blank,
        emergency_contact: emergency_from_person_in_charge(pick.call('PersonInCharge'))
      }.compact_blank
    end

    def emergency_from_person_in_charge(value)
      return nil if value.blank?

      { 'name' => value.to_s.strip }
    end

    def normalize_email(value)
      v = value.to_s.strip.downcase
      return nil if v.blank?
      return nil unless v.match?(URI::MailTo::EMAIL_REGEXP)

      v
    end

    def normalize_phone(value)
      digits = value.to_s.gsub(/\D/, '')
      return nil if digits.length < 8

      digits.start_with?('55') ? "+#{digits}" : "+55#{digits}"
    end

    def normalize_zip(value)
      digits = value.to_s.gsub(/\D/, '')
      digits.presence
    end

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def find_existing_patient(mapped)
      scope = Patient.where(account_id: @account.id, deleted_at: nil)
      if mapped[:cpf].present?
        by_cpf = scope.find_by(cpf: mapped[:cpf])
        return by_cpf if by_cpf
      end
      normalized = normalize_name(mapped[:name])
      return nil if normalized.blank?

      scope.where('LOWER(name) = ?', normalized).first
    end

    def normalize_name(name)
      name.to_s.strip.downcase
    end

    def decide_merge(existing, mapped, line_number)
      existing_score = score_existing(existing)
      incoming_score = score_mapped(mapped)
      needs_cleanup = legacy_pinned_to_migrate?(existing)
      # Re-import precisa popular `external_ids['clinicorp']` mesmo em
      # pacientes que já têm dados bons (caso contrário score-based skip
      # deixaria o id ausente). Sem isso, o vínculo do TreatmentOperation
      # importer (futuro) falha pra esses registros.
      missing_external_id = mapped[:clinicorp_id].present? &&
                            existing.external_ids.to_h['clinicorp'].to_s != mapped[:clinicorp_id].to_s

      if incoming_score > existing_score || needs_cleanup || missing_external_id
        existing.update!(merge_into_existing(existing, mapped))
        @counters[:updated] += 1
      else
        @counters[:skipped] += 1
        log_skip(line_number, "Já existe paciente '#{existing.name}' (id=#{existing.id}) com mais ou igual informação.")
      end
    end

    # Detects residue from the pre-fix importer: a Clinicorp-migrated patient
    # whose pinned_note holds clinical history (the old code dumped Notes
    # there). On re-import we move that content into notes and clear
    # pinned_note. Idempotent — once notes already contains the pinned text,
    # this returns false so re-running doesn't duplicate.
    def legacy_pinned_to_migrate?(existing)
      return false if existing.origin != 'migration_clinicorp'
      return false if existing.pinned_note.to_s.strip.blank?
      return false if existing.notes.to_s.include?(existing.pinned_note.to_s)

      true
    end

    PATIENT_FIELDS = %i[name email phone cpf rg birthdate sex marital_status].freeze

    def score_existing(patient)
      score = PATIENT_FIELDS.count { |f| patient.public_send(f).present? }
      score += jsonb_score(patient.address)
      score += jsonb_score(patient.insurance)
      score += jsonb_score(patient.emergency_contact)
      score
    end

    def score_mapped(mapped)
      score = PATIENT_FIELDS.count { |f| mapped[f].present? }
      score += jsonb_score(mapped[:address])
      score += jsonb_score(mapped[:insurance])
      score += jsonb_score(mapped[:emergency_contact])
      score
    end

    def jsonb_score(hash)
      return 0 if hash.blank?

      hash.values.count { |v| v.present? }
    end

    def merge_into_existing(existing, mapped)
      attrs = {}
      PATIENT_FIELDS.each do |f|
        attrs[f] = mapped[f] if existing.public_send(f).blank? && mapped[f].present?
      end
      attrs[:address] = (existing.address || {}).merge(mapped[:address] || {}) { |_k, old, new| old.presence || new }
      attrs[:insurance] = (existing.insurance || {}).merge(mapped[:insurance] || {}) { |_k, old, new| old.presence || new }
      if mapped[:emergency_contact].present?
        attrs[:emergency_contact] = (existing.emergency_contact || {}).merge(mapped[:emergency_contact]) { |_k, old, new| old.presence || new }
      end

      # Legacy cleanup: pinned_note populated by the pre-fix importer holds
      # clinical history that belongs in notes. Consolidate (dedup-aware) and
      # clear pinned_note so the sticky-note stops showing convênio info.
      if legacy_pinned_to_migrate?(existing)
        attrs[:notes] = [existing.notes, existing.pinned_note, mapped[:notes]].compact_blank.uniq.join("\n").presence
        attrs[:pinned_note] = nil
      elsif existing.notes.blank? && mapped[:notes].present?
        attrs[:notes] = mapped[:notes]
      end

      # Persist the Clinicorp id so future imports (TreatmentOperation,
      # Anamnesis follow-ups) can resolve patient links deterministically.
      # Re-import is idempotent: existing pacientes recebem a chave faltante.
      external_ids = with_clinicorp_external_id(existing.external_ids, mapped[:clinicorp_id])
      attrs[:external_ids] = external_ids if external_ids != existing.external_ids

      attrs
    end

    # Mescla `clinicorp_id` no JSONB sem sobrescrever IDs de outras origens
    # (BeClinic, Dentrix etc.). Retorna o hash original se nada muda — caller
    # usa essa identidade pra evitar UPDATE sem necessidade.
    def with_clinicorp_external_id(existing_jsonb, clinicorp_id)
      return existing_jsonb if clinicorp_id.blank?

      base = existing_jsonb.is_a?(Hash) ? existing_jsonb : {}
      return base if base['clinicorp'].to_s == clinicorp_id.to_s

      base.merge('clinicorp' => clinicorp_id.to_s)
    end

    def create_patient(mapped, line_number)
      patient = Patient.new(
        account_id: @account.id,
        name: mapped[:name],
        email: mapped[:email],
        phone: mapped[:phone],
        cpf: mapped[:cpf],
        rg: mapped[:rg],
        birthdate: mapped[:birthdate],
        sex: mapped[:sex],
        marital_status: mapped[:marital_status],
        address: mapped[:address] || {},
        insurance: mapped[:insurance] || {},
        emergency_contact: mapped[:emergency_contact] || {},
        notes: mapped[:notes],
        external_ids: with_clinicorp_external_id({}, mapped[:clinicorp_id]),
        origin: 'migration_clinicorp'
      )
      if patient.save
        @counters[:created] += 1
        return patient
      end

      @counters[:errors] += 1
      log_error(line_number, patient.errors.full_messages.join('; '))
      nil
    end

    # Indexes the patient by both the exact id and its scientific-notation
    # truncation so the anamnesis pass can resolve PatientAnamnesis rows that
    # only carry the truncated value (Excel mangles the 16-digit id).
    def register_clinicorp_id(patient, exact_id, line_number)
      key_exact = exact_id.to_s.strip
      return if key_exact.blank?

      keys = [key_exact, scientific_truncation(key_exact)].compact.uniq
      keys.each do |key|
        existing = @clinicorp_id_to_patient[key]
        if existing && existing != patient.id
          # Two different exact IDs collapsed to the same key. We KEEP the
          # first-seen mapping but flag both so the anamnesis pass can refuse
          # to link this key (collision detection).
          # This is a CSV precision artifact (Excel rounds 16-digit IDs to
          # scientific notation), not a real error — patients are imported
          # correctly. Only the anamnesis-to-patient link can't be resolved
          # for these specific patients.
          @clinicorp_id_to_patient[key] = :collision
          @counters[:warnings] += 1
          log_warning(line_number,
                      "Chave '#{key}' colide entre 2+ pacientes (Excel arredondou IDs longos). " \
                      'Pacientes importados normalmente; anamneses dessa chave ficam sem vínculo.')
        elsif !existing
          @clinicorp_id_to_patient[key] = patient.id
        end
      end
    end

    # Mimics Excel's scientific notation rounding for long IDs, so the
    # truncated string in the anamnesis CSVs ("5,02564E+15") matches what we
    # compute from Patient.csv's exact id ("5025635697819648"). Excel rounds
    # half-up to 5 decimal places (6 significant digits).
    def scientific_truncation(exact_id_str)
      digits = exact_id_str.to_s.gsub(/\D/, '')
      return nil if digits.length < 7

      exp = digits.length - 1
      first7 = digits[0, 7].to_i
      rounded6 = (first7 + 5) / 10  # half-up
      # Carry overflow (e.g. 9999995 → 1000000) bumps the exponent and re-pads.
      if rounded6 >= 1_000_000
        exp += 1
        rounded6 /= 10
      end
      str = format('%06d', rounded6)
      "#{str[0]},#{str[1, 5]}E+#{format('%02d', exp)}"
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Anamnesis pass
    # ─────────────────────────────────────────────────────────────────────────

    def process_anamneses!
      anamnesis_rows = parse_csv(@anamnesis_csv)
      pa_rows = @patient_anamnesis_csv.present? ? parse_csv(@patient_anamnesis_csv) : []

      # PatientAnamnesis.csv carries `AnamnesisId` already in Excel's truncated
      # scientific form (e.g. "4,64507E+15"); Anamnesis.csv carries the EXACT
      # 16-digit `id`. We index answers by the truncated string and convert
      # each anamnesis exact id to that same form when looking it up.
      answers_by_anamnesis_id = pa_rows.group_by { |r| r['AnamnesisId'].to_s.strip }

      anamnesis_rows.each do |row|
        exact_id     = row['id'].to_s.strip
        anamnesis_id = scientific_truncation(exact_id) || exact_id
        patient_key  = row['Patient_PersonId'].to_s.strip
        answers      = answers_by_anamnesis_id[anamnesis_id] || []

        result = build_and_persist_anamnesis(anamnesis_id, patient_key, answers)
        case result
        when :created  then @counters[:anamneses_created] += 1
        when :skipped  then @counters[:anamneses_skipped] += 1
        when :error    then @counters[:anamneses_errors]  += 1
        end
      end
    end

    def build_and_persist_anamnesis(anamnesis_id, patient_key, answers)
      patient_id_or_collision = @clinicorp_id_to_patient[patient_key]
      if patient_id_or_collision == :collision
        log_warning(anamnesis_id, "Anamnese sem vínculo — chave '#{patient_key}' aponta para 2+ pacientes (precisão do Excel).")
        return :skipped
      end
      if patient_id_or_collision.nil?
        log_warning(anamnesis_id, "Anamnese sem vínculo — paciente clinicorp_id='#{patient_key}' não foi importado (provavelmente pulado por nome em branco).")
        return :skipped
      end

      attrs = build_anamnesis_attributes(answers)

      Anamnesis.create!(
        account_id: @account.id,
        patient_id: patient_id_or_collision,
        status: 'finalized',
        finalized_at: Time.current,
        chief_complaint: attrs[:chief_complaint],
        family_history:  attrs[:family_history],
        additional_notes: attrs[:additional_notes],
        medical_history: attrs[:medical_history] || {},
        allergies:       attrs[:allergies] || [],
        current_medications: attrs[:current_medications] || [],
        relevant_habits: attrs[:relevant_habits] || {},
        contraindications: attrs[:contraindications] || [],
        pregnancy:       attrs[:pregnancy] || {}
      )
      :created
    rescue StandardError => e
      log_error(anamnesis_id, "Erro criando anamnese: #{e.class}: #{e.message}")
      :error
    end

    # Walks the rows belonging to one anamnesis and routes each Q/A into the
    # right field on our Anamnesis model. Unmapped questions accumulate into
    # additional_notes so nothing is silently lost.
    def build_anamnesis_attributes(answers)
      acc = {
        chief_complaint:     nil,
        family_history:      nil,
        additional_notes_lines: [],
        medical_history:     {},
        allergies:           [],
        current_medications: [],
        relevant_habits:     {},
        contraindications:   [],
        pregnancy:           {}
      }

      answers.each do |row|
        question = row['Question'].to_s.strip
        next if question.blank?

        answer_text = row['AnswerDescription'].to_s.strip
        answer_opt  = row['AnswerOption'].to_s.strip
        combined    = [answer_opt, answer_text].compact_blank.join(' — ').presence

        target = lookup_question_target(question)
        if target.nil?
          acc[:additional_notes_lines] << "#{question}: #{combined || '—'}"
          next
        end

        apply_to_field(acc, target, question, answer_opt, answer_text, combined)
      end

      {
        chief_complaint:     acc[:chief_complaint],
        family_history:      acc[:family_history],
        additional_notes:    acc[:additional_notes_lines].any? ? acc[:additional_notes_lines].join("\n") : nil,
        medical_history:     acc[:medical_history],
        allergies:           acc[:allergies],
        current_medications: acc[:current_medications],
        relevant_habits:     acc[:relevant_habits],
        contraindications:   acc[:contraindications],
        pregnancy:           acc[:pregnancy]
      }
    end

    def lookup_question_target(question)
      norm = normalize_text(question)
      ANAMNESIS_QUESTION_MAP.find { |m| norm.include?(normalize_text(m[:match])) }
    end

    def normalize_text(str)
      str.to_s.downcase
    end

    def apply_to_field(acc, target, question, answer_opt, answer_text, combined)
      case target[:field]
      when :chief_complaint
        acc[:chief_complaint] = [acc[:chief_complaint], answer_text.presence].compact.join(' | ').presence
      when :family_history
        acc[:family_history]  = [acc[:family_history], "#{question}: #{combined || '—'}"].compact.join("\n")
      when :additional_notes
        acc[:additional_notes_lines] << "#{question}: #{combined || '—'}"
      when :medical_history
        # jsonb hash: { "label" => { "yes" => true/false, "details" => "..." } }
        acc[:medical_history][question] = {
          'yes' => yes?(answer_opt),
          'details' => answer_text.presence
        }.compact
      when :allergies
        if yes?(answer_opt) || answer_text.present?
          acc[:allergies] << { 'description' => combined || question, 'severity' => 'unknown' }
        end
      when :current_medications
        if yes?(answer_opt) || answer_text.present?
          acc[:current_medications] << { 'name' => answer_text.presence || 'Não informado' }
        end
      when :relevant_habits
        acc[:relevant_habits][question] = combined || (yes?(answer_opt) ? 'sim' : 'não')
      when :contraindications
        if yes?(answer_opt) || answer_text.present?
          acc[:contraindications] << (combined || question)
        end
      when :pregnancy
        acc[:pregnancy] = { 'is_pregnant' => yes?(answer_opt), 'details' => answer_text.presence }.compact
      end
    end

    def yes?(answer_opt)
      answer_opt.to_s.strip.downcase.in?(%w[sim yes true 1 s])
    end

    # ─────────────────────────────────────────────────────────────────────────
    # Progress / logging
    # ─────────────────────────────────────────────────────────────────────────

    def flush_progress!(final: false)
      @run.update_columns(
        processed_rows: @counters[:processed],
        created_count: @counters[:created] + @counters[:anamneses_created],
        updated_count: @counters[:updated],
        skipped_count: @counters[:skipped] + @counters[:anamneses_skipped],
        error_count: @counters[:errors] + @counters[:anamneses_errors],
        errors_log: @errors.last(200),
        updated_at: Time.current
      )
    end

    def log_error(line, message)
      @errors << { line: line, level: 'error', message: message }
    end

    def log_warning(line, message)
      @errors << { line: line, level: 'warning', message: message }
    end

    def log_skip(line, message)
      @errors << { line: line, level: 'info', message: message }
    end
  end
end
