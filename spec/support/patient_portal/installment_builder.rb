# Helper para construir Financial::Budget + Installment nos specs do portal.
# Não usamos FactoryBot porque o plugin Financial não expõe factories — tudo
# fica self-contained e fácil de seguir.
module PatientPortalSpecSupport
  module InstallmentBuilder
    def build_paid_installment_target(account:, patient:, amount_cents: 30_000, due_date: 7.days.from_now.to_date)
      professional = create(:user, :administrator, account: account)
      budget = Financial::Budget.create!(
        account_id: account.id, patient_id: patient.id, professional_id: professional.id,
        origin: 'orcamento', status: 'aprovado',
        subtotal_cents: amount_cents, total_cents: amount_cents, installments_count: 1,
        approved_at: 1.day.ago, valid_until: 6.months.from_now
      )
      Financial::Installment.create!(
        account_id: account.id, financial_budget_id: budget.id,
        patient_id: patient.id, professional_id: professional.id,
        number: 1, total_in_series: 1,
        amount_cents: amount_cents, received_amount_cents: 0,
        due_date: due_date, competence_date: due_date,
        status: 'pendente', payment_method: 'pix'
      )
    end
  end
end

RSpec.configure do |config|
  config.include PatientPortalSpecSupport::InstallmentBuilder
end
