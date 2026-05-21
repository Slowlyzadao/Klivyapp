module Financial
  # Transferência interna entre contas bancárias (canon §4.2 + CT-CC-03 + CHK-43).
  # Gera 2 entries (saída na origem, entrada no destino) com kind=transferencia
  # e affects_dre=false — não soma no DRE (movimento neutro).
  class TransferBetweenAccounts
    Result = Financial::ServiceResult

    def self.call(**kwargs) = new(**kwargs).call

    def initialize(account:, actor:, from_bank_account:, to_bank_account:,
                   amount_cents:, occurred_at: nil, notes: nil)
      @account = account
      @actor = actor
      @from = from_bank_account
      @to = to_bank_account
      @amount_cents = amount_cents.to_i
      @date = occurred_at || Date.current
      @notes = notes
    end

    def call
      return Result.failure('amount_cents > 0 obrigatório') if @amount_cents <= 0
      return Result.failure('contas devem ser diferentes') if @from.id == @to.id
      return Result.failure('saldo insuficiente na conta origem') if @from.current_balance_cents < @amount_cents

      out_entry = nil
      in_entry = nil

      ActiveRecord::Base.transaction do
        out_entry = Financial::Entry.create!(
          account_id: @account.id,
          financial_bank_account_id: @from.id,
          direction: 'out',
          kind: 'transferencia',
          amount_cents: @amount_cents,
          competence_date: @date,
          cash_date: @date,
          description: build_description(:out),
          affects_dre: false,
          affects_cashflow: true,
          registered_by_id: @actor&.id
        )

        in_entry = Financial::Entry.create!(
          account_id: @account.id,
          financial_bank_account_id: @to.id,
          direction: 'in',
          kind: 'transferencia',
          amount_cents: @amount_cents,
          competence_date: @date,
          cash_date: @date,
          description: build_description(:in),
          affects_dre: false,
          affects_cashflow: true,
          registered_by_id: @actor&.id,
          transfer_pair_id: out_entry.id
        )

        out_entry.update!(transfer_pair_id: in_entry.id)
      end

      Result.success(entry_out: out_entry, entry_in: in_entry)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    def build_description(side)
      verb = side == :out ? 'para' : 'de'
      counterpart = side == :out ? @to.name : @from.name
      base = "Transferência #{verb} #{counterpart}"
      @notes.present? ? "#{base} - #{@notes}" : base
    end
  end
end
