require 'rails_helper'

RSpec.describe PatientPortal::Payment::AsaasGateway do
  let(:account)     { create(:account) }
  let(:patient)     { create(:patient, account: account) }
  let(:installment) { build_paid_installment_target(account: account, patient: patient, amount_cents: 12_345) }

  # Stub mínimo de GatewaySetting compatível com o que o gateway lê.
  let(:setting) do
    Struct.new(:api_key, :environment).new('fake_token', 'sandbox')
  end

  describe '#initialize' do
    it 'levanta AsaasError se api_key vazia' do
      bad = Struct.new(:api_key, :environment).new('', 'sandbox')
      expect { described_class.new(setting: bad) }.to raise_error(described_class::AsaasError, /api_key/)
    end

    it 'levanta AsaasError se setting nil' do
      expect { described_class.new(setting: nil) }.to raise_error(described_class::AsaasError, /ausente/)
    end
  end

  describe '#create_charge!' do
    let(:gateway) { described_class.new(setting: setting) }
    let(:customer_response) { { 'id' => 'cus_999' }.to_json }
    let(:payment_response) do
      {
        'id' => 'pay_777', 'status' => 'PENDING',
        'bankSlipUrl' => 'https://asaas.test/boleto', 'dueDate' => Date.current.iso8601,
        'identificationField' => '12345.67890'
      }.to_json
    end
    let(:pix_response) do
      { 'encodedImage' => 'iVBOR...', 'payload' => '0002012626...', 'expirationDate' => '' }.to_json
    end

    before do
      patient.update!(external_ids: {})
      stub_request(:post, %r{api-sandbox\.asaas\.com/v3/customers})
        .to_return(status: 200, body: customer_response, headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, %r{api-sandbox\.asaas\.com/v3/payments})
        .to_return(status: 200, body: payment_response, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, %r{api-sandbox\.asaas\.com/v3/payments/pay_777/pixQrCode})
        .to_return(status: 200, body: pix_response, headers: { 'Content-Type' => 'application/json' })
    end

    it 'cria customer e charge no Asaas e retorna Result preenchido (PIX)' do
      result = gateway.create_charge!(
        method: 'pix', amount_cents: 12_345,
        patient: patient, installment: installment
      )
      expect(result.gateway_payment_id).to eq('pay_777')
      expect(result.pix_qr_code).to eq('iVBOR...')
      expect(result.pix_copy_paste).to eq('0002012626...')
      expect(result.boleto_url).to be_nil.or(eq('https://asaas.test/boleto'))
    end

    it 'salva asaas_customer_id em Patient.external_ids' do
      gateway.create_charge!(method: 'pix', amount_cents: 12_345, patient: patient, installment: installment)
      expect(patient.reload.external_ids['asaas_customer_id']).to eq('cus_999')
    end

    it 'não chama ensure_customer se já tem id cacheado' do
      patient.update!(external_ids: { 'asaas_customer_id' => 'cus_existing' })

      gateway.create_charge!(method: 'boleto', amount_cents: 12_345, patient: patient, installment: installment)
      expect(WebMock).not_to have_requested(:post, %r{customers})
    end

    it 'levanta AsaasError quando Asaas devolve erro' do
      stub_request(:post, %r{api-sandbox\.asaas\.com/v3/payments})
        .to_return(status: 400, body: '{"errors":[{"description":"sandbox bloqueado"}]}')
      patient.update!(external_ids: { 'asaas_customer_id' => 'cus_existing' })

      expect {
        gateway.create_charge!(method: 'pix', amount_cents: 12_345, patient: patient, installment: installment)
      }.to raise_error(described_class::AsaasError, /400/)
    end

    it 'rejeita método não suportado' do
      patient.update!(external_ids: { 'asaas_customer_id' => 'cus_existing' })
      expect {
        gateway.create_charge!(method: 'bitcoin', amount_cents: 1, patient: patient, installment: installment)
      }.to raise_error(described_class::AsaasError, /não suportado/)
    end
  end
end
