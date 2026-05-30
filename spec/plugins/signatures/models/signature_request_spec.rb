# Specs do SignatureRequest. Foca na máquina de estados (transições
# permitidas + rejeitadas) e validações.
require 'rails_helper'

RSpec.describe SignatureRequest do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:patient) { Patient.create!(account: account, name: 'Maria', cpf: '12345678900') }
  let(:document) do
    Document.create!(patient: patient, account: account, generated_by: user,
                     document_type: 'atestado', title: 'Test', status: 'gerado')
  end

  def build_request(**overrides)
    described_class.new(
      account: account, signable: document,
      requested_by_user: user, provider: 'mock', status: 'pending',
      signer_name: 'Bob', signer_email: 'bob@x.com',
      audit_log: [], **overrides
    )
  end

  describe 'validações' do
    it 'aceita request mock válido' do
      expect(build_request).to be_valid
    end

    it 'recusa provider fora do whitelist' do
      expect(build_request(provider: 'bogus')).not_to be_valid
    end

    it 'recusa status fora do whitelist' do
      expect(build_request(status: 'bogus')).not_to be_valid
    end

    it 'mock NÃO exige email' do
      # MockProvider serve pra dev local que pode não ter signer real ainda.
      expect(build_request(signer_email: nil)).to be_valid
    end

    it 'clicksign exige email' do
      r = build_request(provider: 'clicksign', signer_email: nil)
      expect(r).not_to be_valid
      expect(r.errors[:signer_email]).to be_present
    end

    it 'email com formato inválido falha (provider clicksign)' do
      r = build_request(provider: 'clicksign', signer_email: 'not-an-email')
      expect(r).not_to be_valid
    end

    it 'external_id único por provider' do
      described_class.create!(account: account, signable: document, provider: 'mock',
                              status: 'sent', signer_name: 'A', external_id: 'dup_x',
                              audit_log: [])
      dup = build_request(external_id: 'dup_x')
      dup.status = 'sent'
      expect(dup).not_to be_valid
    end
  end

  describe 'máquina de estados' do
    let(:request) { build_request.tap(&:save!) }

    describe '#mark_sent!' do
      it 'transita de pending pra sent' do
        request.mark_sent!(external_id: 'env_x', signing_url: 'http://x')
        expect(request).to be_sent
        expect(request.external_id).to eq('env_x')
        expect(request.sent_at).to be_present
      end

      it 'append audit_log' do
        expect { request.mark_sent!(external_id: 'a') }
          .to change { request.audit_log.size }.by(1)
      end

      it 'recusa transição de sent → sent (origem inválida)' do
        request.mark_sent!(external_id: 'a')
        expect { request.mark_sent!(external_id: 'b') }
          .to raise_error(SignatureRequest::InvalidTransition)
      end
    end

    describe '#mark_viewed!' do
      it 'transita de sent pra viewed' do
        request.mark_sent!(external_id: 'a')
        request.mark_viewed!
        expect(request).to be_viewed
        expect(request.viewed_at).to be_present
      end

      it 'recusa de pending direto pra viewed' do
        expect { request.mark_viewed! }
          .to raise_error(SignatureRequest::InvalidTransition)
      end
    end

    describe '#mark_signed!' do
      it 'aceita transição de sent ou viewed' do
        request.mark_sent!(external_id: 'a')
        request.mark_signed!(signed_pdf_hash: 'h' * 64)
        expect(request).to be_signed
        expect(request.signed_pdf_hash).to be_present
      end
    end

    describe '#mark_completed!' do
      it 'fecha pipeline e fica terminal' do
        request.mark_sent!(external_id: 'a')
        request.mark_signed!
        request.mark_completed!
        expect(request).to be_completed
        expect(request).to be_terminal
      end
    end

    describe '#mark_cancelled!' do
      it 'aceita cancel a partir de pending/sent/viewed' do
        request.mark_cancelled!(reason: 'mudei de ideia')
        expect(request).to be_cancelled
        expect(request.audit_log.last['meta']).to include('reason' => 'mudei de ideia')
      end

      it 'recusa cancel quando já completed' do
        request.mark_sent!(external_id: 'a')
        request.mark_signed!
        request.mark_completed!
        expect { request.mark_cancelled! }
          .to raise_error(SignatureRequest::InvalidTransition)
      end
    end

    describe '#mark_failed!' do
      it 'aceita failed de qualquer estado não-terminal com reason' do
        request.mark_failed!(reason: 'provider error')
        expect(request).to be_failed
      end
    end
  end

  describe 'scopes' do
    let!(:pending_r) { build_request.tap(&:save!) }
    let!(:sent_r)    { build_request(status: 'sent', external_id: 'sent_x').tap(&:save!) }
    let!(:done_r)    { build_request(status: 'completed', external_id: 'done_x').tap(&:save!) }

    it 'in_progress retorna pending/sent/viewed' do
      result = described_class.in_progress
      expect(result).to include(pending_r, sent_r)
      expect(result).not_to include(done_r)
    end

    it 'terminal retorna completed/cancelled/failed/expired' do
      expect(described_class.terminal).to include(done_r)
      expect(described_class.terminal).not_to include(pending_r, sent_r)
    end
  end
end
