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
      'BOLETO_EXTERNAL'      => 'boleto',
      'CREDIT_CARD_INTERNAL' => 'credito',
      'PIX'                  => 'pix',
      # PIX_EXTERNAL adicionado 2026-05-25 — apareceu no import Streit #37
      # (gerava warning + fallback 'dinheiro'). Clinicorp usa o sufixo
      # _EXTERNAL pra cobranças processadas fora do gateway interno, mesmo
      # critério que BOLETO_EXTERNAL.
      'PIX_EXTERNAL'         => 'pix',
      'CASH'                 => 'dinheiro',
      'DINHEIRO'             => 'dinheiro'
    }.freeze

    # Display nomes pt-BR usados ao auto-criar PaymentMethod fallback
    # ("Importação Clinicorp · X") quando o admin não mapeou no form.
    KIND_DISPLAY = {
      'dinheiro'              => 'Dinheiro',
      'pix'                   => 'PIX',
      'debito'                => 'Débito',
      'credito'               => 'Crédito',
      'boleto'                => 'Boleto',
      'transferencia'         => 'Transferência',
      'convenio'              => 'Convênio',
      'parcelamento_proprio'  => 'Parcelamento próprio',
      'cheque'                => 'Cheque'
    }.freeze

    # Gateway por Type Clinicorp. Clinicorp NÃO tem integração de gateway
    # online (Asaas/Stripe/PagSeguro) hoje — toda cobrança é "manual" do ponto
    # de vista do Klivy, mesmo cartão de crédito (foi maquininha fora do
    # sistema, não gateway integrado). Mantido como mapa explícito (não literal
    # hardcoded) pra ficar trivial adicionar gateway quando aparecer cliente
    # cujo Clinicorp exporta o processador real. Audit 2026-05-21.
    DEFAULT_GATEWAY = 'manual'.freeze
    TYPE_TO_GATEWAY = Hash.new(DEFAULT_GATEWAY).merge(
      'OTHER'                => 'manual',
      'CREDIT_CARD_EXTERNAL' => 'manual', # maquininha física fora do Klivy
      'DEBIT_CARD_EXTERNAL'  => 'manual',
      'BOLETO_INTERNAL'      => 'manual', # boleto Clinicorp interno, sem rastreio Klivy
      'CREDIT_CARD_INTERNAL' => 'manual',
      'PIX'                  => 'manual',
      'CASH'                 => 'manual',
      'DINHEIRO'             => 'manual'
    ).freeze

    BANK_ACCOUNT_NAME = 'Importação Clinicorp'.freeze

    def initialize(migration_run, budgets_csv:, payment_headers_csv:, payment_items_csv:,
                   dentist_mapping: {}, bank_account_strategy: 'create',
                   bank_account_id: nil, payment_method_mapping: {},
                   specialty_mapping: {})
      @run = migration_run
      @budgets_csv = budgets_csv
      @payment_headers_csv = payment_headers_csv
      @payment_items_csv = payment_items_csv
      @dentist_mapping = (dentist_mapping || {}).transform_keys(&:to_s)
      @bank_account_strategy = bank_account_strategy.to_s.presence || 'create'
      @bank_account_id = bank_account_id.presence&.to_i
      # Mapeamento opcional "kind canônico → payment_method_id do Settings".
      # Ex: { 'pix' => 42, 'credito' => 43 }. Quando setado, parcelas com aquele
      # kind herdam o PaymentMethod escolhido pelo admin (canon Settings). Sem
      # mapping (ou kind ausente do map), o importer auto-cria
      # "Importação Clinicorp · <kind>" como fallback — admin pode renomear/
      # reatribuir depois pelo Settings sem perder integridade dos vínculos.
      @payment_method_mapping = (payment_method_mapping || {}).transform_keys(&:to_s)
      # Mapeamento opcional "Specialty Clinicorp → Financial::DreCategory.id".
      # Ex: { 'Cirurgia' => 453, 'Endodontia' => 451 }. Quando setado, define a
      # categoria DRE de cada Installment/Entry herdando do Budget de origem
      # (Specialty DOMINANTE das rows do Budgets.csv — aquela com maior valor
      # de ProcedureFinalAmount). Sem mapping = nil em `financial_dre_category_id`
      # → operador reclassifica em Configurações → Reclassificar.
      @specialty_mapping = (specialty_mapping || {}).transform_keys(&:to_s)
      @account = migration_run.account
      @errors = []
      @counters = blank_counters
      @bucket_by_patient = {}
      @budget_by_clinicorp_id = {}
      # Cache de PaymentMethod por kind canônico — pre-popula com o mapping
      # do admin no `call`, demais kinds são auto-criados sob demanda em
      # `payment_method_id_for(kind)`. Single source of truth pro id usado em
      # Budget/Installment/Receipt.
      @payment_method_id_by_kind = {}
      # Cache `budget_id → dre_category_id`. Populado em `process_budget`
      # (resolve Specialty dominante → dre_id via @specialty_mapping). Lido
      # em `process_installment` e `ensure_entry_for_receipt` pra herdar.
      @dre_category_id_by_budget = {}
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
      preload_payment_method_mapping!
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
        installments = Financial::Installment.where(financial_budget_id: bucket_id, deleted_at: nil)
        actual_count = installments.count
        next if actual_count.zero?

        # update! em loop (não `update_all`) pra disparar Auditable + validações.
        # Custo: ~N writes a mais por bucket (1 Budget + N Installments). Roda
        # uma vez no fim do import — aceitável em troca da trilha de AuditLog
        # completa exigida pelo canon Financial::* (LGPD/forense).
        bucket = Financial::Budget.find(bucket_id)
        bucket.update!(installments_count: actual_count) if bucket.installments_count != actual_count
        installments.find_each do |inst|
          inst.update!(total_in_series: actual_count) if inst.total_in_series != actual_count
        end
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
        # PR audit 2026-05-21: created_entries faltava do blank_counters,
        # ficava em lazy-init no ensure_entry_for_receipt e nunca aparecia
        # no flush_progress!. Agora inicializado pra ser somado corretamente.
        created_entries: 0,
        skipped: 0, errors: 0, warnings: 0
      }
    end

    # PR audit 2026-05-21: fallback silencioso 'dinheiro' mascarava Type
    # desconhecido da Clinicorp. Agora loga warning quando o valor existe
    # no CSV mas não está no TYPE_TO_METHOD — clínica precisa saber pra
    # eventualmente adicionar suporte ao novo tipo de pagamento.
    def resolve_payment_method(row, item_id)
      raw = row['Type'].to_s.strip.upcase
      return 'dinheiro' if raw.empty?

      mapped = TYPE_TO_METHOD[raw]
      return mapped if mapped

      log_warning(item_id, "Type Clinicorp '#{raw}' não mapeado em TYPE_TO_METHOD — usando 'dinheiro' como fallback. Adicionar no map se aparecer recorrente.")
      'dinheiro'
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
        # `bank_account_id` opcional: admin pode escolher conta específica entre
        # várias ativas. Sem ele, mantém comportamento original (1ª ativa).
        if @bank_account_id
          ba = Financial::BankAccount.where(account_id: @account.id, id: @bank_account_id, active: true).first
          raise "Conta bancária #{@bank_account_id} não encontrada ou inativa para a clínica." if ba.nil?

          return ba
        end

        ba = Financial::BankAccount.where(account_id: @account.id, active: true).order(:id).first
        raise 'Nenhuma conta bancária ativa cadastrada. Crie pelo menos uma conta em Configurações → Contas Bancárias antes de rodar a importação.' if ba.nil?

        ba
      else
        raise "Estratégia de conta bancária desconhecida: #{@bank_account_strategy}"
      end
    end

    # ── PaymentMethod resolve (canon Settings) ───────────────────────────────

    # Pre-popula o cache `@payment_method_id_by_kind` com o mapping vindo do
    # form (admin selecionou "PIX Cielo" pro kind 'pix' etc.). Valida que cada
    # PaymentMethod escolhido existe na conta + tem o kind correto. Kinds não
    # mapeados ficam pra auto-criação on-demand em `payment_method_id_for`.
    def preload_payment_method_mapping!
      return if @payment_method_mapping.blank?

      ids = @payment_method_mapping.values.map(&:to_i).reject(&:zero?).uniq
      methods_by_id = Financial::PaymentMethod.where(account_id: @account.id, id: ids).index_by(&:id)

      @payment_method_mapping.each do |kind, pm_id|
        next if pm_id.blank?

        pm = methods_by_id[pm_id.to_i]
        if pm.nil?
          log_warning('payment_method_mapping', "Forma '#{kind}' mapeada pra PaymentMethod ##{pm_id} que não existe nesta conta — vai usar fallback auto-criado.")
          next
        end
        if pm.kind != kind
          log_warning('payment_method_mapping', "PaymentMethod ##{pm_id} ('#{pm.name}') tem kind='#{pm.kind}', diferente de '#{kind}' que o admin tentou mapear — vai usar fallback auto-criado.")
          next
        end
        @payment_method_id_by_kind[kind] = pm.id
      end
    end

    # Devolve o `payment_method_id` canônico pro kind (já mapeado pelo admin OU
    # auto-criado on-demand). Auto-criação é fallback: name=
    # "Importação Clinicorp · <Display>", provider='Clinicorp'. Admin pode
    # renomear depois pelo Settings sem perder vínculo (FK estável).
    #
    # Returns nil pra kind que não está em Financial::PaymentMethod::KINDS
    # (ex: 'credito_paciente', 'multiplas') — nesses casos a Installment fica
    # sem FK e o operador classifica depois manualmente.
    def payment_method_id_for(kind)
      return nil if kind.blank?
      return nil unless Financial::PaymentMethod::KINDS.include?(kind)

      @payment_method_id_by_kind[kind] ||= begin
        display = KIND_DISPLAY[kind] || kind.to_s.tr('_', ' ').capitalize
        name = "Importação Clinicorp · #{display}"
        pm = Financial::PaymentMethod.where(account_id: @account.id, name: name).first
        pm ||= Financial::PaymentMethod.create!(
          account_id: @account.id,
          kind: kind,
          name: name,
          provider: 'Clinicorp',
          status: 'active',
          # Crédito exige supports_installments=true + max_installments >= 1
          # (validação `credito_must_support_installments` do model).
          supports_installments: kind == 'credito',
          max_installments: kind == 'credito' ? 12 : 1,
          default_bank_account_id: @bank_account.id
        )
        pm.id
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

      # Budget.payment_method_id: sugestão default que ApproveBudget propagaria
      # pras Installments num fluxo novo. Importer pula ApproveBudget (parcelas
      # vêm do PaymentItem com kinds variados), então aqui só preserva o kind
      # que o admin escolheu como default da clínica (1º do mapping) ou nil.
      default_pm_id = @payment_method_mapping.values.map(&:to_i).find(&:positive?)

      # Specialty dominante: row com maior ProcedureFinalAmount define a
      # categoria DRE de TODAS as Installments do Budget. Heurística simples
      # (não quebra Receipt em N entries proporcionais) — basta pra DRE
      # mostrar agregado por especialidade. Operador pode reclassificar items
      # divergentes manualmente em Configurações → Reclassificar.
      dominant_spec = dominant_specialty(rows)
      dre_id = dominant_spec ? @specialty_mapping[dominant_spec.to_s] : nil
      dre_id = dre_id.to_i if dre_id.present?

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
        payment_method_id: default_pm_id,
        metadata: {
          'source' => 'clinicorp',
          'clinicorp_budget_id' => budget_id,
          'dominant_specialty' => dominant_spec
        }.compact
      )

      if budget.save
        sync_budget_items(budget, rows)
        was_new ? @counters[:created_budgets] += 1 : @counters[:updated_budgets] += 1
        @budget_by_clinicorp_id[budget_id] = budget.id
        @dre_category_id_by_budget[budget.id] = dre_id if dre_id
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

    # Specialty dominante das rows do Budget: aquela cuja SOMA de
    # ProcedureFinalAmount é maior. Empate → maior contagem. Strings vazias e
    # lixo numérico (Excel column drift: "1", "5091508143783936") são
    # filtradas via `valid_specialty?` — alfa só, mín 3 chars.
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
      # Alpha-dominant (rejeita IDs numéricos e flag "OPEN" residual)
      v.count('a-zA-Záéíóúâêîôûãõàèç A-ZÁÉÍÓÚÂÊÎÔÛÃÕÀÈÇ').to_f / v.length > 0.7
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

      # PeriodClosure guard: se o competence_date OU received_at cair em mês
      # contábil fechado da conta, parcela vai pro skipped. Operador precisa
      # reabrir o período (Settings → Contador) antes de re-importar. Sem isso,
      # `ReceivePayment#period_closed?` bloquearia o lançamento depois e ficaria
      # parcela órfã no banco.
      blocking = period_closure_blocking_dates(row)
      if blocking.any?
        @counters[:skipped] += 1
        log_warning(item_id, "Parcela ignorada: datas #{blocking.join(', ')} caem em período contábil fechado. Reabra o período em Settings → Contador e re-importe.")
        return
      end

      amount_cents = parse_cents(row['Amount']) || 0
      amount_cents = 1 if amount_cents <= 0  # Installment exige > 0
      received_amount_cents = compute_received_amount(row, amount_cents)
      # PR audit 2026-05-21: data ausente/inválida ANTES caia silenciosamente em
      # Date.current, mascarando dado corrompido (parcela de 2020 virava
      # vencimento de hoje). Agora loga warning explícito e ainda usa today
      # como melhor esforço (Installment exige due_date NOT NULL).
      due_date = parse_date(row['DueDate']) || parse_date(row['OriginalDueDate'])
      if due_date.nil?
        log_warning(item_id, "Vencimento ausente/inválido (DueDate=#{row['DueDate'].inspect}, OriginalDueDate=#{row['OriginalDueDate'].inspect}) — usando hoje (#{Date.current}). Revisar manualmente.")
        due_date = Date.current
      end
      received_at = parse_date(row['ReceivedDate'])
      payment_method = resolve_payment_method(row, item_id)
      gateway        = TYPE_TO_GATEWAY[row['Type'].to_s.strip.upcase]

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
        # Canon V2: FK pra Settings → Forma de Pagamento. Vinda do mapping do
        # admin OU auto-criada como "Importação Clinicorp · X" (fallback).
        payment_method_id: payment_method_id_for(payment_method),
        # DRE category: herda do Budget de origem (Specialty dominante → dre_id
        # via @specialty_mapping). Nil se admin não mapeou → vai pra
        # "sem categoria" e operador reclassifica em Settings → Reclassificar.
        financial_dre_category_id: @dre_category_id_by_budget[bucket_budget_id],
        due_date: due_date,
        competence_date: parse_date(row['PostDate']) || due_date,
        received_at: received_at,
        gateway: gateway,
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

    # Retorna lista de datas (formatadas dd/mm/aaaa) que caem em PeriodClosure
    # fechado pra esta conta. Vazia = OK pra importar. Checa competence (PostDate
    # ou DueDate como fallback) + received (ReceivedDate). Cache em memória
    # por (year, month) — DRE da clínica tipicamente tem 1-2 períodos fechados.
    def period_closure_blocking_dates(row)
      return [] unless period_closures_exist?

      checks = []
      competence = parse_date(row['PostDate']) || parse_date(row['DueDate']) || parse_date(row['OriginalDueDate'])
      received   = parse_date(row['ReceivedDate']) || parse_date(row['PaymentDate'])

      checks << competence if competence && period_month_closed?(competence)
      checks << received   if received   && period_month_closed?(received)
      checks.compact.uniq.map { |d| d.strftime('%d/%m/%Y') }
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
      # PR audit 2026-05-21: PaymentReceipt.received_at também tinha fallback
      # silencioso pra Date.current quando a parcela tem received_amount > 0
      # mas nenhuma das colunas de data está populada. Loga warning agora.
      received_at = installment.received_at || parse_date(row['PaymentDate'])
      if received_at.nil?
        log_warning(item_id, "Recebimento sem data (ReceivedDate/PaymentDate vazios) mas com PaidMoneyAmount > 0 — usando hoje (#{Date.current}). Revisar manualmente.")
        received_at = Date.current
      end

      # Modifier intent (canon `add_modifier_intent_to_payment_receipts`):
      # Clinicorp CSV TEM PaidInterestAmount, PenaltyAmount, DiscountAmount —
      # antes eram ignorados (juros/multa/desconto histórico = 0). Agora
      # preservamos a INTENÇÃO original (sempre 'fixed', valor em reais).
      # Derivamos `gross` pra que o invariante de Receipt feche:
      #   net = gross + interest + fine - discount - credit_applied
      # Como credit_applied=0 e net=received_amount, fica:
      #   gross = received - interest - fine + discount
      # Se a derivação ficar negativa (dado Clinicorp corrompido — desconto
      # maior que o recebimento), cai no comportamento conservador antigo
      # (gross=net, modifiers=0) pra não estourar validação.
      interest_cents = parse_cents(row['PaidInterestAmount']) || 0
      fine_cents     = parse_cents(row['PenaltyAmount']) || 0
      discount_cents = parse_cents(row['DiscountAmount']) || 0
      derived_gross  = net - interest_cents - fine_cents + discount_cents

      use_modifiers = derived_gross >= 0 && (interest_cents + fine_cents + discount_cents).positive?

      gross_cents = use_modifiers ? derived_gross : net
      receipt_interest_cents = use_modifiers ? interest_cents : 0
      receipt_fine_cents     = use_modifiers ? fine_cents     : 0
      receipt_discount_cents = use_modifiers ? discount_cents : 0

      if !use_modifiers && (interest_cents + fine_cents + discount_cents).positive?
        log_warning(item_id, "Modificadores Clinicorp (juros=#{interest_cents}, multa=#{fine_cents}, desconto=#{discount_cents}) inconsistentes com PaidMoneyAmount=#{net} — gross derivado #{derived_gross} negativo. Salvando sem modifier intent (preserva total). Revisar manualmente.")
      end

      receipt.assign_attributes(
        patient_id: patient_id,
        financial_bank_account_id: @bank_account.id,
        payment_method: installment.payment_method,
        gross_amount_cents: gross_cents,
        interest_amount_cents: receipt_interest_cents,
        fine_amount_cents: receipt_fine_cents,
        discount_amount_cents: receipt_discount_cents,
        credit_applied_cents: 0,
        net_amount_cents: net,
        # Modifier intent (canon V2): tipo fixo em R$ pra dados históricos
        # (Clinicorp não tem informação de "foi % ou R$ digitado"). Valor em
        # reais (não centavos) — coluna NUMERIC(10,2).
        interest_type: 'fixed',
        interest_value: BigDecimal(receipt_interest_cents) / 100,
        fine_type: 'fixed',
        fine_value: BigDecimal(receipt_fine_cents) / 100,
        discount_type: 'fixed',
        discount_value: BigDecimal(receipt_discount_cents) / 100,
        received_at: received_at,
        notes: "Importado da Clinicorp (PaymentItem #{item_id}).",
        metadata: {
          'source' => 'clinicorp',
          'clinicorp_item_id' => item_id,
          'clinicorp_header_id' => row['PaymentHeaderId'].to_s,
          'needs_review' => partial_flag,
          'clinicorp_modifiers_imported' => use_modifiers
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
        # DRE category herdada da Installment (que herdou do Budget de origem).
        # Mantém DRE coerente quando lê via Entry (caminho Fluxo de Caixa) OU
        # via Installment (caminho A Receber).
        financial_dre_category_id: installment.financial_dre_category_id,
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

      # PR audit 2026-05-21: trocado update_column por update! pra disparar
      # callbacks/AuditLog do Financial::PaymentReceipt (regra arquitetural
      # `project_financeiro_arch_decisions` — AuditLog automático em todo
      # modelo Financial::*). update_column pula callbacks por design.
      receipt.update!(financial_entry_id: entry.id)
      @counters[:created_entries] += 1
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
