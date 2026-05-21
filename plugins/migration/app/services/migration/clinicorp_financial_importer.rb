require 'csv'

module Migration
  # F-10 Importador Financeiro Clinicorp → Klivy/Salus Financial::*
  #
  # Recebe 3 CSVs (já convertidos do XLSX no frontend via SheetJS):
  #   - Budgets.xlsx        → Financial::Budget + Financial::BudgetItem
  #   - PaymentHeader.xlsx  → indexa pra resolver cabeçalhos de cobrança
  #   - PaymentItem.xlsx    → Financial::Installment + (Receipt + Item se quitado)
  #
  # Idempotência: cada entidade usa `external_id` único por conta:
  #   Budget        = "clinicorp_budget_<BudgetId>"            (orçamentos reais)
  #   Budget bucket = "clinicorp_avulsos_<PatientId clinicorp>" (parcelas sem orçamento)
  #   Installment   = "clinicorp_item_<PaymentItem.id>"
  #   PaymentReceipt= "clinicorp_item_<PaymentItem.id>"  (1 receipt por item quitado)
  #
  # Match Patient: `Patient.external_ids ->> 'clinicorp' == row.PatientId`
  # Match Dentist: dropdown manual no Painel (mesma UX do treatment_operations).
  #
  # Canon §3.6 — três sub-etapas em ordem:
  #   6.1 Budgets    — filtros = importar TUDO (escolha do user "Tudo, inclusive rejeitados")
  #   6.2 Headers    — preload em memória; receipt nasce no passo 6.3 (vincula 1:1 ao item)
  #   6.3 Items      — Canceled=X vira status=cancelado mas NÃO é pulado (preserva histórico)
  #
  # PaymentItem.Type → Klivy Installment.payment_method (canon §6.3):
  class ClinicorpFinancialImporter
    BATCH_SIZE = 250

    TYPE_TO_METHOD = {
      'OTHER'                => 'dinheiro',
      'CREDIT_CARD_EXTERNAL' => 'credito',
      'DEBIT_CARD_EXTERNAL'  => 'debito',
      'BOLETO_INTERNAL'      => 'boleto',
      'CREDIT_CARD_INTERNAL' => 'credito',
      'PIX'                  => 'pix',
      'CASH'                 => 'dinheiro',
      'DINHEIRO'             => 'dinheiro'
    }.freeze

    BANK_ACCOUNT_NAME = 'Importação Clinicorp'.freeze

    def initialize(migration_run, budgets_csv:, payment_headers_csv:, payment_items_csv:,
                   dentist_mapping: {}, bank_account_strategy: 'create')
      @run = migration_run
      @budgets_csv = budgets_csv
      @payment_headers_csv = payment_headers_csv
      @payment_items_csv = payment_items_csv
      @dentist_mapping = (dentist_mapping || {}).transform_keys(&:to_s)
      @bank_account_strategy = bank_account_strategy.to_s.presence || 'create'
      @account = migration_run.account
      @errors = []
      @counters = blank_counters
      @bucket_by_patient = {}
      @budget_by_clinicorp_id = {}
      # Sequence incremental por bucket: o índice único
      # idx_uniq_installment_number_per_budget impede 2 parcelas com mesmo
      # `number` no mesmo budget. Como a maioria das parcelas avulsas Clinicorp
      # tem InstallmentNumber=1 ("parcela 1 de 1"), agrupá-las no bucket do
      # paciente quebra unique. Usamos sequência crescente por bucket; a
      # numeração ORIGINAL (1 de N) fica preservada em metadata.clinicorp_*.
      @bucket_number_sequence = {}
      # Resolvido no call: se dentist_mapping tem exatamente 1 user_id (não-
      # ignore), usa esse como professional_id default em parcelas avulsas e
      # entries. Cobre clínica unipessoal (caso Mamedes). Multi-dentista fica
      # nil — admin deve usar reclassificação manual ou card futuro.
      @effective_default_professional_id = nil
    end

    def call
      @bank_account = resolve_bank_account!
      preload_patient_index!
      @effective_default_professional_id = resolve_default_professional_id

      budget_rows = parse_csv(@budgets_csv)
      header_rows = parse_csv(@payment_headers_csv)
      item_rows   = parse_csv(@payment_items_csv)

      @counters[:budgets_total] = budget_rows.group_by { |r| r['BudgetId'].to_s.strip }.size
      @counters[:headers_total] = header_rows.size
      @counters[:items_total]   = item_rows.size

      # Index PaymentHeader sob exato + ambas as formas científicas (mesmo padrão
      # do patient index) — PaymentItem.PaymentHeaderId frequentemente vem
      # truncado em notação científica enquanto PaymentHeader.id vem exato.
      @header_by_clinicorp_id = {}
      header_rows.each do |r|
        exact_id = r['id'].to_s.strip
        next if exact_id.blank?

        @header_by_clinicorp_id[exact_id] ||= r
        scientific_truncations(exact_id).each { |sci| @header_by_clinicorp_id[sci] ||= r }
      end
      flush_progress!

      process_budgets!(budget_rows)
      process_items!(item_rows)
      finalize_buckets!

      flush_progress!(final: true)
      @counters
    end

    # Após processar todos os items, normaliza `installments_count` e
    # `total_in_series` de cada bucket pro número REAL de parcelas dentro dele
    # (active + canceled). Sem isso, parcelas mostram "1/1, 2/6, 3/1, …" na UI
    # porque herdam o `InstallmentsCount` original do Clinicorp (referente à
    # venda original, não ao bucket). Com este finalize, mostram "1/19, 2/19,
    # 3/19, …" — coerente com o que o paciente vê.
    def finalize_buckets!
      @bucket_by_patient.each_value do |bucket_id|
        actual_count = Financial::Installment.where(financial_budget_id: bucket_id, deleted_at: nil).count
        next if actual_count.zero?

        Financial::Budget.where(id: bucket_id).update_all(installments_count: actual_count)
        Financial::Installment.where(financial_budget_id: bucket_id, deleted_at: nil)
                              .update_all(total_in_series: actual_count)
      end
    end

    private

    def blank_counters
      {
        budgets_total: 0, headers_total: 0, items_total: 0,
        processed_budgets: 0, processed_items: 0,
        created_budgets: 0, updated_budgets: 0,
        created_buckets: 0,
        created_items: 0, updated_items: 0,
        created_receipts: 0,
        skipped: 0, errors: 0, warnings: 0
      }
    end

    # Heurística "única clínica unipessoal" — se o admin mapeou exatamente 1
    # dentista (não-ignore), todas as parcelas avulsas e entries herdam esse
    # user_id como professional_id. Resolve o caso comum de clínica com 1
    # dentista titular onde o Clinicorp não traz DentistId em PaymentItem
    # (limitação estrutural — só Budgets tem DentistId, e PaymentItem não
    # linka ao Budget). Multi-dentista (2+ mapeados) → nil, sem default.
    def resolve_default_professional_id
      mapped_ids = @dentist_mapping.values
                                   .reject { |v| v.blank? || v.to_s.downcase == 'ignore' }
                                   .map { |v| v.to_i.positive? ? v.to_i : nil }
                                   .compact
                                   .uniq
      mapped_ids.size == 1 ? mapped_ids.first : nil
    end

    # ── Bank account ─────────────────────────────────────────────────────────

    def resolve_bank_account!
      case @bank_account_strategy
      when 'create'
        Financial::BankAccount.find_by(account_id: @account.id, name: BANK_ACCOUNT_NAME) ||
          Financial::BankAccount.create!(
            account_id: @account.id, name: BANK_ACCOUNT_NAME, kind: 'checking',
            initial_balance_cents: 0, active: true
          )
      when 'existing'
        ba = Financial::BankAccount.where(account_id: @account.id, active: true).order(:id).first
        raise 'Nenhuma conta bancária ativa cadastrada. Crie pelo menos uma conta em Configurações → Contas Bancárias antes de rodar a importação.' if ba.nil?

        ba
      else
        raise "Estratégia de conta bancária desconhecida: #{@bank_account_strategy}"
      end
    end

    # ── Patient index ────────────────────────────────────────────────────────

    # PatientId nos CSVs financeiros pode chegar em 3 formatos por causa do
    # truncamento Excel para IDs longos (16 dígitos):
    #   1) Exato:     "4573620000000000"
    #   2) BR comma:  "4,57362E+15"   (Excel BR locale)
    #   3) US dot:    "4.57362E+15"   (SheetJS / CSV genérico)
    # Indexamos o paciente sob TODOS os formatos pra que o lookup do importer
    # bata independente de como o XLSX foi gerado/convertido pra CSV.
    #
    # Fallback CPF: como Excel arredonda IDs longos pra 6 dígitos significativos,
    # MUITOS pacientes colidem na forma científica (paradox do aniversário com
    # ~2.4k pacientes em ~1.1k buckets). Pra esses casos, usamos OwnerCPF/PayerCPF
    # da própria linha do PaymentItem como segunda chave de match — quase sempre
    # populado em boletos e cartões.
    def preload_patient_index!
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
    end

    def normalize_cpf(value)
      value.to_s.gsub(/\D/, '')
    end

    def register_patient_key(key, patient_id)
      return if key.blank?

      existing = @patient_by_clinicorp_id[key]
      if existing.nil?
        @patient_by_clinicorp_id[key] = patient_id
      elsif existing != patient_id && existing != :collision
        # 2 pacientes exatos colapsam pra mesma forma científica (Excel arredondou).
        # Marcar como collision pra que o lookup pule a parcela (canon: melhor pular
        # do que vincular ao paciente errado).
        @patient_by_clinicorp_id[key] = :collision
      end
    end

    # Gera os 2 formatos científicos (vírgula BR e ponto US) que o Excel
    # produz ao exportar IDs longos. Mantemos paridade com o
    # `scientific_truncation` do clinicorp_patient_importer.rb (que sempre
    # gerava só a vírgula — funciona pra anamneses CSV exportado pelo Excel BR,
    # mas falha pra XLSX convertido por SheetJS que usa ponto).
    def scientific_truncations(exact_id_str)
      digits = exact_id_str.to_s.gsub(/\D/, '')
      return [] if digits.length < 7

      exp = digits.length - 1
      first7 = digits[0, 7].to_i
      rounded6 = (first7 + 5) / 10  # half-up
      if rounded6 >= 1_000_000
        exp += 1
        rounded6 /= 10
      end
      s = format('%06d', rounded6)
      exp_str = format('%02d', exp)
      ["#{s[0]},#{s[1, 5]}E+#{exp_str}", "#{s[0]}.#{s[1, 5]}E+#{exp_str}"]
    end

    # Lookup com tratamento de :collision (paciente ambíguo por arredondamento)
    # e fallback automático por CPF — quando PatientId é ambíguo OU não existe,
    # tenta OwnerCPF/PayerCPF da linha (campos populados em boletos/CC).
    def lookup_patient_id(clinicorp_id, owner_cpf: nil, payer_cpf: nil)
      val = @patient_by_clinicorp_id[clinicorp_id.to_s.strip]
      return val if val.is_a?(Integer)

      # PatientId não bateu (nil) OU collision — tenta CPF.
      [owner_cpf, payer_cpf].each do |cpf|
        cpf_digits = normalize_cpf(cpf)
        next if cpf_digits.length != 11

        pid = @patient_by_cpf[cpf_digits]
        return pid if pid
      end

      nil
    end

    # ── Phase 1: Budgets ─────────────────────────────────────────────────────

    def process_budgets!(rows)
      by_budget = rows.group_by { |r| r['BudgetId'].to_s.strip }

      by_budget.each do |budget_id, budget_rows|
        next if budget_id.blank?

        process_budget(budget_id, budget_rows)
        @counters[:processed_budgets] += 1
        flush_progress! if (@counters[:processed_budgets] % BATCH_SIZE).zero?
      end
      flush_progress!
    end

    def process_budget(budget_id, rows)
      first = rows.first
      patient_id = lookup_patient_id(first['PatientId'])
      if patient_id.nil?
        @counters[:skipped] += 1
        log_warning(budget_id, "Budget '#{budget_id}' ignorado: paciente Clinicorp '#{first['PatientId']}' não foi importado.")
        return
      end

      external_id = "clinicorp_budget_#{budget_id}"
      budget = Financial::Budget.find_or_initialize_by(account_id: @account.id, external_id: external_id)
      was_new = budget.new_record?

      subtotal = rows.sum { |r| parse_cents(r['ProcedureAmount']) || 0 }
      discount = parse_cents(first['BudgetDiscountAmount']) || 0
      total    = parse_cents(first['BudgetAmount']) || (subtotal - discount)

      budget.assign_attributes(
        patient_id: patient_id,
        professional_id: resolve_dentist(first['DentistId'], first['DentistName']),
        origin: 'orcamento',
        status: compute_budget_status(first),
        subtotal_cents: subtotal,
        discount_cents: discount,
        total_cents: total,
        installments_count: [first['BudgetPaymentInstallments'].to_i, 1].max,
        notes: first['BudgetsNotes'].to_s.strip.presence,
        approved_at: parse_date(first['BudgetApprovedDate']),
        canceled_at: parse_date(first['BudgetRejectedDate']),
        cancel_reason: first['BudgetRejectedReason'].to_s.strip.presence,
        metadata: { 'source' => 'clinicorp', 'clinicorp_budget_id' => budget_id }
      )

      if budget.save
        sync_budget_items(budget, rows)
        was_new ? @counters[:created_budgets] += 1 : @counters[:updated_budgets] += 1
        @budget_by_clinicorp_id[budget_id] = budget.id
      else
        @counters[:errors] += 1
        log_error(budget_id, "Budget: #{budget.errors.full_messages.join('; ')}")
      end
    rescue StandardError => e
      @counters[:errors] += 1
      log_error(budget_id, "Budget: #{e.class}: #{e.message}")
    end

    def sync_budget_items(budget, rows)
      budget.items.destroy_all
      rows.each_with_index do |row, idx|
        unit = parse_cents(row['ProcedureFinalAmount']) || parse_cents(row['ProcedureAmount']) || 0
        Financial::BudgetItem.create!(
          account_id: @account.id,
          financial_budget_id: budget.id,
          description: row['ProcedureName'].to_s.strip.presence || 'Procedimento sem nome',
          procedure_code: row['Procedure_CharacteristicId'].to_s.strip.presence,
          quantity: 1,
          unit_price_cents: unit,
          discount_cents: 0,
          total_cents: unit,
          position: idx
        )
      end
    end

    def compute_budget_status(row)
      return 'cancelado' if row['NotApproved'].to_s.strip == 'X'
      return 'cancelado' if row['BudgetRejectedDate'].to_s.strip.present?
      return 'concluido' if row['Executed'].to_s.strip == 'X'
      return 'aprovado' if row['BudgetApproved'].to_s.strip == 'X'

      'rascunho'
    end

    def resolve_dentist(dentist_id, dentist_name)
      key = dentist_id.to_s.strip.presence || dentist_name.to_s.strip
      return nil if key.blank?

      val = @dentist_mapping[key]
      return nil if val.blank? || val == 'ignore'

      val.to_i.positive? ? val.to_i : nil
    end

    # ── Phase 2: Payment items (+ receipts) ──────────────────────────────────

    def process_items!(rows)
      active_rows = rows.reject { |r| canceled?(r) }
      buckets_data = active_rows.group_by { |r| r['PatientId'].to_s.strip }
                                .transform_values { |rs|
                                  { total: rs.sum { |r| parse_cents(r['Amount']) || 0 }, count: rs.size }
                                }

      # Ordena linhas por DueDate ANTES de iterar: `next_bucket_number` atribui
      # `number` incremental conforme as linhas são processadas, então sem este
      # sort o `number` reflete a ordem de export da Clinicorp (aleatória) e
      # quebra a ordem cronológica esperada na timeline do paciente. Tiebreak
      # pelo `id` Clinicorp pra ficar determinístico entre re-runs (importante
      # quando o mesmo paciente tem múltiplas vendas vencendo no mesmo dia).
      # Linhas com DueDate ausente vão pro fim, mantendo `id` como ordem
      # estável dentro desse grupo.
      sorted_rows = rows.sort_by do |r|
        [parse_date(r['DueDate']) || parse_date(r['OriginalDueDate']) || Date.new(9999, 1, 1),
         r['id'].to_s]
      end

      sorted_rows.each_with_index do |row, idx|
        process_installment(row, buckets_data)
        @counters[:processed_items] += 1
        flush_progress! if (idx % BATCH_SIZE).zero?
      end
      flush_progress!
    end

    def process_installment(row, buckets_data)
      item_id = row['id'].to_s.strip
      if item_id.blank?
        @counters[:skipped] += 1
        log_warning('?', 'PaymentItem sem id — linha ignorada.')
        return
      end

      patient_clinicorp_id = row['PatientId'].to_s.strip
      patient_id = lookup_patient_id(patient_clinicorp_id, owner_cpf: row['OwnerCPF'], payer_cpf: row['PayerCPF'])
      if patient_id.nil?
        @counters[:skipped] += 1
        log_warning(item_id, "Item ignorado: paciente Clinicorp '#{patient_clinicorp_id}' não foi importado (e OwnerCPF/PayerCPF não casaram com nenhum paciente).")
        return
      end

      bucket_budget_id = ensure_bucket_budget(patient_id, patient_clinicorp_id, buckets_data)
      return if bucket_budget_id.nil?

      amount_cents = parse_cents(row['Amount']) || 0
      amount_cents = 1 if amount_cents <= 0  # Installment exige > 0
      received_amount_cents = compute_received_amount(row, amount_cents)
      due_date = parse_date(row['DueDate']) || parse_date(row['OriginalDueDate']) || Date.current
      received_at = parse_date(row['ReceivedDate'])
      payment_method = TYPE_TO_METHOD[row['Type'].to_s.strip] || 'dinheiro'

      external_id = "clinicorp_item_#{item_id}"
      installment = Financial::Installment.find_or_initialize_by(account_id: @account.id, external_id: external_id)
      was_new = installment.new_record?

      original_number = positive_or_one(row['InstallmentNumber'])
      attrs = {
        financial_budget_id: bucket_budget_id,
        patient_id: patient_id,
        professional_id: @effective_default_professional_id,
        total_in_series: positive_or_one(row['InstallmentsCount']),
        amount_cents: amount_cents,
        received_amount_cents: received_amount_cents,
        status: compute_installment_status(row, amount_cents, received_amount_cents, due_date),
        payment_method: payment_method,
        due_date: due_date,
        competence_date: parse_date(row['PostDate']) || due_date,
        received_at: received_at,
        gateway: 'manual',
        metadata: {
          'source' => 'clinicorp',
          'clinicorp_item_id' => item_id,
          'clinicorp_type' => row['Type'].to_s,
          'clinicorp_header_id' => row['PaymentHeaderId'].to_s,
          'clinicorp_installment_number' => original_number,
          'clinicorp_installments_count' => positive_or_one(row['InstallmentsCount'])
        }
      }
      # Em re-import (was_new=false), preserva o `number` já gravado pra não
      # mexer no índice único; em criação nova, atribui o próximo da sequência
      # do bucket (carregada do banco na 1ª referência ao bucket).
      attrs[:number] = next_bucket_number(bucket_budget_id) if was_new
      installment.assign_attributes(attrs)

      if installment.save
        sync_receipt(installment, row, patient_id)
        was_new ? @counters[:created_items] += 1 : @counters[:updated_items] += 1
      else
        @counters[:errors] += 1
        log_error(item_id, "Installment: #{installment.errors.full_messages.join('; ')}")
      end
    rescue StandardError => e
      @counters[:errors] += 1
      log_error(item_id, "Item: #{e.class}: #{e.message}")
    end

    # Próximo `number` disponível pro bucket. Em 1ª referência ao bucket, lê
    # o MAX(number) do banco (suporta cenário de re-run após erros: pega a partir
    # do que ficou da rodada anterior). Subsequentes incrementos são em memória.
    def next_bucket_number(bucket_budget_id)
      @bucket_number_sequence[bucket_budget_id] ||=
        (Financial::Installment.where(financial_budget_id: bucket_budget_id, deleted_at: nil).maximum(:number) || 0)
      @bucket_number_sequence[bucket_budget_id] += 1
      @bucket_number_sequence[bucket_budget_id]
    end

    def ensure_bucket_budget(patient_id, patient_clinicorp_id, buckets_data)
      cached = @bucket_by_patient[patient_clinicorp_id]
      return cached if cached

      external_id = "clinicorp_avulsos_#{patient_clinicorp_id}"
      bucket = Financial::Budget.find_by(account_id: @account.id, external_id: external_id)
      if bucket.nil?
        data = buckets_data[patient_clinicorp_id] || { total: 1, count: 1 }
        bucket = Financial::Budget.create!(
          account_id: @account.id,
          patient_id: patient_id,
          professional_id: @effective_default_professional_id,
          external_id: external_id,
          origin: 'orcamento',
          status: 'aprovado',
          subtotal_cents: [data[:total], 1].max,
          discount_cents: 0,
          total_cents: [data[:total], 1].max,
          installments_count: [data[:count], 1].max,
          notes: 'Parcelas importadas da Clinicorp sem orçamento de origem (bucket Avulsos).',
          metadata: { 'source' => 'clinicorp', 'kind' => 'avulsos_bucket', 'patient_clinicorp_id' => patient_clinicorp_id }
        )
        @counters[:created_buckets] += 1
      end

      @bucket_by_patient[patient_clinicorp_id] = bucket.id
    end

    def compute_installment_status(row, amount_cents, received_amount_cents, due_date)
      return 'cancelado' if canceled?(row)
      return 'recebido' if received_amount_cents >= amount_cents && amount_cents.positive?
      return 'parcial' if received_amount_cents.positive?
      return 'vencido' if due_date < Date.current

      'pendente'
    end

    def canceled?(row)
      row['Canceled'].to_s.strip == 'X' || row['CancelInstallment'].to_s.strip == 'X'
    end

    # `PaymentReceived=X` é o gatilho de "parcela quitada" no Clinicorp.
    # `PaidMoneyAmount` guarda só a parcela em dinheiro de pagamentos divididos
    # (cash + card), então não serve como valor recebido canônico — quase
    # sempre fica vazio em pagamentos não-dinheiro. Default robusto:
    #   - Se PaymentReceived=X: PaidMoneyAmount (se > 0) ou Amount integral.
    #   - Caso ReceivedDate populada (alguns CSVs não têm a flag): mesmo
    #     comportamento.
    #   - Senão: 0.
    # Clamp em amount_cents pra evitar received > amount (inconsistência).
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

    def sync_receipt(installment, row, patient_id)
      return if installment.received_amount_cents.zero?
      return unless received?(row)

      item_id = row['id'].to_s.strip
      external_id = "clinicorp_item_#{item_id}"
      receipt = Financial::PaymentReceipt.find_or_initialize_by(account_id: @account.id, external_id: external_id)
      was_new = receipt.new_record?

      header_row = @header_by_clinicorp_id[row['PaymentHeaderId'].to_s.strip]
      partial_flag = header_row && header_row['IsPartialPayment'].to_s.strip == 'X'

      net = installment.received_amount_cents
      receipt.assign_attributes(
        patient_id: patient_id,
        financial_bank_account_id: @bank_account.id,
        payment_method: installment.payment_method,
        gross_amount_cents: net,
        interest_amount_cents: 0,
        fine_amount_cents: 0,
        discount_amount_cents: 0,
        credit_applied_cents: 0,
        net_amount_cents: net,
        received_at: installment.received_at || parse_date(row['PaymentDate']) || Date.current,
        notes: "Importado da Clinicorp (PaymentItem #{item_id}).",
        metadata: {
          'source' => 'clinicorp',
          'clinicorp_item_id' => item_id,
          'clinicorp_header_id' => row['PaymentHeaderId'].to_s,
          'needs_review' => partial_flag
        }
      )

      receipt.save!
      Financial::PaymentReceiptItem.find_or_create_by!(
        account_id: @account.id,
        financial_payment_receipt_id: receipt.id,
        financial_installment_id: installment.id
      ) do |pri|
        pri.amount_cents = net
      end

      # Cria/garante o Financial::Entry vinculado — sem isso, A Receber e
      # prontuário do paciente funcionam (lêem Installment+Receipt direto),
      # mas Fluxo de Caixa e DRE ficam vazios (lêem Entry com affects_cashflow
      # / affects_dre). No fluxo normal o service ReceivePayment cria os dois
      # atomicamente; aqui replicamos a etapa que faltava.
      ensure_entry_for_receipt(receipt, installment, item_id)

      @counters[:created_receipts] += 1 if was_new
    end

    def ensure_entry_for_receipt(receipt, installment, item_id)
      return if receipt.financial_entry_id.present?

      entry = Financial::Entry.create!(
        account_id: @account.id,
        financial_bank_account_id: receipt.financial_bank_account_id,
        patient_id: receipt.patient_id,
        professional_id: installment.professional_id,  # propaga (vem do bucket / default)
        direction: 'in',
        kind: 'receita',
        amount_cents: receipt.net_amount_cents,
        payment_method: receipt.payment_method,
        competence_date: installment.competence_date || receipt.received_at,
        cash_date: receipt.received_at,
        description: "Recebimento Clinicorp · PaymentItem #{item_id}",
        affects_dre: true,
        affects_cashflow: true,
        source_type: 'Financial::PaymentReceipt',
        source_id: receipt.id,
        metadata: { 'source' => 'clinicorp', 'clinicorp_item_id' => item_id }
      )

      receipt.update_column(:financial_entry_id, entry.id)
      @counters[:created_entries] = (@counters[:created_entries] || 0) + 1
    end

    # ── Parsing helpers ──────────────────────────────────────────────────────

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

    # Aceita "1234.56", "1234,56", "1.234,56", "R$ 1.234,56" e devolve em centavos.
    def parse_cents(value)
      return nil if value.nil?

      str = value.to_s.strip
      return nil if str.blank?

      str = str.gsub(/[^\d,.\-]/, '')
      return nil if str.blank?

      # Formato BR (1.234,56) → US (1234.56)
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

    def positive_or_one(value)
      n = value.to_i
      n.positive? ? n : 1
    end

    # ── Progress / logging ──────────────────────────────────────────────────

    def flush_progress!(final: false)
      total = @counters[:budgets_total] + @counters[:items_total]
      processed = @counters[:processed_budgets] + @counters[:processed_items]

      @run.update_columns(
        total_rows: total,
        processed_rows: final ? total : processed,
        created_count: @counters[:created_budgets] + @counters[:created_buckets] + @counters[:created_items] + @counters[:created_receipts],
        updated_count: @counters[:updated_budgets] + @counters[:updated_items],
        skipped_count: @counters[:skipped],
        error_count: @counters[:errors],
        errors_log: @errors.last(200),
        updated_at: Time.current
      )
    end

    def log_error(line, message)
      @errors << { line: line.to_s, level: 'error', message: message }
    end

    def log_warning(line, message)
      @counters[:warnings] += 1
      @errors << { line: line.to_s, level: 'warning', message: message }
    end
  end
end
