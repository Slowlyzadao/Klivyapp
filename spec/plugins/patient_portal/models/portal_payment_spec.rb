require 'rails_helper'

RSpec.describe PortalPayment, type: :model do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }
  let(:installment) { build_paid_installment_target(account: account, patient: patient) }

  def build_payment(overrides = {})
    described_class.new({
      account:      account,
      patient:      patient,
      installment:  installment,
      method:       'pix',
      gateway:      'mock',
      amount_cents: installment.amount_cents,
      status:       'pending'
    }.merge(overrides))
  end

  describe 'validations' do
    it 'aceita instância válida' do
      expect(build_payment).to be_valid
    end

    it 'rejeita método inválido' do
      expect(build_payment(method: 'paypal')).not_to be_valid
    end

    it 'rejeita status inválido' do
      expect(build_payment(status: 'foo')).not_to be_valid
    end

    it 'rejeita gateway desconhecido' do
      expect(build_payment(gateway: 'cielo')).not_to be_valid
    end

    it 'exige amount_cents > 0' do
      expect(build_payment(amount_cents: 0)).not_to be_valid
      expect(build_payment(amount_cents: -100)).not_to be_valid
    end
  end

  describe 'scopes' do
    it 'open inclui pending e awaiting_payment' do
      p1 = build_payment(status: 'pending').tap(&:save!)
      p2 = build_payment(status: 'awaiting_payment').tap(&:save!)
      build_payment(status: 'paid').tap { |p| p.amount_cents = 99; p.save!(validate: false) }
      build_payment(status: 'cancelled').tap { |p| p.amount_cents = 100; p.save!(validate: false) }

      expect(described_class.open).to contain_exactly(p1, p2)
    end
  end

  describe '#mark_paid!' do
    it 'transiciona status pra paid e carimba paid_at' do
      payment = build_payment(status: 'awaiting_payment').tap(&:save!)
      time = Time.current
      payment.mark_paid!(at: time, payload: { webhook: 'ok' })

      expect(payment.reload).to be_paid
      expect(payment.paid_at.to_i).to eq(time.to_i)
      expect(payment.gateway_payload['webhook']).to eq('ok')
    end

    it 'é idempotente — não muda paid_at se já estiver paid' do
      original_time = 1.hour.ago
      payment = build_payment(status: 'awaiting_payment').tap(&:save!)
      payment.mark_paid!(at: original_time)

      payment.mark_paid!(at: Time.current)
      expect(payment.paid_at.to_i).to eq(original_time.to_i)
    end
  end

  describe '#mark_cancelled!' do
    it 'cancela quando pending/awaiting_payment' do
      payment = build_payment(status: 'awaiting_payment').tap(&:save!)
      payment.mark_cancelled!
      expect(payment.reload.status).to eq('cancelled')
    end

    it 'não cancela quando já paid' do
      payment = build_payment(status: 'awaiting_payment').tap(&:save!)
      payment.mark_paid!
      payment.mark_cancelled!
      expect(payment.reload).to be_paid
    end
  end
end
