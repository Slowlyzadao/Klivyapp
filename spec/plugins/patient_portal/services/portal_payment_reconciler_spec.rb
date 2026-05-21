require 'rails_helper'

RSpec.describe PatientPortal::PortalPaymentReconciler do
  let(:account)     { create(:account) }
  let(:patient)     { create(:patient, account: account) }
  let(:installment) { build_paid_installment_target(account: account, patient: patient, amount_cents: 12_500) }

  def build_payment(status: 'awaiting_payment', gateway_payment_id: 'pay_abc')
    PortalPayment.create!(
      account: account, patient: patient, installment: installment,
      method: 'pix', gateway: 'asaas', amount_cents: 12_500,
      status: status, gateway_payment_id: gateway_payment_id
    )
  end

  describe '#call' do
    context 'evento que não representa pagamento' do
      it 'retorna reconciled=false' do
        result = described_class.new(event_type: 'PAYMENT_OVERDUE', payload: {}).call
        expect(result.reconciled?).to eq(false)
        expect(result.reason).to eq('event_not_payment_paid')
      end
    end

    context 'PortalPayment correspondente não existe' do
      it 'retorna reconciled=false com motivo' do
        result = described_class.new(
          event_type: 'PAYMENT_RECEIVED',
          payload: { 'payment' => { 'id' => 'inexistente' } }
        ).call
        expect(result.reconciled?).to eq(false)
        expect(result.reason).to eq('portal_payment_not_found')
      end
    end

    context 'PortalPayment já está paid (re-entrega de webhook)' do
      it 'retorna reconciled=true sem reprocessar' do
        payment = build_payment
        payment.mark_paid!(at: 1.hour.ago)

        expect_any_instance_of(PatientPortal::PaymentReceiptIssuer).not_to receive(:call)

        result = described_class.new(
          event_type: 'PAYMENT_RECEIVED',
          payload: { 'payment' => { 'id' => payment.gateway_payment_id } }
        ).call
        expect(result.reconciled?).to eq(true)
        expect(result.reason).to eq('already_paid')
      end
    end

    context 'PortalPayment aguardando confirmação' do
      it 'marca como paid e dispara PaymentReceiptIssuer (recibo + notification + installment recebido)' do
        payment = build_payment

        result = described_class.new(
          event_type: 'PAYMENT_RECEIVED',
          payload: { 'payment' => { 'id' => payment.gateway_payment_id, 'paymentDate' => '2026-06-01' } }
        ).call

        expect(result.reconciled?).to eq(true)
        expect(payment.reload.status).to eq('paid')
        expect(installment.reload.status).to eq('recebido')
        expect(Document.active.where(patient_id: patient.id).count).to eq(1)
        expect(PatientPortalNotification.where(patient_id: patient.id, kind: 'financial_charge').count).to eq(1)
      end

      it 'aceita PAYMENT_CONFIRMED como evento que paga' do
        payment = build_payment
        result = described_class.new(
          event_type: 'PAYMENT_CONFIRMED',
          payload: { 'payment' => { 'id' => payment.gateway_payment_id } }
        ).call
        expect(result.reconciled?).to eq(true)
        expect(payment.reload.status).to eq('paid')
      end

      it 'usa Time.current quando paymentDate ausente' do
        payment = build_payment
        described_class.new(
          event_type: 'PAYMENT_RECEIVED',
          payload: { 'payment' => { 'id' => payment.gateway_payment_id } }
        ).call
        expect(payment.reload.paid_at).to be_within(5.seconds).of(Time.current)
      end
    end
  end
end
