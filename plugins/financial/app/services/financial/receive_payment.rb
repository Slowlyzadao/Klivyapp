module Financial
  # Recebe pagamento de 1..N parcelas em um único movimento.
  # Cadeia de efeitos atomica (canon backlog Parte I §2.2):
  #   1. Atualiza received_amount_cents de cada Installment
  #   2. Cria PaymentReceipt + PaymentReceiptItem por parcela
  #   3. Cria Financial::Entry de entrada na conta de destino
  #   4. Atualiza CommissionEntry: provisionada → devida (com snapshot final)
  #   5. Atualiza status do Budget (concluido se todas as parcelas pagas)
  #   6. Aplica crédito do paciente se solicitado
  #   7. Lança crédito de excedente (se net > total devido)
  #   8. Bloqueia se a conta destino é caixa físico (cash) e o caixa não está aberto na data
  #
  # BUG-01 fix:
  #   - amount_to_apply pode ser MENOR que installment.remaining_cents (baixa parcial).
  #   - Cria nova installment de saldo restante via partial_keep_installment_open=true
  #     (default) — installment original fica com status='parcial' e a nova com 'pendente'.
  class ReceivePayment
    Result = Financial::ServiceResult

    # @param installment_amounts [Array<Hash>]
    #   Array de { installment_id:, amount_cents: } indicando quanto aplicar a cada parcela.
    # @param account [Account]
    # @param actor [User]
    # @param bank_account [Financial::BankAccount] conta destino do dinheiro
    # @param payment_method [String]
    # @param received_at [Date]
    # @param interest_cents [Integer] juros aplicados (0)
    # @param fine_cents [Integer] multa aplicada (0)
    # @param discount_cents [Integer] desconto concedido (0)
    # @param apply_patient_credit_cents [Integer] valor de crédito do paciente a abater (0)
    # @param notes [String] opcional
    # @param keep_installment_open [Boolean] em baixa parcial, abrir nova parcela com saldo restante (default true)
    # @return [Result]
    def self.call(**kwargs)
      new(**kwargs).call
    end

    def initialize(account:, actor:, bank_account:, installment_amounts:, payment_method:,
                   payment_method_record: nil,
                   received_at: nil,
                   interest_cents: 0, interest_type: 'fixed', interest_value: 0,
                   fine_cents: 0,     fine_type: 'fixed',     fine_value: 0,
                   discount_cents: 0, discount_type: 'fixed', discount_value: 0,
                   apply_patient_credit_cents: 0, notes: nil, keep_installment_open: true,
                   auto_settled: false)
      @account = account
      @actor = actor
      @bank_account = bank_account
      @rows = installment_amounts
      @payment_method = payment_method
      # Refactor 2026-05-24: PaymentMethod específico configurado em Settings.
      # Opcional pra compat — quando vier, é gravado em Installment.payment_method_id
      # e usado pelo `freeze_payment_fee_snapshot!` (mais preciso que lookup por kind).
      @payment_method_record = payment_method_record
      # Garante Date (controller passa String) — vários callees fazem `.year`
      # e `.strftime` direto na ref, e string quebra com NoMethodError.
      @received_at = if received_at.blank?
                       Date.current
                     elsif received_at.is_a?(String)
                       Date.parse(received_at)
                     else
                       received_at.to_date
                     end
      # Modificadores: cents = valor final aplicado; type/value = intenção
      # original do operador (preservada pra recibos, relatórios, auditoria).
      @interest_cents = interest_cents.to_i
      @interest_type  = interest_type
      @interest_value = interest_value.to_f
      @fine_cents = fine_cents.to_i
      @fine_type  = fine_type
      @fine_value = fine_value.to_f
      @discount_cents = discount_cents.to_i
      @discount_type  = discount_type
      @discount_value = discount_value.to_f
      @apply_credit_cents = apply_patient_credit_cents.to_i
      @notes = notes
      @keep_open = keep_installment_open
      # `auto_settled`: baixa programática (AutoSettleCardInstallmentsJob), sem
      # operador nem gateway confirmando no momento. Marca cada Installment p/
      # conciliação contra o extrato da adquirente identificar swipe que falhou.
      @auto_settled = auto_settled
    end

    def call
      return Result.failure('nenhuma parcela informada') if @rows.blank?
      return Result.failure('payment_method inválido') unless Financial::Installment::PAYMENT_METHODS.include?(@payment_method)

      installments = load_installments
      return Result.failure('parcela(s) não encontrada(s) ou inválidas') if installments.size != @rows.size

      # ALTO-SVC-01: parcelas DEVEM ser do mesmo budget e mesmo paciente.
      # Sem essa validação, um recibo podia agrupar parcelas de tratamentos
      # diferentes (mesmo paciente OK) — quebra rastreabilidade contábil.
      coherence = validate_coherence(installments)
      return coherence if coherence.failure?

      # Period closure: bloqueia recebimento com data em mês fechado contábil.
      if ::Financial::PeriodClosure.closed_for?(@account.id, @received_at)
        return Result.failure(
          "Operação bloqueada — #{@received_at.strftime('%m/%Y')} é período contábil fechado. " \
          'Reabrir via Governance::ReopenPeriod (ADMIN) ou usar data dentro de período aberto.'
        )
      end

      validation = validate_inputs(installments)
      return validation if validation.failure?

      cash_check = ensure_cash_register_open_if_needed
      return cash_check if cash_check.failure?

      patient = installments.first.patient
      check_credit = validate_patient_credit(patient)
      return check_credit if check_credit.failure?

      receipt = nil
      entry = nil
      new_installments_for_remainder = []
      commission_updates = []

      ActiveRecord::Base.transaction do
        # Lock pessimista + RELOAD pós-lock. Auditoria 2026-05-22
        # (`CRIT-SVC-06`): snapshot anterior era tirado da coleção carregada
        # ANTES do lock — outras transações que atualizassem `received_amount_cents`
        # entre o load e o lock causavam `remaining_cents` stale. Agora cada
        # installment é reloaded depois do lock pra refletir estado pós-locks.
        # Ordem estável (sort_by(&:id)) evita deadlock em cenários multi-parcela.
        installments = installments.sort_by(&:id).map do |inst|
          inst.lock!
          inst.reload
        end

        # Snapshot do total a receber ANTES de qualquer update — base correta
        # pra detectar pagamento excedente. Sem snapshot, o cálculo lia
        # `remaining_cents` após o update das parcelas (= 0 quando tudo
        # quitado), gerando excess fantasma = total pago.
        total_due_before_update = installments.sum(&:remaining_cents)

        # Snapshot da taxa (PaymentMethodFee) AGORA — congela no Installment.
        # Auditoria `CRIT-CALC-01`: MDR vinha hardcoded; agora vem da
        # configuração da clínica via PaymentMethodFee, com vigência respeitada.
        installments.each { |inst| freeze_payment_fee_snapshot!(inst) }

        gross_cents = total_gross_cents
        net_cents   = compute_net_cents(gross_cents)

        # Override de método quando o crédito do paciente cobre 100% do valor
        # devido: o método registrado deve ser `credito_paciente`, não o que
        # o usuário pré-selecionou no modal (PIX por default). Reflete a
        # realidade contábil — não houve PIX, foi consumo de saldo a favor.
        effective_payment_method = if net_cents.zero? && @apply_credit_cents.positive?
                                     'credito_paciente'
                                   else
                                     @payment_method
                                   end

        # 1) Cria o receipt (mestre)
        receipt = Financial::PaymentReceipt.create!(
          account_id: @account.id,
          patient_id: patient.id,
          financial_bank_account_id: @bank_account.id,
          received_by_id: @actor&.id,
          payment_method: effective_payment_method,
          gross_amount_cents: gross_cents,
          interest_amount_cents: @interest_cents,
          interest_type:  @interest_type,
          interest_value: @interest_value,
          fine_amount_cents: @fine_cents,
          fine_type:  @fine_type,
          fine_value: @fine_value,
          discount_amount_cents: @discount_cents,
          discount_type:  @discount_type,
          discount_value: @discount_value,
          credit_applied_cents: @apply_credit_cents,
          net_amount_cents: net_cents,
          received_at: @received_at,
          notes: @notes
        )

        # 2) Cria os items + atualiza installments (baixa parcial → BUG-01 fix)
        @rows.each do |row|
          inst = installments.find { |i| i.id == row[:installment_id].to_i }
          amount_to_apply = row[:amount_cents].to_i

          Financial::PaymentReceiptItem.create!(
            account_id: @account.id,
            financial_payment_receipt_id: receipt.id,
            financial_installment_id: inst.id,
            amount_cents: amount_to_apply
          )

          # Cap `received_amount_cents` em `amount_cents`: o excedente vai para
          # PatientCredit (calculado depois), não infla a parcela. Sem cap, uma
          # parcela de R$ 485 que recebe R$ 500 ficaria com received=500 e
          # amount=485 (estado contabilmente inválido).
          would_be_received = inst.received_amount_cents + amount_to_apply
          new_received = [would_be_received, inst.amount_cents].min
          new_status =
            if new_received >= inst.amount_cents
              'recebido'
            else
              'parcial'
            end

          inst.update!(
            received_amount_cents: new_received,
            received_at: (new_status == 'recebido' ? @received_at : inst.received_at),
            payment_method: effective_payment_method,
            # Refactor 2026-05-24: grava o PaymentMethod específico escolhido
            # (provider + alias). Permite relatórios/auditoria diferenciarem
            # "PIX Cielo" de "PIX Stone". Nil quando vier só via legacy enum.
            payment_method_id: @payment_method_record&.id,
            auto_settled: @auto_settled,
            status: new_status
          )

          # BUG-01: se baixa parcial e keep_open, gera nova parcela com saldo
          # restante. A parcela original "encerra" com o valor efetivamente pago
          # — `amount_cents` é rebatizado para o que foi recebido (R$ 300 em vez
          # do original R$ 570), evitando que a UI mostre "R$ 570 PAGO" inflando
          # o total. O saldo já está numa parcela nova.
          if new_status == 'parcial' && @keep_open
            remainder = inst.amount_cents - new_received
            new_installments_for_remainder << create_remainder_installment(inst, remainder)
            inst.update!(
              status: 'recebido',
              amount_cents: new_received,     # rebatiza para o valor efetivamente pago
              received_at: @received_at
            )
          end

          # 4) Comissão: provisionada → devida (snapshot final com deduções)
          comm_update = update_commission_for_partial_or_full(inst, amount_to_apply)
          commission_updates << comm_update if comm_update
        end

        # 7) Aplica crédito do paciente (debit ledger)
        if @apply_credit_cents.positive?
          Financial::PatientCredit.create!(
            account_id: @account.id,
            patient_id: patient.id,
            amount_cents: -@apply_credit_cents,
            origin: 'abatimento_parcela',
            origin_type: 'Financial::PaymentReceipt',
            origin_id: receipt.id,
            registered_by_id: @actor&.id,
            occurred_at: Time.current,
            description: "Abatimento aplicado no recibo #{receipt.receipt_number}"
          )
        end

        # 7b) Excedente como crédito (se houver).
        # `total_due_before_update` = soma dos remaining ANTES das updates.
        # Compara com `gross_paid` (soma dos valores aplicados em cada parcela)
        # — só configura excedente quando o usuário pagou mais que o devido,
        # NÃO quando o crédito cobriu o devido (caso em que gross == due).
        excess = compute_excess_cents(total_due: total_due_before_update)
        if excess.positive?
          Financial::PatientCredit.create!(
            account_id: @account.id,
            patient_id: patient.id,
            amount_cents: excess,
            origin: 'pagamento_excedente',
            origin_type: 'Financial::PaymentReceipt',
            origin_id: receipt.id,
            registered_by_id: @actor&.id,
            occurred_at: Time.current,
            description: "Excedente do recibo #{receipt.receipt_number}"
          )
        end

        # 3) Cria Entry de entrada efetiva (Fluxo de Caixa + DRE) — SÓ se
        # houve entrada efetiva de dinheiro na conta. Quando o crédito do
        # paciente cobre 100% do valor (`net_cents == 0`), não há fluxo de
        # caixa novo: foi só consumo do saldo a favor existente. O recibo
        # e a baixa da parcela continuam acontecendo normalmente; o PatientCredit
        # é decrementado no passo de `apply_credit`. Pular a Entry evita
        # `amount_cents > 0` validation error sem impacto contábil (DRE também
        # não muda — a receita já foi reconhecida quando o orçamento aprovou).
        if net_cents.positive?
          revenue_category_id = primary_revenue_category_id(installments)
          entry = Financial::Entry.create!(
            account_id: @account.id,
            financial_bank_account_id: @bank_account.id,
            financial_dre_category_id: revenue_category_id,
            patient_id: patient.id,
            professional_id: installments.first.professional_id,
            direction: 'in',
            kind: 'receita',
            amount_cents: net_cents,
            payment_method: effective_payment_method,
            competence_date: @received_at,    # regime competência: a data do recebimento marca a baixa
            cash_date: @received_at,          # regime caixa: efetivamente entrou hoje
            description: "Recebimento #{receipt.receipt_number} - #{patient.name}",
            source_type: 'Financial::PaymentReceipt',
            source_id: receipt.id,
            affects_dre: true,
            affects_cashflow: true,
            cash_register_id: open_cash_register_id_if_cash,
            registered_by_id: @actor&.id
          )

          # Vincula entry no receipt
          receipt.update!(financial_entry_id: entry.id)
        end

        # 5) Status do Budget: se todas as installments estão recebidas → concluido
        update_budget_statuses(installments)

        # 6) Lança Entry adicional para juros/multa em "Outras Receitas"
        # (Apenas para o DRE — já estão no net acima, mas categoria diferente)
        # Decisão pragmática: NÃO duplica entry; mantemos simples no MVP.
      end

      Result.success(
        receipt: receipt,
        entry: entry,
        new_installments: new_installments_for_remainder,
        commission_updates: commission_updates
      )
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    def load_installments
      ids = @rows.map { |r| r[:installment_id].to_i }
      Financial::Installment.where(id: ids, account_id: @account.id).to_a
    end

    def total_gross_cents
      @rows.sum { |r| r[:amount_cents].to_i }
    end

    def compute_net_cents(gross_cents)
      gross_cents + @interest_cents + @fine_cents - @discount_cents - @apply_credit_cents
    end

    def validate_inputs(installments)
      installments.each do |inst|
        row = @rows.find { |r| r[:installment_id].to_i == inst.id }
        amount = row[:amount_cents].to_i

        return Result.failure("amount_cents da parcela ##{inst.number} deve ser > 0") if amount <= 0
        return Result.failure("parcela ##{inst.number} já estornada") if inst.status == 'estornado'
        return Result.failure("parcela ##{inst.number} cancelada") if inst.status == 'cancelado'
        return Result.failure("parcela ##{inst.number} renegociada") if inst.status == 'renegociado'

        if amount > inst.remaining_cents
          # excedente vira crédito do paciente — só valido por receipt, não por linha individual.
          return Result.failure("amount_cents da parcela ##{inst.number} excede saldo restante. " \
                                'Use uma única parcela e o excedente vira crédito.') if installments.size > 1
        end
      end

      Result.success(valid: true)
    end

    # Caixa físico: bloqueia recebimento em dinheiro com data em sessão fechada.
    def ensure_cash_register_open_if_needed
      return Result.success(skip: true) unless @bank_account.cash?

      open_register = Financial::CashRegister
                      .for_account(@account.id)
                      .where(financial_bank_account_id: @bank_account.id, session_date: @received_at, status: 'open')
                      .first

      if open_register.nil?
        return Result.failure("Caixa do dia #{@received_at.strftime('%d/%m/%Y')} está fechado. Reabra antes de lançar recebimento em dinheiro.")
      end

      Result.success(cash_register: open_register)
    end

    def open_cash_register_id_if_cash
      return nil unless @bank_account.cash?

      Financial::CashRegister
        .for_account(@account.id)
        .where(financial_bank_account_id: @bank_account.id, session_date: @received_at, status: 'open')
        .pick(:id)
    end

    def validate_patient_credit(patient)
      return Result.success unless @apply_credit_cents.positive?

      balance = Financial::PatientCredit.balance_cents_for(account_id: @account.id, patient_id: patient.id)
      if balance < @apply_credit_cents
        return Result.failure("Crédito do paciente insuficiente: disponível R$ #{balance / 100.0}")
      end

      Result.success
    end

    # Excedente = valor que o usuário aplicou nas parcelas A MAIS do que o
    # total devido (`total_due`). `total_due` deve vir do snapshot ANTES do
    # update das installments — depois do update, todas estão quitadas e o
    # cálculo daria excess = total_pago (bug pré-2026-05-12).
    def compute_excess_cents(total_due:)
      total_paid_to_installments = @rows.sum { |r| r[:amount_cents].to_i }
      [total_paid_to_installments - total_due, 0].max
    end

    def primary_revenue_category_id(installments)
      installments.first.financial_dre_category_id ||
        Financial::DreCategory
          .for_account(@account.id)
          .where(kind: 'receita', is_default: true)
          .pick(:id)
    end

    # Ao receber parte/todo de uma parcela, calcula a comissão devida sobre o que foi
    # efetivamente recebido. A provisão é substituída por uma entrada 'devida' com base
    # no amount_to_apply (canon §4.3 — comissão sobre RECEBIDO).
    def update_commission_for_partial_or_full(installment, amount_received_cents)
      provision = installment.commission_entries.find_by(status: 'provisionada')
      return nil unless provision

      rule = provision.commission_rule
      mdr = rule&.deduct_mdr ? mdr_deduction_for(@payment_method, amount_received_cents) : 0
      lab = 0  # placeholder — vinculação Lab por procedimento ainda não implementada
      calc_base = amount_received_cents - mdr - lab

      commission_cents =
        if rule&.kind == 'valor_fixo'
          # comissão fixa: paga uma única vez por parcela quitada totalmente
          installment.fully_paid? ? rule.fixed_amount_cents.to_i : 0
        else
          ((calc_base * provision.percent_basis_points.to_i) / 10_000.0).round
        end

      provision.update!(
        status: 'devida',
        base_amount_cents: amount_received_cents,
        mdr_deduction_cents: mdr,
        lab_deduction_cents: lab,
        calc_base_cents: calc_base,
        commission_amount_cents: commission_cents,
        competence_date: @received_at
      )
      provision
    end

    # Auditoria 2026-05-22 (`CRIT-CALC-01`): MDR vem de PaymentMethodFee
    # cadastrada pela clínica, não de tabela hardcoded.
    #
    # Lookup: (account, payment_method.kind = string passada pelo modal,
    # installments_count = total_in_series do installment, vigência = received_at).
    # Quando há múltiplos PaymentMethods do mesmo kind (ex: "Cielo Crédito" +
    # "GetNet Crédito"), usa o que tiver fee vigente — se nenhum, fee=0.
    #
    # Disambiguação real virá em Fase 4 quando o frontend passar
    # `payment_method_id` em vez de string.
    def mdr_deduction_for(payment_method, amount_cents)
      fee = lookup_fee_for(payment_method, installments_count_for_lookup)
      return 0 if fee.nil?

      fee.calculate_fee_cents(amount_cents)
    end

    def lookup_fee_for(payment_method_kind, installments_count)
      # Cache de lookup por kind pra evitar N+1 quando múltiplas parcelas.
      @fee_cache ||= {}
      key = [payment_method_kind, installments_count]
      return @fee_cache[key] if @fee_cache.key?(key)

      methods = ::Financial::PaymentMethod
                  .for_account(@account.id)
                  .alive
                  .where(kind: payment_method_kind, status: 'active')
                  .to_a

      fee = methods.lazy.filter_map do |m|
        m.fee_for(installments_count: installments_count, on_date: @received_at)
      end.first

      @fee_cache[key] = fee
    end

    def installments_count_for_lookup
      # MDR por transação: usa o parcelamento DA PERNA (card_installments) quando
      # houver — cai no total_in_series senão. Sem isso, "Cielo 3x" dentro de um
      # plano de 5 parcelas buscava a taxa de 5x (errada).
      first = @rows.first
      inst = Financial::Installment.find_by(id: first[:installment_id])
      inst ? inst.effective_installments_count : 1
    end

    # Congela o snapshot de taxa no Installment ANTES de processar o
    # recebimento. Cada parcela passa a ter `payment_method_fee_id`,
    # `fee_percent_basis_points`, `fee_fixed_cents`, `fee_amount_cents`,
    # `net_amount_cents` preenchidos imutavelmente — frozen_attributes do
    # model bloqueia update posterior.
    #
    # Idempotente: se já tem snapshot (parcela paga antes), só recalcula
    # se ainda não foi vinculada a fee.
    def freeze_payment_fee_snapshot!(inst)
      return if inst.payment_method_fee_id.present?  # já congelado

      installments_count = inst.effective_installments_count
      # Refactor 2026-05-24: quando temos o PaymentMethod específico (escolhido
      # no modal), lookup é determinístico — pega a fee DESSE method (não de
      # qualquer outro do mesmo kind). Fallback pro lookup por kind quando o
      # caller não passou o record (compat com callers legacy).
      fee = if @payment_method_record
              @payment_method_record.fee_for(installments_count: installments_count, on_date: @received_at)
            else
              lookup_fee_for(@payment_method, installments_count)
            end
      fee_amount = fee ? fee.calculate_fee_cents(inst.amount_cents) : 0
      net = inst.amount_cents - fee_amount

      # Fix 2026-05-24: `update_columns` no Rails 7.1.5+ valida `attr_readonly`
      # (mudou de versões anteriores), e `payment_method_fee_id` está em
      # `frozen_attributes` (que aplica attr_readonly). Trocamos por
      # `update_all` (SQL raw via scope) — esse SIM bypassa attr_readonly
      # legitimamente, pois estamos congelando o snapshot inicial (não há
      # snapshot anterior pra mutar). Reload em seguida pra refletir em memória.
      Financial::Installment.where(id: inst.id).update_all(
        payment_method_fee_id: fee&.id,
        fee_percent_basis_points: fee&.fee_percent_basis_points,
        fee_fixed_cents: fee&.fee_fixed_cents.to_i,
        fee_amount_cents: fee_amount,
        net_amount_cents: net,
        expected_liquidation_date: fee ? @received_at + fee.liquidation_days.days : nil,
        updated_at: Time.current
      )
      inst.reload
    end

    # Coerência multi-parcela: todas as installments devem pertencer ao
    # MESMO budget e MESMO paciente. Sem essa checagem, recibo pode agrupar
    # parcelas de tratamentos diferentes — quebra rastreabilidade.
    def validate_coherence(installments)
      budget_ids = installments.map(&:financial_budget_id).compact.uniq
      if budget_ids.size > 1
        return Result.failure(
          'Não é possível receber parcelas de orçamentos diferentes em um único recibo. ' \
          'Faça um recibo por orçamento.'
        )
      end

      patient_ids = installments.map(&:patient_id).compact.uniq
      if patient_ids.size > 1
        return Result.failure(
          'Não é possível receber parcelas de pacientes diferentes em um único recibo.'
        )
      end

      Result.success(coherent: true)
    end

    def create_remainder_installment(original, remainder_cents)
      # Insere logicamente como nova parcela ao final da série, com vencimento +30 dias.
      Financial::Installment.create!(
        account_id: original.account_id,
        financial_budget_id: original.financial_budget_id,
        patient_id: original.patient_id,
        professional_id: original.professional_id,
        financial_dre_category_id: original.financial_dre_category_id,
        number: next_number_for_budget(original.financial_budget_id),
        total_in_series: original.total_in_series + 1,
        amount_cents: remainder_cents,
        received_amount_cents: 0,
        status: 'pendente',
        payment_method: original.payment_method,
        due_date: original.due_date + 30.days,
        competence_date: original.competence_date,
        replaces_installment_id: original.id,
        notes: "Saldo de parcela ##{original.number} em baixa parcial"
      )
    end

    def next_number_for_budget(budget_id)
      (Financial::Installment.where(financial_budget_id: budget_id).maximum(:number) || 0) + 1
    end

    def update_budget_statuses(installments)
      budget_ids = installments.map(&:financial_budget_id).uniq
      Financial::Budget.where(id: budget_ids).find_each do |b|
        unpaid = b.installments.where.not(status: %w[recebido cancelado]).count
        b.update!(status: 'concluido') if unpaid.zero? && b.status == 'aprovado'
      end
    end
  end
end
