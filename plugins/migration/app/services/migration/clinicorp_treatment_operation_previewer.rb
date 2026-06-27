require 'csv'

module Migration
  # "What-would-happen-if-I-imported-this" do `TreatmentOperation.xlsx`.
  # Reusa parsing/mapping/lookup do importer (ZERO duplicação) — só decide o
  # *action* (create/update/skip) sem tocar no banco.
  #
  # MUST stay in sync com `ClinicorpTreatmentOperationImporter#process_row`.
  # A lição aprendida em [1.5.2.9] (preview de pacientes mentindo sobre o que
  # ia acontecer) vale aqui também — qualquer condição nova que mude action no
  # importer precisa virar action equivalente aqui.
  #
  # Retorno:
  #   {
  #     summary: { total:, would_create_session:, would_update_session:,
  #                would_create_item:, would_update_item:, would_skip:,
  #                errors:, warnings: },
  #     rows: [{ line:, action:, name:, procedure:, dentist:, reason:, ... }] (cap 100),
  #     warnings: [ { line:, message: } ] (cap 50),
  #     dentists: [{ id:, name:, count:, mapped: bool }, ...] (todos os dentistas distintos)
  #   }
  class ClinicorpTreatmentOperationPreviewer
    SAMPLE_LIMIT = 100
    WARNING_LIMIT = 50

    def initialize(account, operations_csv:, dentist_mapping: {})
      @account = account
      @operations_csv = operations_csv
      @dentist_mapping = (dentist_mapping || {}).transform_keys(&:to_s)
      @importer = ClinicorpTreatmentOperationImporter.new(
        OpenStruct.new(account: account),
        operations_csv: operations_csv,
        dentist_mapping: @dentist_mapping
      )
      # Force preload do índice de pacientes (importer expõe via send).
      @importer.send(:preload_patient_index!)
      preload_existing_operation_ids!
    end

    def call
      rows = parse_csv(@operations_csv)
      summary = {
        total: rows.size,
        would_create_session: 0,
        would_update_session: 0,
        would_create_item: 0,
        would_update_item: 0,
        would_skip: 0,
        errors: 0,
        warnings: 0
      }
      sample = []
      warnings = []
      dentist_counts = Hash.new { |h, k| h[k] = { id: nil, name: nil, count: 0 } }

      rows.each_with_index do |row, idx|
        line = idx + 2
        mapped = @importer.map_row(row)
        track_dentist(dentist_counts, mapped)

        action, reason = decide_action(mapped, line, warnings)
        case action
        when 'skip'           then summary[:would_skip] += 1
        when 'create_session' then summary[:would_create_session] += 1
        when 'update_session' then summary[:would_update_session] += 1
        when 'create_item'    then summary[:would_create_item] += 1
        when 'update_item'    then summary[:would_update_item] += 1
        end
        summary[:errors] += 1 if action == 'skip' && reason&.start_with?('Erro')

        push_sample(sample, line: line, action: action, mapped: mapped, reason: reason)
      end

      summary[:warnings] = warnings.size
      {
        summary: summary,
        rows: sample,
        warnings: warnings,
        dentists: dentists_payload(dentist_counts)
      }
    end

    private

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

    def track_dentist(acc, mapped)
      key = (mapped[:dentist_id].presence || mapped[:dentist_name].presence)
      return if key.blank?

      bucket = acc[key]
      bucket[:id] ||= mapped[:dentist_id]
      bucket[:name] ||= mapped[:dentist_name]
      bucket[:count] += 1
    end

    # Mirrors `ClinicorpTreatmentOperationImporter#process_row`. Não precisa de
    # banco — só precisa saber se a linha *iria* virar create/update/skip.
    def decide_action(mapped, line, warnings)
      if mapped[:deleted]
        return ['skip', 'Operação marcada como excluída no Clinicorp.']
      end
      if mapped[:operation_id].blank?
        return ['skip', 'Sem `id` (operation id).']
      end

      patient_id = @importer.find_patient_id(mapped[:patient_clinicorp_id])
      if patient_id.nil?
        push_warning(warnings, line, "Paciente '#{mapped[:patient_clinicorp_id]}' não encontrado — importe Patient.csv primeiro.")
        return ['skip', 'Paciente não encontrado no Klivy.']
      end

      if mapped[:executed].nil?
        push_warning(warnings, line, "Coluna `Executed` inválida.")
        return ['skip', 'Coluna `Executed` inválida.']
      end

      if mapped[:performed_at].nil?
        push_warning(warnings, line, 'ExecutedDate e CreateDate inválidos.')
        return ['skip', 'Sem data válida.']
      end

      if mapped[:executed]
        existing_session_log_for(patient_id, mapped[:operation_id]) ? ['update_session', "Sessão já existente — vai atualizar campos derivados."] : ['create_session', "Nova entrada na aba Evolução do paciente."]
      else
        existing_treatment_item_for(patient_id, mapped[:operation_id]) ? ['update_item', "Item já existente — vai atualizar."] : ['create_item', "Novo item pendente em 'Histórico Clinicorp'."]
      end
    rescue StandardError => e
      ['skip', "Erro ao prever: #{e.class}: #{e.message}"]
    end

    # Pré-carrega TODOS os clinicorp_operation_id já importados pra essa account
    # em 2 queries. Sem isso o previewer fazia 2 queries por linha do CSV (~10k
    # linhas → ~10k queries → estoura Rack::Timeout de 15s em prod).
    # `?` aqui é o operador JSONB "key exists" (sem bind args, AR trata como SQL
    # cru). `->>` retorna text, então o Set guarda strings — o op_id do CSV
    # também vira string em `map_row`, lookup bate.
    def preload_existing_operation_ids!
      @existing_session_op_ids = SessionLog.where(account_id: @account.id)
                                           .where("external_ids ? 'clinicorp_operation_id'")
                                           .pluck(Arel.sql("external_ids ->> 'clinicorp_operation_id'"))
                                           .to_set
      @existing_item_op_ids = TreatmentItem.where(account_id: @account.id)
                                           .where("external_ids ? 'clinicorp_operation_id'")
                                           .pluck(Arel.sql("external_ids ->> 'clinicorp_operation_id'"))
                                           .to_set
    end

    # patient_id ignorado: op_id do Clinicorp é único por clínica, não se
    # repete entre pacientes. Lookup global por account é equivalente.
    def existing_session_log_for(_patient_id, operation_id)
      @existing_session_op_ids.include?(operation_id.to_s)
    end

    def existing_treatment_item_for(_patient_id, operation_id)
      @existing_item_op_ids.include?(operation_id.to_s)
    end

    def push_sample(sample, line:, action:, mapped:, reason:)
      return if sample.size >= SAMPLE_LIMIT

      sample << {
        line: line,
        action: action,
        operation_id: mapped[:operation_id],
        patient_name: mapped[:patient_name],
        patient_clinicorp_id: mapped[:patient_clinicorp_id],
        procedure: mapped[:procedure_name],
        condition: mapped[:procedure_condition],
        type: mapped[:type],
        dentist: mapped[:dentist_name],
        executed: mapped[:executed],
        performed_at: mapped[:performed_at]&.iso8601,
        reason: reason
      }
    end

    def push_warning(warnings, line, message)
      return if warnings.size >= WARNING_LIMIT

      warnings << { line: line, message: message }
    end

    # Lista de dentistas distintos pra o passo de mapeamento na UI super_admin.
    # `mapped: true` = admin já indicou um user_id pra esse dentista (via
    # `dentist_mapping`).
    def dentists_payload(dentist_counts)
      dentist_counts.map do |key, info|
        {
          key: key,
          id: info[:id],
          name: info[:name],
          count: info[:count],
          mapped_user_id: @dentist_mapping[key].to_s == 'ignore' ? nil : @dentist_mapping[key],
          ignored: @dentist_mapping[key].to_s == 'ignore'
        }
      end.sort_by { |d| -d[:count] }
    end
  end
end
