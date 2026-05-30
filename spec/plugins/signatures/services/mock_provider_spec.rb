# Specs do MockProvider — provider falso pra dev/testes. Garantia mínima
# de que retorna o shape esperado pra alimentar SignatureRequest.
require 'rails_helper'

RSpec.describe Signatures::Providers::MockProvider do
  let(:account) { create(:account) }
  let(:patient) { Patient.create!(account: account, name: 'Patient', cpf: '12345678900') }
  let(:document) do
    Document.create!(patient: patient, account: account, generated_by: nil,
                     document_type: 'atestado', title: 'Test', status: 'gerado')
  end
  let(:request) do
    SignatureRequest.create!(account: account, signable: document, provider: 'mock',
                             status: 'pending', signer_name: 'Signer', audit_log: [])
  end
  let(:provider) { described_class.new }

  describe '#create_envelope' do
    it 'retorna external_id e signing_url' do
      result = provider.create_envelope(request: request, pdf_data: 'x')
      expect(result.success?).to be true
      expect(result.external_id).to match(/^mock_[a-f0-9]+$/)
      expect(result.signing_url).to start_with('/mock/signatures/')
    end
  end

  describe '#cancel_envelope' do
    it 'success regardless of state' do
      result = provider.cancel_envelope(request: request, reason: 'whatever')
      expect(result.success?).to be true
    end
  end

  describe '#fetch_status' do
    it 'espelha o status local' do
      result = provider.fetch_status(request: request)
      expect(result.data[:status]).to eq(request.status)
    end
  end

  describe '#download_signed_pdf' do
    it 'devolve bytes que começam com %PDF (header válido)' do
      bytes = provider.download_signed_pdf(request: request)
      expect(bytes).to start_with('%PDF')
    end
  end
end
