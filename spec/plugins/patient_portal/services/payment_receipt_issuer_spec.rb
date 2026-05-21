require 'rails_helper'

RSpec.describe PatientPortal::PaymentReceiptIssuer do
  let(:account)     { create(:account) }
  let(:patient)     { create(:patient, account: account) }
  let(:installment) { build_paid_installment_target(account: account, patient: patient, amount_cents: 30_000) }
  let(:payment) do
    PortalPayment.create!(
      account: account, patient: patient, installment: installment,
      method: 'pix', gateway: 'mock', amount_cents: 30_000,
      status: 'awaiting_payment'
    ).tap { |p| p.mark_paid!(at: Time.current) }
  end

  subject(:issuer) { described_class.new(payment: payment) }

  it 'levanta erro se PortalPayment não está paid' do
    pending_payment = PortalPayment.create!(
      account: account, patient: patient, installment: installment,
      method: 'pix', gateway: 'mock', amount_cents: 30_000,
      status: 'awaiting_payment'
    )
    expect { described_class.new(payment: pending_payment).call }.to raise_error(/paid/)
  end

  it 'marca installment como recebido com método correto' do
    issuer.call
    expect(installment.reload.status).to eq('recebido')
    expect(installment.received_amount_cents).to eq(30_000)
    expect(installment.payment_method).to eq('pix')
    expect(installment.received_at).to be_present
  end

  it 'gera um Document do tipo recibo com variables apontando para o pagamento' do
    expect { issuer.call }.to change(Document.active, :count).by(1)

    doc = Document.active.last
    expect(doc.patient_id).to eq(patient.id)
    expect(doc.account_id).to eq(account.id)
    expect(doc.title).to include('R$ 300,00')
    expect(doc.variables['portal_payment_id']).to eq(payment.id)
    expect(doc.variables['method']).to eq('pix')
  end

  it 'dispatcha notificação financial_charge para o paciente' do
    expect { issuer.call }.to change {
      PatientPortalNotification.where(patient_id: patient.id, kind: 'financial_charge').count
    }.by(1)

    notif = PatientPortalNotification.where(patient_id: patient.id, kind: 'financial_charge').last
    expect(notif.title).to eq('Pagamento confirmado')
    expect(notif.payload['payment_id']).to eq(payment.id)
  end

  it 'é idempotente — chamadas repetidas não duplicam o Document' do
    issuer.call
    expect { described_class.new(payment: payment.reload).call }.not_to change(Document.active, :count)
  end

  context 'quando installment já foi marcado recebido externamente' do
    it 'não falha e ainda dispatcha notificação' do
      installment.update!(status: 'recebido', received_amount_cents: 30_000, received_at: Time.current)
      expect { issuer.call }.not_to raise_error
    end
  end
end
