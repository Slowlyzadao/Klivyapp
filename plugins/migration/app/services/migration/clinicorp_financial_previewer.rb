require 'csv'

module Migration
  # Dry-run do F-10 Importador Financeiro Clinicorp.
  # Sem tocar no banco, decide para cada entidade (Budget/Header/Item) se seria
  # create/update/skip, conta totais a receber/recebido (canon §4), e lista
  # dentistas distintos pro passo de mapeamento na UI super_admin.
  #
  # MUST stay in sync com `ClinicorpFinancialImporter`. Lição [1.5.2.9] —
  # qualquer condição nova lá precisa virar action equivalente aqui.
  class ClinicorpFinancialPreviewer
    SAMPLE_LIMIT = 100
    WARNING_LIMIT = 50

    def initialize(account, budgets_csv:, payment_headers_csv:, payment_items_csv:,
                   dentist_mapping: {}, bank_account_strategy: 'create',
                   bank_account_id: nil, payment_method_mapping: {},
                   specialty_mapping: {})
      @account = account
      @budgets_csv = budgets_csv
      @payment_headers_csv = payment_headers_csv
      @payment_items_csv = payment_items_csv
      @dentist_mapping = (dentist_mapping || {}).transform_keys(&:to_s)
      @bank_account_strategy = bank_account_strategy.to_s.presence || 'create'
      @bank_account_id = bank_account_id.presence&.to_i
      @payment_method_mapping = (payment_method_mapping || {}).transform_keys(&:to_s)
      @specialty_mapping = (specialty_mapping || {}).transform_keys(&:to_s)
      preload_indexes!
    end

    def call
      budget_rows = parse_csv(@budgets_csv)
      header_rows = parse_csv(@payment_headers_csv)
      item_rows   = parse_csv(@payment_items_csv)

      budget_groups = budget_rows.group_by { |r| r['BudgetId'].to_s.strip }.reject { |k, _| k.blank? }
      headers_by_id = header_rows.index_by { |r| r['id'].to_s.strip }

      summary = {
        total: budget_groups.size + item_rows.size,
        budgets_total: budget_groups.size,
        headers_total: header_rows.size,
        items_total: item_rows.size,
        would_create: 0,
        would_update: 0,
        would_skip: 0,
        errors: 0,
        warnings: 0
      }
      sample = []
      warnings = []
      dentist_counts = Hash.new { |h, k| h[k] = { id: nil, name: nil, count: 0 } }
      # Kinds canônicos encontrados (`pix`, `credito`, etc.) + contagem de itens
      # pra cada kind. Vai pro form do admin escolher qual PaymentMethod do
      # Settings vincular pra cada kind (em vez do importer auto-criar).
      payment_kind_counts = Hash.new(0)
      period_closure_blocked = 0

      # Bank-account check (estratégia "existing" exige conta cadastrada).
      bank_account_warning = check_bank_account_strategy
      push_warning(warnings, 0, bank_account_warning) if bank_account_warning

      # Agregação de Specialty: por Budget pegamos a DOMINANTE (mesma heurística
      # do importer — maior soma de ProcedureFinalAmount). Por Specialty
      # contamos quantos Budgets têm aquela como dominante + soma de valor.
      # Vai pro form do admin escolher DreCategory pra cada uma.
      specialty_counts = Hash.new { |h, k| h[k] = { count: 0, value_cents: 0 } }

      # ── Budgets ────────────────────────────────────────────────────────────
      budget_groups.each do |budget_id, rows|
        first = rows.first
        track_dentist(dentist_counts, first)
        action, reason = decide_budget(budget_id, first, warnings)
        case action
        when 'create' then summary[:would_create] += 1
        when 'update' then summary[:would_update] += 1
        when 'skip'   then summary[:would_skip] += 1
        end

        # Acumula stats da Specialty dominante (ignora budgets que vão ser
        # pulados — não geram DreCategory output mesmo).
        if action != 'skip'
          spec = dominant_specialty(rows)
          if spec
            specialty_counts[spec][:count] += 1
            specialty_counts[spec][:value_cents] +=
              rows.sum { |r| parse_cents(r['ProcedureFinalAmount']) || 0 }
          end
        end

        push_sample(sample, line: budget_id, kind: 'budget', action: action, reason: reason,
                            label: "Orçamento #{budget_id} · #{first['PatientName']}", row: first)
      end

      # ── Items (reconciliation totals & per-row action) ─────────────────────
      financial_totals = {
        amount_total_cents: 0,
        amount_active_cents: 0,
        amount_received_cents: 0,
        amount_pending_cents: 0,
        items_received: 0,
        items_pending: 0,
        items_overdue: 0,
        items_canceled: 0,
        items_partial_headers: 0
      }

      item_rows.each_with_index do |row, idx|
        line = idx + 2
        action, reason, classification = decide_item(row, headers_by_id, warnings, line)
        case action
        when 'create' then summary[:would_create] += 1
        when 'update' then summary[:would_update] += 1
        when 'skip'   then summary[:would_skip] += 1
        end

        # Conta os kinds (sempre, mesmo se a row vai ser skipada por outros
        # motivos — admin precisa saber TODOS os kinds que aparecem na planilha
        # pra mapear todos eles, não só os "salváveis").
        kind = clinicorp_type_to_kind(row['Type'])
        payment_kind_counts[kind] += 1 if kind

        # PeriodClosure check (mesmo critério do importer):
        # competence (PostDate ou DueDate) OU received (ReceivedDate) caindo
        # em mês fechado bloqueia. Conta separado pra mostrar no preview.
        period_closure_blocked += 1 if period_closure_blocks?(row)

        accumulate_totals(financial_totals, classification)
        next if sample.size >= SAMPLE_LIMIT && action == 'skip'

        push_sample(sample, line: line, kind: 'item', action: action, reason: reason,
                            label: "Parcela #{row['id']} · #{format_money(parse_cents(row['Amount']) || 0)}", row: row)
      end

      financial_totals[:items_partial_headers] = header_rows.count { |r| r['IsPartialPayment'].to_s.strip == 'X' }

      # Avisos consolidados de período fechado — só 1 entrada na lista mesmo
      # que afete N linhas (não polui a UI com 1000 warnings idênticos).
      if period_closure_blocked.positive?
        push_warning(warnings, 0,
                     "#{period_closure_blocked} parcela(s) caem em período contábil fechado e serão IGNORADAS. " \
                     'Reabra o período em Settings → Contador antes de importar pra incluí-las.')
      end

      summary[:warnings] = warnings.size
      {
        summary: summary,
        rows: sample,
        warnings: warnings,
        dentists: dentists_payload(dentist_counts),
        reconciliation: reconciliation_payload(financial_totals),
        bank_account: bank_account_payload,
        payment_kinds: payment_kinds_payload(payment_kind_counts),
        specialties: specialties_payload(specialty_counts),
        period_closure: { blocked_rows: period_closure_blocked }
      }
    end

    private

    def preload_indexes!
      @patient_by_clinicorp_id = {}
      @patient_by_cpf = {}
      ::Patient.where(account_id: @account.id, deleted_at: nil)
               .where("external_ids ? 'clinicorp' OR cpf IS NOT NULL")
               .pluck(Arel.sql("external_ids ->> 'clinicorp'"), :cpf, :id)
               .each do |exact_id, cpf, pid|
        if exact_id.present?
          register_patient_key(exact_id.to_s, pid)
          scientific_truncations(exact_id.to_s).each { |sci| register_patient_key(sci, pid) }
        end
        @patient_by_cpf[normalize_cpf(cpf)] = pid if cpf.present? && normalize_cpf(cpf).length == 11
      end

      @existing_budget_external_ids = Financial::Budget.where(account_id: @account.id)
                                                       .where.not(external_id: nil)
                                                       .pluck(:external_id).to_set
      @existing_installment_external_ids = Financial::Installment.where(account_id: @account.id)
                                                                  .where.not(external_id: nil)
                                                                  .pluck(:external_id).to_set
    end

    def normalize_cpf(value)
      value.to_s.gsub(/\D/, '')
    end

    # MUST stay in sync with ClinicorpFinancialImporter#scientific_truncations.
    def scientific_truncations(exact_id_str)
      digits = exact_id_str.to_s.gsub(/\D/, '')
      return [] if digits.length < 7

      exp = digits.length - 1
      first7 = digits[0, 7].to_i
      rounded6 = (first7 + 5) / 10
      if rounded6 >= 1_000_000
        exp += 1
        rounded6 /= 10
      end
      s = format('%06d', rounded6)
      exp_str = format('%02d', exp)
      ["#{s[0]},#{s[1, 5]}E+#{exp_str}", "#{s[0]}.#{s[1, 5]}E+#{exp_str}"]
    end

    def register_patient_key(key, patient_id)
      return if key.blank?

      existing = @patient_by_clinicorp_id[key]
      if existing.nil?
        @patient_by_clinicorp_id[key] = patient_id
      elsif existing != patient_id && existing != :collision
        @patient_by_clinicorp_id[key] = :collision
      end
    end

    def lookup_patient_id(clinicorp_id, owner_cpf: nil, payer_cpf: nil)
      val = @patient_by_clinicorp_id[clinicorp_id.to_s.strip]
      return val if val.is_a?(Integer)

      [owner_cpf, payer_cpf].each do |cpf|
        cpf_digits = normalize_cpf(cpf)
        next if cpf_digits.length != 11

        pid = @patient_by_cpf[cpf_digits]
        return pid if pid
      end

      nil
    end

    def check_bank_account_strategy
      return nil unless @bank_account_strategy == 'existing'

      has_accounts = Financial::BankAccount.where(account_id: @account.id, active: true).exists?
      return nil if has_accounts

      'Estratégia "Usar conta existente" foi escolhida, mas a clínica não tem conta bancária ativa cadastrada. Cadastre uma conta ou troque pra "Criar conta dedicada".'
    end

    def bank_account_payload
      accounts = Financial::BankAccount.where(account_id: @account.id, active: true).order(:id)
                                       .pluck(:id, :name, :kind)
                                       .map { |id, name, kind| { id: id, name: name, kind: kind } }
      {
        strategy: @bank_account_strategy,
        selected_id: @bank_account_id,
        active_accounts: accounts,
        has_active_accounts: accounts.any?,
        will_create_dedicated: @bank_account_strategy == 'create' &&
                               !Financial::BankAccount.where(account_id: @account.id,
                                                             name: ClinicorpFinancialImporter::BANK_ACCOUNT_NAME).exists?
      }
    end

    # ── PaymentMethod resolve (preview-only) ─────────────────────────────────

    # Mapeia Clinicorp Type → kind canônico Klivy. Espelha
    # `ClinicorpFinancialImporter::TYPE_TO_METHOD` — DEVE bater 100%, lição
    # [1.5.2.9]: previewer e importer caminham juntos.
    def clinicorp_type_to_kind(raw_type)
      ClinicorpFinancialImporter::TYPE_TO_METHOD[raw_type.to_s.strip.upcase]
    end

    # Payload pro form do admin escolher PaymentMethod por kind.
    # Inclui:
    #   - kinds (lista ordenada por contagem desc): kind canônico + label + n_items
    #   - methods_available: PaymentMethods já cadastrados na conta (grouped por kind)
    #   - selected (admin já mapeou alguma forma nessa preview): kind => pm_id
    def payment_kinds_payload(kind_counts)
      methods = Financial::PaymentMethod.where(account_id: @account.id, status: 'active')
                                        .order(:kind, :name)
                                        .pluck(:id, :kind, :name, :provider)
      methods_by_kind = methods.group_by { |_id, kind, _name, _provider| kind }
                               .transform_values do |list|
        list.map { |id, _kind, name, provider| { id: id, name: name, provider: provider } }
      end

      kinds = kind_counts.sort_by { |_kind, count| -count }.map do |kind, count|
        {
          kind: kind,
          label: ClinicorpFinancialImporter::KIND_DISPLAY[kind] || kind.to_s.capitalize,
          count: count,
          available_methods: methods_by_kind[kind] || [],
          selected_id: @payment_method_mapping[kind].presence
        }
      end

      { kinds: kinds, mapped: @payment_method_mapping.reject { |_, v| v.blank? } }
    end

    # ── Specialty → DreCategory (preview-only) ───────────────────────────────

    # Mesma heurística do importer — maior soma de ProcedureFinalAmount.
    def dominant_specialty(rows)
      rows.group_by { |r| r['Specialty'].to_s.strip }
          .reject { |k, _| !valid_specialty?(k) }
          .max_by do |_, group|
            [group.sum { |r| parse_cents(r['ProcedureFinalAmount']) || 0 }, group.size]
          end&.first
    end

    def valid_specialty?(value)
      v = value.to_s.strip
      return false if v.length < 3

      v.count('a-zA-Záéíóúâêîôûãõàèç A-ZÁÉÍÓÚÂÊÎÔÛÃÕÀÈÇ').to_f / v.length > 0.7
    end

    # Payload pro form mapear "Specialty → DreCategory". DreCategories receita
    # da conta vão pro select; vazio = importer deixa nil (operador
    # reclassifica depois em Configurações → Reclassificar).
    def specialties_payload(specialty_counts)
      categories = Financial::DreCategory.where(account_id: @account.id, kind: 'receita')
                                          .order(:path, :name)
                                          .pluck(:id, :name, :path)
                                          .map { |id, name, path| { id: id, name: name, path: path } }

      items = specialty_counts.sort_by { |_, h| -h[:value_cents] }.map do |spec, stats|
        {
          name: spec,
          count: stats[:count],
          value_cents: stats[:value_cents],
          selected_id: @specialty_mapping[spec].presence
        }
      end

      { items: items, available_categories: categories }
    end

    # ── PeriodClosure (preview-only) ─────────────────────────────────────────

    def period_closure_blocks?(row)
      return false unless period_closures_exist?

      competence = parse_date(row['PostDate']) || parse_date(row['DueDate']) || parse_date(row['OriginalDueDate'])
      received   = parse_date(row['ReceivedDate']) || parse_date(row['PaymentDate'])
      (competence && period_month_closed?(competence)) || (received && period_month_closed?(received))
    end

    def period_closures_exist?
      return @period_closures_exist unless @period_closures_exist.nil?

      @period_closures_exist = Financial::PeriodClosure
                                 .closed
                                 .where(account_id: @account.id)
                                 .exists?
    end

    def period_month_closed?(date)
      @period_closure_cache ||= {}
      key = [date.year, date.month]
      return @period_closure_cache[key] if @period_closure_cache.key?(key)

      @period_closure_cache[key] = Financial::PeriodClosure.closed_for?(@account.id, date)
    end

    def decide_budget(budget_id, first, warnings)
      patient_clinicorp_id = first['PatientId'].to_s.strip
      if lookup_patient_id(patient_clinicorp_id).nil?
        push_warning(warnings, budget_id, "Budget '#{budget_id}': paciente Clinicorp '#{patient_clinicorp_id}' não foi importado.")
        return ['skip', 'Paciente não encontrado no Klivy.']
      end

      external_id = "clinicorp_budget_#{budget_id}"
      return ['update', "Já existe — vai atualizar valores e itens."] if @existing_budget_external_ids.include?(external_id)

      ['create', "Novo orçamento (status #{guess_budget_status(first)})."]
    rescue StandardError => e
      ['skip', "Erro: #{e.class}: #{e.message}"]
    end

    def decide_item(row, headers_by_id, warnings, line)
      item_id = row['id'].to_s.strip
      classification = classify_item(row)

      return ['skip', 'PaymentItem sem id.', classification] if item_id.blank?

      patient_clinicorp_id = row['PatientId'].to_s.strip
      if lookup_patient_id(patient_clinicorp_id, owner_cpf: row['OwnerCPF'], payer_cpf: row['PayerCPF']).nil?
        push_warning(warnings, line, "Item '#{item_id}': paciente '#{patient_clinicorp_id}' não foi importado (CPF também não casou).")
        return ['skip', 'Paciente não encontrado.', classification]
      end

      external_id = "clinicorp_item_#{item_id}"
      action = @existing_installment_external_ids.include?(external_id) ? 'update' : 'create'
      [action, action == 'create' ? "Nova parcela (#{classification[:status]})." : "Parcela já existe — vai atualizar.", classification]
    rescue StandardError => e
      ['skip', "Erro: #{e.class}: #{e.message}", classify_item(row)]
    end

    def classify_item(row)
      amount_cents = parse_cents(row['Amount']) || 0
      received_amount_cents = compute_received_amount(row, amount_cents)
      due_date = parse_date(row['DueDate'])
      canceled = row['Canceled'].to_s.strip == 'X' || row['CancelInstallment'].to_s.strip == 'X'

      status = if canceled then 'cancelado'
               elsif amount_cents.positive? && received_amount_cents >= amount_cents then 'recebido'
               elsif received_amount_cents.positive? then 'parcial'
               elsif due_date && due_date < Date.current then 'vencido'
               else 'pendente'
               end

      { amount_cents: amount_cents, received_amount_cents: received_amount_cents, status: status, canceled: canceled }
    end

    # Idêntico ao ClinicorpFinancialImporter — mantemos parity pra preview e
    # importação concordarem 100%.
    def compute_received_amount(row, amount_cents)
      return 0 unless received?(row)

      paid = parse_cents(row['PaidMoneyAmount']) || 0
      val = paid.positive? ? paid : amount_cents
      [val, amount_cents].min
    end

    def received?(row)
      flag = row['PaymentReceived'].to_s.strip.upcase
      return true if %w[X TRUE 1 Y SIM].include?(flag)

      parse_date(row['ReceivedDate']).present?
    end

    def accumulate_totals(totals, classification)
      totals[:amount_total_cents] += classification[:amount_cents]
      unless classification[:canceled]
        totals[:amount_active_cents] += classification[:amount_cents]
        totals[:amount_received_cents] += classification[:received_amount_cents]
      end
      case classification[:status]
      when 'recebido', 'parcial' then totals[:items_received] += 1
      when 'pendente' then totals[:items_pending] += 1
      when 'vencido' then totals[:items_overdue] += 1
      when 'cancelado' then totals[:items_canceled] += 1
      end
      totals[:amount_pending_cents] = totals[:amount_active_cents] - totals[:amount_received_cents]
    end

    def reconciliation_payload(totals)
      {
        total_launched_brl: format_money(totals[:amount_active_cents]),
        total_received_brl: format_money(totals[:amount_received_cents]),
        balance_to_receive_brl: format_money(totals[:amount_pending_cents]),
        items_received: totals[:items_received],
        items_pending: totals[:items_pending],
        items_overdue: totals[:items_overdue],
        items_canceled: totals[:items_canceled],
        partial_headers_for_review: totals[:items_partial_headers]
      }
    end

    def guess_budget_status(row)
      return 'cancelado' if row['NotApproved'].to_s.strip == 'X'
      return 'cancelado' if row['BudgetRejectedDate'].to_s.strip.present?
      return 'concluido' if row['Executed'].to_s.strip == 'X'
      return 'aprovado' if row['BudgetApproved'].to_s.strip == 'X'

      'rascunho'
    end

    def track_dentist(acc, row)
      key = row['DentistId'].to_s.strip.presence || row['DentistName'].to_s.strip
      return if key.blank?

      bucket = acc[key]
      bucket[:id] ||= row['DentistId'].to_s.strip.presence
      bucket[:name] ||= row['DentistName'].to_s.strip.presence
      bucket[:count] += 1
    end

    def dentists_payload(dentist_counts)
      dentist_counts.map do |key, info|
        {
          key: key,
          id: info[:id],
          name: info[:name],
          count: info[:count],
          mapped_user_id: (@dentist_mapping[key].to_s == 'ignore' ? nil : @dentist_mapping[key]),
          ignored: @dentist_mapping[key].to_s == 'ignore'
        }
      end.sort_by { |d| -d[:count] }
    end

    def push_sample(sample, line:, kind:, action:, reason:, label:, row:)
      return if sample.size >= SAMPLE_LIMIT

      sample << {
        line: line.to_s,
        kind: kind,
        action: action,
        label: label,
        patient_name: row['PatientName'].to_s.strip.presence,
        patient_clinicorp_id: row['PatientId'].to_s.strip.presence,
        amount: row['Amount'].to_s.strip.presence,
        type: row['Type'].to_s.strip.presence,
        received: row['PaymentReceived'].to_s.strip == 'X',
        canceled: row['Canceled'].to_s.strip == 'X',
        reason: reason
      }
    end

    def push_warning(warnings, line, message)
      return if warnings.size >= WARNING_LIMIT

      warnings << { line: line.to_s, message: message }
    end

    # ── Parsing helpers (mesma lógica do importer) ───────────────────────────

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

    def parse_cents(value)
      return nil if value.nil?

      str = value.to_s.strip
      return nil if str.blank?

      str = str.gsub(/[^\d,.\-]/, '')
      return nil if str.blank?

      str = str.tr('.', '').tr(',', '.') if str.match?(/,\d{1,2}\z/)
      (BigDecimal(str) * 100).to_i
    rescue ArgumentError
      nil
    end

    def parse_date(value)
      return nil if value.blank?

      str = value.to_s.strip
      return Date.parse(str) if str.match?(/\A\d{4}-\d{2}-\d{2}/)

      Date.strptime(str[0, 10], '%d/%m/%Y') if str.match?(%r{\A\d{2}/\d{2}/\d{4}})
    rescue ArgumentError, Date::Error
      nil
    end

    def format_money(cents)
      format('R$ %.2f', cents.to_i / 100.0).tr('.', ',')
    end
  end
end
