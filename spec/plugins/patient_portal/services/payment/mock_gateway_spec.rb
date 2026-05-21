require 'rails_helper'

RSpec.describe PatientPortal::Payment::MockGateway do
  let(:account)     { create(:account) }
  let(:patient)     { create(:patient, account: account) }
  let(:installment) { build_paid_installment_target(account: account, patient: patient, amount_cents: 50_000) }
  let(:gateway)     { described_class.new }

  describe '#create_charge!' do
    it 'gera QR code PIX e copia-cola quando method=pix' do
      result = gateway.create_charge!(
        method: 'pix', amount_cents: 50_000,
        patient: patient, installment: installment
      )

      expect(result.gateway_payment_id).to start_with('mock_')
      expect(result.pix_qr_code).to be_present
      expect(result.pix_copy_paste).to be_present
      expect(result.boleto_url).to be_nil
      expect(result.expires_at).to be > Time.current
      expect(result.expires_at).to be < 1.hour.from_now
    end

    it 'gera URL e linha digitável quando method=boleto' do
      result = gateway.create_charge!(
        method: 'boleto', amount_cents: 50_000,
        patient: patient, installment: installment
      )

      expect(result.boleto_url).to start_with('https://klivy.test/boleto/')
      expect(result.boleto_barcode).to match(/\d{5}/)
      expect(result.pix_qr_code).to be_nil
      expect(result.expires_at).to be > 1.day.from_now
    end

    it 'inclui metadata de teste no payload bruto' do
      result = gateway.create_charge!(
        method: 'pix', amount_cents: 50_000,
        patient: patient, installment: installment
      )
      expect(result.raw[:simulated]).to be(true)
      expect(result.raw[:installment_id]).to eq(installment.id)
    end
  end

  describe '.for(account:) factory' do
    it 'retorna MockGateway por padrão em dev' do
      gw = PatientPortal::Payment::Gateway.for(account: account)
      expect(gw).to be_a(described_class)
    end
  end

  describe 'Result#to_attrs' do
    it 'remove chaves nil pra evitar sobrescrever DB com nil acidentalmente' do
      attrs = gateway.create_charge!(method: 'pix', amount_cents: 100,
                                      patient: patient, installment: installment).to_attrs
      expect(attrs.keys).not_to include(:boleto_url, :boleto_barcode)
      expect(attrs.keys).to include(:pix_qr_code, :pix_copy_paste, :expires_at)
    end
  end
end
