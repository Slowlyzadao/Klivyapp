require 'csv'

module Migration
  # Importa `TreatmentOperation.xlsx` (procedimentos) do Clinicorp para o Klivy.
  #
  # Cada linha vira:
  #   * Executed=true  → SessionLog (registro de procedimento já realizado)
  #   * Executed=false → TreatmentItem dentro de um TreatmentPlan "Histórico
  #                      Clinicorp" criado lazy (1 plano por paciente).
  #
  # Vínculo paciente: lookup determinístico via
  #   `patients.external_ids ->> 'clinicorp' = PatientId`
  # (populado pelo `ClinicorpPatientImporter` em [1.5.2.7]).
  #
  # Vínculo dentista: o caller passa `dentist_mapping` como Hash
  #   { "DentistName ou DentistId" => user_id }
  # construído pela tela super_admin (ver `MigrationsController#dentists_distinct`).
  # Linhas com dentista não-mapeado caem em `professional_id: nil` (importer não
  # bloqueia — log de info pra o admin saber).
  #
  # Idempotência: cada operação carrega `id` (Q) único do Clinicorp. Salvamos em
  # `session_logs.external_ids['clinicorp_operation_id']` (ou `treatment_items`).
  # Re-import: lookup pelo id externo → update; senão → create.
  #
  # Observações importantes (validadas com o usuário):
  #   * `Amount` (A) está 0% preenchida no XLSX → todos `unit_price` ficam nil.
  #   * `Type` (P) e `ProcedureCondition` (L) são texto livre → guardamos em
  #     `external_metadata['procedure_condition']` / `['type']` pra preservar
  #     fielmente sem ter que criar enum.
  #   * `NextAppointmentNotes` (H) → `session_logs.next_consultation_details`.
  #   * `Notes` (I) → `session_logs.observation`.
  #   * `Surface` (N), `Tooth` (O), `z_ImportKey` (R) → `external_metadata`.
  class ClinicorpTreatmentOperationImporter
    BATCH_SIZE = 250
    BR_TZ = 'America/Sao_Paulo'.freeze
    HISTORICAL_PLAN_KEY = 'clinicorp_historical_plan'.freeze

    # A coluna `Executed` do Clinicorp NÃO é booleano. É marcada com "X" quando
    # o procedimento foi executado e fica em branco quando está só planejado
    # (estilo "checkbox" do Excel). Validado em [1.5.3.1]: shared string idx
    # 1943 = "X"; ~99,97% das linhas têm X, ~3 linhas têm valor vazio.
    #
    # Ainda aceitamos os valores booleanos clássicos (`true`/`1`/`verdadeiro`
    # etc.) caso o usuário rode o importer com um CSV de outra origem que use
    # esse formato. Mas o caso real do Clinicorp é X/empty.
    TRUTHY_EXECUTED = %w[x true 1 yes sim t v verdadeiro executed executado].freeze
    FALSY_EXECUTED  = %w[false 0 no nao não f falso planned planejado].freeze

    def initialize(migration_run, operations_csv:, dentist_mapping: {})
      @run = migration_run
      @operations_csv = operations_csv
      @account = migration_run.account
      # `dentist_mapping`: { "DentistName"|"DentistId" => user_id ou nil/'ignore' }
      # Aceita tanto chaves por nome quanto por id — preferimos o id quando
      # disponível porque é estável em re-imports.
      @dentist_mapping = (dentist_mapping || {}).transform_keys(&:to_s)
      @errors = []
      @counters = {
        processed: 0,
        sessions_created: 0,   # Executed=true → SessionLog novo
        sessions_updated: 0,   # Executed=true → SessionLog já existia (re-import)
        items_created: 0,      # Executed=false → TreatmentItem novo
        items_updated: 0,      # Executed=false → TreatmentItem já existia
        plans_created: 0,      # TreatmentPlan "Histórico Clinicorp" criado lazy
        skipped: 0,            # paciente não-encontrado, data inválida, etc.
        errors: 0,
        warnings: 0
      }
      # Caches in-memory pra reduzir queries num run de ~10k linhas:
      @patient_by_clinicorp_id = {}  # clinicorp_id (string) → patient_id
      @historical_plan_by_patient_id = {} # patient_id → plan_id (lazy)
    end

    def call
      rows = parse_csv(@operations_csv)
      @run.update!(total_rows: rows.size, processed_rows: 0)

      preload_patient_index!

      rows.each_slice(BATCH_SIZE).with_index do |slice, batch_index|
        slice.each_with_index do |row, idx|
          line_number = (batch_index * BATCH_SIZE) + idx + 2
          process_row(row, line_number)
          @counters[:processed] += 1
        end
        flush_progress!
      end

      flush_progress!(final: true)
      @counters
    end

    # Pública porque o Previewer compartilha — mantém lógica de mapeamento idêntica.
    def map_row(row)
      h = row.transform_keys { |k| k.to_s.strip }
      pick = ->(canonical) { h[canonical] }

      operation_id = pick.call('id').to_s.strip
      patient_clinicorp_id = pick.call('PatientId').to_s.strip
      dentist_id = pick.call('DentistId').to_s.strip
      dentist_name = pick.call('DentistName').to_s.strip
      executed_raw = pick.call('Executed').to_s.strip.downcase

      # Branco = planejado (não executado) no padrão Clinicorp; valor "X" ou
      # qualquer truthy clássico = executado. Valores inesperados retornam nil
      # pra cair em "Coluna Executed inválida" e o admin saber que a planilha
      # tá com formato incomum.
      executed = if executed_raw.empty?
                   false
                 elsif TRUTHY_EXECUTED.include?(executed_raw)
                   true
                 elsif FALSY_EXECUTED.include?(executed_raw)
                   false
                 end

      performed_at = parse_date(pick.call('ExecutedDate')) || parse_date(pick.call('CreateDate'))

      {
        operation_id: operation_id.presence,
        patient_clinicorp_id: patient_clinicorp_id.presence,
        patient_name: pick.call('PatientName')&.strip.presence,
        dentist_id: dentist_id.presence,
        dentist_name: dentist_name.presence,
        executed: executed,
        deleted: truthy?(pick.call('Deleted')),
        performed_at: performed_at,
        created_at_raw: pick.call('CreateDate'),
        procedure_name: pick.call('ProcedureDescription')&.strip.presence,
        procedure_condition: pick.call('ProcedureCondition')&.strip.presence,
        type: pick.call('Type')&.strip.presence,
        notes: pick.call('Notes')&.strip.presence,
        next_appointment_notes: pick.call('NextAppointmentNotes')&.strip.presence,
        surface: pick.call('Surface')&.strip.presence,
        tooth: pick.call('Tooth')&.strip.presence,
        amount: pick.call('Amount')&.strip.presence, # ~100% nil; mantemos pra futuro
        z_import_key: pick.call('z_ImportKey')&.strip.presence
      }
    end

    # Pública — usada pelo Previewer pra resolver o user_id sem duplicar lógica.
    def resolve_dentist_id(mapped)
      key_id = mapped[:dentist_id]
      key_name = mapped[:dentist_name]

      # Preferimos lookup por DentistId (estável). Se admin mapeou por nome, OK.
      mapped_value = @dentist_mapping[key_id] || @dentist_mapping[key_name]
      return nil if mapped_value.blank? || mapped_value.to_s == 'ignore'

      mapped_value.to_i
    end

    def find_patient_id(clinicorp_id)
      @patient_by_clinicorp_id[clinicorp_id.to_s]
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

    # Roda 1 query única pra todo o índice de pacientes do account, evitando
    # SELECT N+1 dentro do loop. Em accounts com 10k pacientes isso ainda cabe
    # tranquilamente em memória (chave=string, valor=integer).
    def preload_patient_index!
      Patient.where(account_id: @account.id, deleted_at: nil)
             .where("external_ids ? 'clinicorp'")
             .pluck(Arel.sql("external_ids ->> 'clinicorp'"), :id)
             .each { |cid, pid| @patient_by_clinicorp_id[cid.to_s] = pid }
    end

    def process_row(row, line_number)
      mapped = map_row(row)

      if mapped[:deleted]
        @counters[:skipped] += 1
        log_info(line_number, "Operação marcada como excluída no Clinicorp — ignorada.")
        return
      end

      if mapped[:operation_id].blank?
        @counters[:skipped] += 1
        log_warning(line_number, 'Linha sem `id` (operation id) — ignorada.')
        return
      end

      patient_id = find_patient_id(mapped[:patient_clinicorp_id])
      if patient_id.nil?
        @counters[:skipped] += 1
        log_warning(line_number,
                    "Paciente Clinicorp '#{mapped[:patient_clinicorp_id]}' " \
                    "(nome: #{mapped[:patient_name] || '—'}) não encontrado. " \
                    'Importe Patient.csv primeiro pra popular external_ids[clinicorp].')
        return
      end

      if mapped[:executed].nil?
        @counters[:skipped] += 1
        log_warning(line_number, "Coluna `Executed` inválida ('#{row['Executed']}') — ignorada.")
        return
      end

      if mapped[:performed_at].nil?
        @counters[:skipped] += 1
        log_warning(line_number, 'ExecutedDate e CreateDate ambos inválidos — ignorada.')
        return
      end

      if mapped[:executed]
        upsert_session_log(patient_id, mapped, line_number)
      else
        upsert_treatment_item(patient_id, mapped, line_number)
      end
    rescue StandardError => e
      @counters[:errors] += 1
      log_error(line_number, "#{e.class}: #{e.message}")
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Executed=true → SessionLog
    # ──────────────────────────────────────────────────────────────────────────

    def upsert_session_log(patient_id, mapped, line_number)
      existing = SessionLog.where(account_id: @account.id, patient_id: patient_id)
                           .where("external_ids @> ?", { 'clinicorp_operation_id' => mapped[:operation_id] }.to_json)
                           .first

      attrs = session_log_attributes(patient_id, mapped)
      if existing
        # Re-import: atualizamos campos derivados, mantendo created_at e o
        # status atual (não sobrescreve assinaturas/erratas que o user
        # adicionou após o 1º import).
        existing.update_columns(
          attrs.except(:status, :external_ids, :external_metadata, :professional_id).merge(
            external_metadata: existing.external_metadata.to_h.merge(attrs[:external_metadata]),
            updated_at: Time.current
          )
        )
        @counters[:sessions_updated] += 1
      else
        SessionLog.insert_all([attrs.merge(created_at: Time.current, updated_at: Time.current)])
        @counters[:sessions_created] += 1
      end

      log_info(line_number, "Sem profissional vinculado para '#{mapped[:dentist_name]}'.") \
        if mapped[:dentist_name].present? && attrs[:professional_id].nil?
    end

    def session_log_attributes(patient_id, mapped)
      professional_id = resolve_dentist_id(mapped)

      # Procedimentos migrados do Clinicorp já foram executados e implicitamente
      # assinados pelo profissional no sistema antigo. Marcamos como `signed`
      # com `signed_by_id = professional_id` e `signed_at = performed_at` pra
      # não criar "rascunhos zumbi" que confundem o usuário e violam a
      # regulação CFO (prontuário deve ser assinado).
      #
      # Exceção: linhas sem dentista identificável caem em `draft` (não temos
      # signer válido). O usuário pode assinar manualmente depois.
      base = {
        account_id: @account.id,
        patient_id: patient_id,
        professional_id: professional_id,
        performed_at: mapped[:performed_at],
        procedure_name: mapped[:procedure_name].presence || 'Procedimento Clinicorp',
        observation: mapped[:notes],
        next_consultation_details: mapped[:next_appointment_notes],
        external_ids: { 'clinicorp_operation_id' => mapped[:operation_id] },
        external_metadata: build_external_metadata(mapped)
      }

      if professional_id
        base.merge(
          status: 'signed',
          signed_by_id: professional_id,
          signed_at: mapped[:performed_at]
        )
      else
        base.merge(status: 'draft')
      end
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Executed=false → TreatmentItem (lazy plano "Histórico Clinicorp")
    # ──────────────────────────────────────────────────────────────────────────

    def upsert_treatment_item(patient_id, mapped, _line_number)
      plan_id = ensure_historical_plan(patient_id)

      existing = TreatmentItem.where(account_id: @account.id, treatment_plan_id: plan_id)
                              .where("external_ids @> ?", { 'clinicorp_operation_id' => mapped[:operation_id] }.to_json)
                              .first

      attrs = treatment_item_attributes(plan_id, mapped)
      if existing
        existing.update!(
          procedure_name: attrs[:procedure_name],
          notes: attrs[:notes],
          external_metadata: existing.external_metadata.to_h.merge(attrs[:external_metadata])
        )
        @counters[:items_updated] += 1
      else
        TreatmentItem.create!(attrs)
        @counters[:items_created] += 1
      end
    end

    # Cria 1 plano "Histórico Clinicorp" por paciente sob demanda. Idempotente:
    # busca primeiro pelo external_ids pra suportar re-import.
    def ensure_historical_plan(patient_id)
      cached = @historical_plan_by_patient_id[patient_id]
      return cached if cached

      plan = TreatmentPlan.active.where(account_id: @account.id, patient_id: patient_id)
                          .where("external_ids @> ?", { HISTORICAL_PLAN_KEY => 'true' }.to_json)
                          .first

      if plan.nil?
        plan = TreatmentPlan.create!(
          account_id: @account.id,
          patient_id: patient_id,
          title: 'Histórico Clinicorp',
          description: 'Plano migrado do Clinicorp — agrupa procedimentos planejados (não executados) importados do histórico.',
          status: 'aprovado',
          approved_at: Time.current.to_date,
          external_ids: { HISTORICAL_PLAN_KEY => 'true' },
          external_metadata: { 'source' => 'clinicorp', 'imported_at' => Time.current.iso8601 }
        )
        @counters[:plans_created] += 1
      end

      @historical_plan_by_patient_id[patient_id] = plan.id
    end

    def treatment_item_attributes(plan_id, mapped)
      {
        account_id: @account.id,
        treatment_plan_id: plan_id,
        procedure_name: (mapped[:procedure_name].presence || 'Procedimento Clinicorp')[0, 255],
        region: mapped[:surface],
        tooth_number: mapped[:tooth],
        sessions_planned: 1,
        sessions_done: 0,
        unit_price: nil,             # Amount é 0% preenchida — admin ajusta na mão se quiser
        discount_value: 0,
        priority: 'media',
        status: 'aprovado',
        notes: mapped[:notes],
        external_ids: { 'clinicorp_operation_id' => mapped[:operation_id] },
        external_metadata: build_external_metadata(mapped)
      }
    end

    # ──────────────────────────────────────────────────────────────────────────
    # Helpers
    # ──────────────────────────────────────────────────────────────────────────

    def build_external_metadata(mapped)
      {
        'source' => 'clinicorp',
        'procedure_condition' => mapped[:procedure_condition],
        'type' => mapped[:type],
        'surface' => mapped[:surface],
        'tooth' => mapped[:tooth],
        'amount_raw' => mapped[:amount],
        'z_import_key' => mapped[:z_import_key],
        'dentist_name_raw' => mapped[:dentist_name],
        'dentist_id_raw' => mapped[:dentist_id]
      }.compact
    end

    # Usado pra coluna `Deleted` (booleano clássico) — não confunde com a
    # coluna `Executed` que usa "X"/empty.
    def truthy?(val)
      %w[true 1 yes sim t].include?(val.to_s.strip.downcase)
    end

    # Aceita 'YYYY-MM-DDTHH:MM:SSZ' (ISO da exportação) e 'DD/MM/YYYY HH:MM:SS'
    # (formato BR exportado pelo Excel). Retorna Time em BRT.
    def parse_date(value)
      return nil if value.blank?

      str = value.to_s.strip
      tz = ActiveSupport::TimeZone[BR_TZ]

      if str.match?(/\A\d{4}-\d{2}-\d{2}T/)
        Time.iso8601(str).in_time_zone(tz)
      elsif str.match?(%r{\A\d{2}/\d{2}/\d{4}})
        # Excel BR: "14/08/2023 16:42:00" (já no fuso local).
        tz.parse(str)
      else
        Time.parse(str).in_time_zone(tz)
      end
    rescue ArgumentError, TypeError
      nil
    end

    def flush_progress!(final: false)
      @run.update_columns(
        processed_rows: @counters[:processed],
        created_count: @counters[:sessions_created] + @counters[:items_created] + @counters[:plans_created],
        updated_count: @counters[:sessions_updated] + @counters[:items_updated],
        skipped_count: @counters[:skipped],
        error_count: @counters[:errors],
        errors_log: @errors.last(200),
        updated_at: Time.current
      )
    end

    def log_error(line, message)
      @errors << { line: line, level: 'error', message: message }
    end

    def log_warning(line, message)
      @counters[:warnings] += 1
      @errors << { line: line, level: 'warning', message: message }
    end

    def log_info(line, message)
      @errors << { line: line, level: 'info', message: message }
    end
  end
end
