# Agrega o financeiro do paciente para a visualização do portal (PRD §9).
#
# MVP é read-only (Sprint D). Pagamento online (PIX/boleto/cartão) entra na
# Sprint F. O service expõe:
#   - totals: em_aberto / vencido / pago_no_ano
#   - next_due: próxima parcela em aberto
#   - installments: lista filtrada pelo modo do setting (paid_history on/off)
#
# Setting consultado:
#   - financial.show_paid_history (bool) — esconde histórico se false
module PatientPortal
  class FinancialSummary
    LIST_LIMIT = 50

    def initialize(patient:, account:)
      @patient = patient
      @account = account
    end

    def totals
      open_cents     = base.open.sum(:amount_cents) - base.open.sum(:received_amount_cents)
      overdue_cents  = base.where(status: 'vencido').sum(:amount_cents) - base.where(status: 'vencido').sum(:received_amount_cents)
      this_year_paid = base.where(status: %w[recebido parcial])
                           .where('received_at >= ?', Date.current.beginning_of_year)
                           .sum(:received_amount_cents)
      {
        open_amount_cents:    open_cents,
        overdue_amount_cents: overdue_cents,
        paid_year_cents:      this_year_paid,
        open_count:           base.open.count,
        overdue_count:        base.where(status: 'vencido').count
      }
    end

    def next_due
      base.open.order(due_date: :asc).first
    end

    def installments(scope: :all)
      list = case scope
             when :open then base.open
             when :paid then show_paid_history? ? base.paid : base.none
             else            show_paid_history? ? base : base.open
             end
      list.order(due_date: :desc).limit(LIST_LIMIT)
    end

    def find(id)
      base.find(id)
    end

    def show_paid_history?
      val = @account.patient_portal_setting&.financial&.dig('show_paid_history')
      val.nil? ? true : val
    end

    private

    def base
      Financial::Installment.where(account_id: @account.id, patient_id: @patient.id)
                            .where(status: %w[pendente parcial recebido vencido])
    rescue StandardError
      Financial::Installment.none
    end
  end
end
