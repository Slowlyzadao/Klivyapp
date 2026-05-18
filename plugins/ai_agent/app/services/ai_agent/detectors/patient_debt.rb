module AiAgent
  module Detectors
    # Consulta pendências financeiras do paciente. Reusa a mesma fonte
    # que `FinancialStatusTool` consome (Installment com status pendente
    # ou vencido). Pure read — não muda estado.
    #
    # Retorna `Result(has_debt:, total_cents:, overdue_count:, summary:)`
    # ou nil se não há `Installment` model carregado / paciente não existe.
    class PatientDebt
      Result = Struct.new(:has_debt, :total_cents, :overdue_count, :summary, keyword_init: true)

      def self.check(account:, contact_id:)
        new(account, contact_id).check
      end

      def initialize(account, contact_id)
        @account = account
        @contact_id = contact_id
      end

      def check
        return nil unless defined?(::Installment) && defined?(::Patient)

        patient = ::Patient.active.find_by(account_id: @account.id, contact_id: @contact_id)
        return nil unless patient

        pending = ::Installment.active
                               .where(account_id: @account.id, patient_id: patient.id)
                               .where(status: %w[pendente vencido])

        return Result.new(has_debt: false, total_cents: 0, overdue_count: 0, summary: nil) unless pending.any?

        Result.new(
          has_debt: true,
          total_cents: (pending.sum(:amount) * 100).to_i,
          overdue_count: pending.where(status: 'vencido').count,
          summary: build_summary(pending)
        )
      end

      private

      def build_summary(pending)
        first = pending.order(:due_date).first
        next_part = first ? "Próxima parcela: #{first.amount.to_f.round(2)} em #{first.due_date.strftime('%d/%m/%Y')} (#{first.status})" : ''
        "#{pending.size} parcela(s) em aberto. #{next_part}"
      end
    end
  end
end
