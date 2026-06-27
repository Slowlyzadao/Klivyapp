module Financial
  module Governance
    # Reabre um mês contábil fechado. Apenas ADMIN, com motivo obrigatório
    # (auditoria contábil exige justificativa pra reabertura — não pode
    # ser silenciosa). Após reabrir, edição retroativa volta a ser permitida.
    #
    # NÃO deleta o registro original — apenas muda `status` para 'reopened'
    # + popula `reopened_at`, `reopened_by_id`, `reopen_reason`. Preserva
    # trilha permanente de "houve fechamento E reabertura".
    #
    # Se a clínica quiser fechar de novo depois, cria NOVO PeriodClosure
    # (registro novo, não update). O unique index `idx_uniq_period_closure_active`
    # exige `status = 'closed'` — então só pode haver 1 closed por (year, month),
    # mas múltiplos reopened históricos.
    class ReopenPeriod
      Result = Struct.new(:success?, :closure, :errors, keyword_init: true)

      def self.call(**kwargs)
        new(**kwargs).call
      end

      def initialize(account:, year:, month:, actor:, reason:)
        @account = account
        @year = year.to_i
        @month = month.to_i
        @actor = actor
        @reason = reason.to_s.strip
      end

      def call
        return failure('account required') if @account.nil?
        return failure('actor required')   if @actor.nil?
        return failure('motivo obrigatório (mínimo 10 caracteres)') if @reason.length < 10

        closure = ::Financial::PeriodClosure
                    .for_account(@account.id)
                    .closed
                    .for_period(@year, @month)
                    .first

        return failure("Período #{@month}/#{@year} não está fechado") if closure.nil?

        ActiveRecord::Base.transaction do
          closure.update!(
            status: 'reopened',
            reopened_at: Time.current,
            reopened_by_id: @actor.id,
            reopen_reason: @reason
          )
        end

        Result.new(success?: true, closure: closure.reload, errors: [])
      end

      private

      def failure(msg)
        Result.new(success?: false, closure: nil, errors: Array(msg))
      end
    end
  end
end
