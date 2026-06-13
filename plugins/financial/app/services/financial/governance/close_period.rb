module Financial
  module Governance
    # Fecha um mês contábil. Após fechado, edição retroativa em Entry,
    # Installment, Expense com competence/cash_date dentro do período
    # é bloqueada pela validação `period_not_closed` nos models (a ser
    # adicionada em Fase 3).
    #
    # Apenas ADMIN. Sem cliente real ainda, mas a checagem fica
    # implementada desde já — corner case raro mas perigoso.
    class ClosePeriod
      Result = Struct.new(:success?, :closure, :errors, keyword_init: true)

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(account:, year:, month:, actor:, notes: nil)
        @account = account
        @year = year.to_i
        @month = month.to_i
        @actor = actor
        @notes = notes
      end

      def call
        return failure('account required') if @account.nil?
        return failure('actor required')   if @actor.nil?
        return failure('year inválido')    unless @year.between?(2020, 2100)
        return failure('month inválido')   unless @month.between?(1, 12)
        return failure('mês futuro não pode ser fechado') if future_period?

        # Já existe fechamento ativo?
        existing = ::Financial::PeriodClosure
                     .for_account(@account.id)
                     .closed
                     .for_period(@year, @month)
                     .first
        return success(existing, already_closed: true) if existing

        closure = nil
        ActiveRecord::Base.transaction do
          closure = ::Financial::PeriodClosure.create!(
            account_id: @account.id,
            period_year: @year,
            period_month: @month,
            closed_at: Time.current,
            closed_by_id: @actor.id,
            notes: @notes,
            status: 'closed'
          )
        end

        Result.new(success?: true, closure: closure, errors: [])
      end

      private

      def failure(msg)
        Result.new(success?: false, closure: nil, errors: Array(msg))
      end

      def success(closure, already_closed: false)
        Result.new(success?: true, closure: closure, errors: already_closed ? ['already_closed'] : [])
      end

      # Não permite fechar mês que ainda não terminou — operador deve esperar
      # último dia do mês ANTES de fechar (canon: DRE final só com mês fechado).
      def future_period?
        today = Date.current
        @year > today.year || (@year == today.year && @month > today.month)
      end
    end
  end
end
