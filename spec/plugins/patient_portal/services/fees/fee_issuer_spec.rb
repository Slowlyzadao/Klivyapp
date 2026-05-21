require 'rails_helper'

RSpec.describe PatientPortal::Fees::FeeIssuer do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }
  let(:user)    { create(:user, :administrator, account: account) }

  # Sem dependência de AgendaEvent real — mock simples com user_id + id.
  let(:event)   { OpenStruct.new(id: 999, user_id: user.id) }

  subject(:issuer) do
    described_class.new(
      account: account, patient: patient, agenda_event: event,
      kind: 'late_cancel', amount_cents: 5_000
    )
  end

  describe '#call' do
    it 'cria Budget + Installment com o valor da fee' do
      expect { issuer.call }.to change(Financial::Budget, :count).by(1)
                            .and change(Financial::Installment, :count).by(1)

      installment = Financial::Installment.last
      expect(installment.amount_cents).to eq(5_000)
      expect(installment.status).to eq('pendente')
      expect(installment.patient_id).to eq(patient.id)
      expect(installment.financial_budget_id).to eq(Financial::Budget.last.id)
    end

    it 'inclui tag de idempotência nas notes do Budget' do
      issuer.call
      expect(Financial::Budget.last.notes).to include("[PortalFee:late_cancel:event=#{event.id}]")
    end

    it 'reusa Budget existente em segunda chamada (idempotente)' do
      first  = issuer.call
      second = nil
      expect {
        second = described_class.new(
          account: account, patient: patient, agenda_event: event,
          kind: 'late_cancel', amount_cents: 5_000
        ).call
      }.not_to change(Financial::Budget, :count)

      expect(second).to be_a(Financial::Installment)
      expect(second.id).to eq(first.id)
    end

    it 'cria Budget separado para kind diferente sobre o mesmo event' do
      issuer.call
      expect {
        described_class.new(
          account: account, patient: patient, agenda_event: event,
          kind: 'no_show', amount_cents: 8_000
        ).call
      }.to change { Financial::Budget.where(patient: patient).count }.by(1)
    end

    it 'retorna nil sem criar nada se amount <= 0' do
      expect {
        result = described_class.new(
          account: account, patient: patient, agenda_event: event,
          kind: 'late_cancel', amount_cents: 0
        ).call
        expect(result).to be_nil
      }.not_to change { Financial::Budget.where(patient: patient).count }
    end
  end
end
