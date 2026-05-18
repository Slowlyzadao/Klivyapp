module AiAgent
  module Tools
    # Read-only financial summary for the active patient — pending and
    # overdue installments. Useful for answering "tenho algo em aberto?" or
    # "qual a data do meu próximo boleto?".
    #
    # Bea must NEVER negotiate, change due dates, or accept partial payments
    # on her own. For anything beyond informing balances, she handsoffs.
    class FinancialStatusTool < BaseTool
      description <<~DESC
        Consulta a situação financeira do paciente atual: parcelas pendentes,
        em atraso e próximo vencimento. Apenas leitura — para qualquer
        negociação, alteração de vencimento ou desconto, transfira para
        atendimento humano.
      DESC

      def execute
        patient = current_patient
        return { found: false, message: 'Paciente não encontrado.' } if patient.nil?
        return { found: false, message: 'Módulo financeiro não disponível.' } unless defined?(::Installment)

        pending = ::Installment.active
                               .where(account_id: account.id, patient_id: patient.id)
                               .where(status: %w[pendente vencido])
                               .order(:due_date)

        {
          found: pending.any?,
          pending_count: pending.size,
          total_pending_cents: (pending.sum(:amount) * 100).to_i,
          overdue_count: pending.where(status: 'vencido').count,
          next_due: pending.first&.then { |inst|
            { due_date: inst.due_date.iso8601, amount: inst.amount.to_f, status: inst.status }
          },
          installments: pending.limit(10).map do |inst|
            {
              id: inst.id,
              number: inst.number,
              amount: inst.amount.to_f,
              due_date: inst.due_date.iso8601,
              status: inst.status
            }
          end
        }
      end
    end
  end
end
