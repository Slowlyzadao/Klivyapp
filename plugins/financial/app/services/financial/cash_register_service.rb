module Financial
  # Operações do caixa físico (canon §4.8 + glossário).
  #
  # CashRegisterService.open(...)         → abre sessão diária
  # CashRegisterService.close(...)        → fecha + lança quebra se houver diferença
  # CashRegisterService.supplement(...)   → suprimento (banco → caixa)
  # CashRegisterService.withdraw(...)     → sangria (caixa → banco)
  # CashRegisterService.reopen(...)       → reabre sessão fechada (GERENTE/ADMIN)
  module CashRegisterService
    Result = Financial::ServiceResult

    module_function

    def open(account:, actor:, bank_account:, opening_balance_cents:, session_date: nil, note: nil)
      session_date ||= Date.current
      return Result.failure('conta deve ser do tipo cash') unless bank_account.cash?

      register = nil
      ActiveRecord::Base.transaction do
        register = Financial::CashRegister.create!(
          account_id: account.id,
          financial_bank_account_id: bank_account.id,
          operator_id: actor.id,
          session_date: session_date,
          status: 'open',
          opening_balance_cents: opening_balance_cents,
          opening_note: note,
          opened_at: Time.current
        )
      end

      Result.success(cash_register: register)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    def close(register:, actor:, counted_balance_cents:, note: nil)
      return Result.failure('caixa já está fechado') if register.closed?

      register.lock!
      expected = register.calculated_expected_cents
      diff = counted_balance_cents - expected
      quebra_movement = nil

      ActiveRecord::Base.transaction do
        register.update!(
          status: 'closed',
          expected_balance_cents: expected,
          counted_balance_cents: counted_balance_cents,
          difference_cents: diff,
          closing_note: note,
          closed_at: Time.current,
          closed_by_id: actor.id
        )

        # Quebra de caixa: lança em Outras Despesas (falta) ou Outras Receitas (sobra).
        # Canon §4.8 + CT-CX-05.
        if diff != 0
          quebra_movement = create_quebra_movement(register, actor, diff)
        end
      end

      Result.success(cash_register: register.reload, difference_cents: diff, quebra_movement: quebra_movement)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    def reopen(register:, actor:, reason:)
      return Result.failure('caixa não está fechado') unless register.closed?
      return Result.failure('motivo obrigatório') if reason.blank?

      register.update!(
        status: 'open',
        reopened_at: Time.current,
        reopened_by_id: actor.id,
        reopen_reason: reason
      )
      Result.success(cash_register: register.reload)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    # Suprimento — pega dinheiro do banco e coloca no caixa físico.
    def supplement(register:, actor:, source_bank_account:, amount_cents:, occurred_at: nil, notes: nil)
      occurred_at ||= Time.current
      return Result.failure('caixa fechado') unless register.opened?
      return Result.failure('source deve ser conta bancária (não cash)') if source_bank_account.cash?
      return Result.failure('amount > 0') if amount_cents <= 0

      result = Financial::TransferBetweenAccounts.call(
        account: register.account,
        actor: actor,
        from_bank_account: source_bank_account,
        to_bank_account: register.financial_bank_account,
        amount_cents: amount_cents,
        occurred_at: occurred_at.to_date,
        notes: ['Suprimento de caixa', notes].compact.join(' - ')
      )
      return result if result.failure?

      movement = Financial::CashMovement.create!(
        account_id: register.account_id,
        financial_cash_register_id: register.id,
        financial_bank_account_id: source_bank_account.id,
        kind: 'suprimento',
        amount_cents: amount_cents,
        financial_entry_in_id: result[:entry_in].id,
        financial_entry_out_id: result[:entry_out].id,
        occurred_at: occurred_at,
        registered_by_id: actor.id,
        notes: notes
      )

      register.entries.where(id: result[:entry_in].id).update_all(cash_register_id: register.id)
      Result.success(movement: movement)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    # Sangria — tira dinheiro do caixa físico e coloca em conta bancária.
    def withdraw(register:, actor:, target_bank_account:, amount_cents:, occurred_at: nil, notes: nil)
      occurred_at ||= Time.current
      return Result.failure('caixa fechado') unless register.opened?
      return Result.failure('target não pode ser cash') if target_bank_account.cash?
      return Result.failure('amount > 0') if amount_cents <= 0

      result = Financial::TransferBetweenAccounts.call(
        account: register.account,
        actor: actor,
        from_bank_account: register.financial_bank_account,
        to_bank_account: target_bank_account,
        amount_cents: amount_cents,
        occurred_at: occurred_at.to_date,
        notes: ['Sangria de caixa', notes].compact.join(' - ')
      )
      return result if result.failure?

      movement = Financial::CashMovement.create!(
        account_id: register.account_id,
        financial_cash_register_id: register.id,
        financial_bank_account_id: target_bank_account.id,
        kind: 'sangria',
        amount_cents: amount_cents,
        financial_entry_in_id: result[:entry_in].id,
        financial_entry_out_id: result[:entry_out].id,
        occurred_at: occurred_at,
        registered_by_id: actor.id,
        notes: notes
      )

      register.entries.where(id: result[:entry_out].id).update_all(cash_register_id: register.id)
      Result.success(movement: movement)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    # PRIVATE-ish helper
    def create_quebra_movement(register, actor, diff_cents)
      kind = diff_cents.negative? ? 'quebra_falta' : 'quebra_sobra'
      direction = diff_cents.negative? ? 'out' : 'in'
      kind_entry = diff_cents.negative? ? 'quebra_caixa' : 'quebra_caixa'

      category = quebra_category(register.account_id, diff_cents.negative?)

      entry = Financial::Entry.create!(
        account_id: register.account_id,
        financial_bank_account_id: register.financial_bank_account_id,
        financial_dre_category_id: category&.id,
        direction: direction,
        kind: kind_entry,
        amount_cents: diff_cents.abs,
        competence_date: Date.current,
        cash_date: Date.current,
        description: "Quebra de caixa - #{register.session_date.strftime('%d/%m/%Y')}",
        cash_register_id: register.id,
        affects_dre: true,
        affects_cashflow: true,
        registered_by_id: actor.id
      )

      Financial::CashMovement.create!(
        account_id: register.account_id,
        financial_cash_register_id: register.id,
        kind: kind,
        amount_cents: diff_cents.abs,
        financial_entry_in_id: direction == 'in' ? entry.id : nil,
        financial_entry_out_id: direction == 'out' ? entry.id : nil,
        occurred_at: Time.current,
        registered_by_id: actor.id,
        notes: "Auto-gerado no fechamento de caixa #{register.id}"
      )
    end
    module_function :create_quebra_movement

    def quebra_category(account_id, falta)
      kind = falta ? 'outra_despesa' : 'receita'
      Financial::DreCategory
        .for_account(account_id)
        .where(kind: kind)
        .where('LOWER(name) LIKE ?', '%quebra%')
        .first ||
        Financial::DreCategory
          .for_account(account_id)
          .where(kind: kind, is_default: true)
          .first
    end
    module_function :quebra_category
  end
end
