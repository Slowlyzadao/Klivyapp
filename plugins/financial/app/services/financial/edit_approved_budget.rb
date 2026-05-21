module Financial
  # BUG-02 fix: permite editar orçamento aprovado dentro de regras claras.
  # Canon §13 BUG-02:
  #   - Editar parcelas Pendentes: forma, valor, vencimento permitidos.
  #   - Bloquear edição apenas das já Recebidas (Recebido / Parcial / Renegociado / Estornado).
  #   - Permitir excluir orçamento se NENHUMA parcela foi paga; senão, oferecer Cancelar.
  class EditApprovedBudget
    Result = Financial::ServiceResult

    # Atualiza um conjunto de parcelas pendentes do orçamento.
    # @param budget [Financial::Budget]
    # @param actor [User]
    # @param installment_changes [Array<Hash>] cada item: { id:, amount_cents?:, due_date?:, payment_method?: }
    def self.update_installments(budget:, actor:, installment_changes:)
      new(budget: budget, actor: actor).update_installments(installment_changes)
    end

    # Cancela orçamento aprovado: parcelas pendentes vão para 'cancelado'.
    # Se houver parcela paga, NÃO permite excluir — só cancelar (mantém histórico).
    def self.cancel(budget:, actor:, reason: nil)
      new(budget: budget, actor: actor).cancel(reason)
    end

    def initialize(budget:, actor:)
      @budget = budget
      @actor = actor
    end

    def update_installments(changes)
      return Result.failure('Orçamento não aprovado') unless @budget.approved? || @budget.status == 'concluido'
      return Result.failure('nenhuma alteração informada') if changes.blank?

      ids = changes.map { |c| c[:id].to_i }
      installments = @budget.installments.where(id: ids).index_by(&:id)

      changes.each do |c|
        inst = installments[c[:id].to_i]
        return Result.failure("parcela #{c[:id]} não pertence a este orçamento") unless inst
        if locked?(inst)
          return Result.failure("parcela ##{inst.number} não pode ser editada (status #{inst.status}). Estorne antes de editar.")
        end
      end

      ActiveRecord::Base.transaction do
        changes.each do |c|
          inst = installments[c[:id].to_i]
          attrs = {}
          attrs[:amount_cents]   = c[:amount_cents].to_i  if c.key?(:amount_cents)
          attrs[:due_date]       = c[:due_date]           if c.key?(:due_date)
          attrs[:payment_method] = c[:payment_method]     if c.key?(:payment_method)
          inst.update!(attrs) unless attrs.empty?
        end

        # Atualiza total do budget = soma das parcelas vivas.
        # Renegociação fina: também ajusta subtotal_cents preservando o desconto,
        # para manter o invariante total == subtotal - discount (validação do model).
        new_total = @budget.installments.where.not(status: 'cancelado').sum(:amount_cents)
        @budget.update!(
          total_cents: new_total,
          subtotal_cents: new_total + @budget.discount_cents.to_i
        )
      end

      Result.success(budget: @budget.reload, installments: @budget.installments.where(id: ids).to_a)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    def cancel(reason)
      return Result.failure('Orçamento já cancelado') if @budget.canceled?

      ActiveRecord::Base.transaction do
        # Cancela apenas parcelas pendentes/vencidas. Parcelas já recebidas mantêm status.
        @budget.installments.where(status: %w[pendente vencido parcial]).find_each do |inst|
          inst.update!(status: 'cancelado')
          # Estornar provisão de comissão das parcelas canceladas
          inst.commission_entries.where(status: 'provisionada').update_all(status: 'estornada')
        end

        if @budget.has_paid_installments?
          @budget.update!(
            status: 'cancelado',
            canceled_at: Time.current,
            canceled_by_id: @actor&.id,
            cancel_reason: reason
          )
        else
          # Sem parcela paga → marca como cancelado de mesma forma; deletar fisicamente é opcional.
          @budget.update!(
            status: 'cancelado',
            canceled_at: Time.current,
            canceled_by_id: @actor&.id,
            cancel_reason: reason
          )
        end
      end

      Result.success(budget: @budget.reload)
    rescue ActiveRecord::RecordInvalid => e
      Result.failure(e.record.errors.full_messages.join('; '))
    end

    private

    LOCKED_STATUSES = %w[recebido parcial estornado renegociado].freeze

    def locked?(installment)
      LOCKED_STATUSES.include?(installment.status) || installment.received_amount_cents.positive?
    end
  end
end
