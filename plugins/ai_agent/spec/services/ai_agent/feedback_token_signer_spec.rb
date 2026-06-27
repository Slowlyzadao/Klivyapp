require 'rails_helper'

RSpec.describe AiAgent::FeedbackTokenSigner do
  let(:trace_id) { 42 }
  let(:account_id) { 7 }
  let(:other_account_id) { 99 }

  describe '.sign + .verify (round-trip)' do
    it 'token assinado bate na verificação' do
      token = described_class.sign(trace_id: trace_id, account_id: account_id)
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: token)).to be(true)
    end

    it 'aceita trace_id e account_id como string ou inteiro (idempotente no canonical)' do
      token_int = described_class.sign(trace_id: 42, account_id: 7)
      # Mesmo trace_id+account_id+issued_at = mesmo digest (parte final do token)
      digest_int = token_int.split(':').last

      # Re-sign com mesmo issued_at extraído pra comparar
      issued_at = Time.zone.at(token_int.split(':')[2].to_i)
      token_str = described_class.sign(trace_id: '42', account_id: '7', issued_at: issued_at)
      digest_str = token_str.split(':').last

      expect(digest_int).to eq(digest_str)
    end
  end

  describe '.verify rejection paths' do
    let(:valid_token) { described_class.sign(trace_id: trace_id, account_id: account_id) }

    it 'rejeita token vazio' do
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: '')).to be(false)
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: nil)).to be(false)
    end

    it 'rejeita trace_id vazio' do
      expect(described_class.verify(trace_id: nil, account_id: account_id, token: valid_token)).to be(false)
    end

    it 'rejeita account_id vazio' do
      expect(described_class.verify(trace_id: trace_id, account_id: nil, token: valid_token)).to be(false)
    end

    it 'rejeita token de outro trace_id' do
      token_for_42 = described_class.sign(trace_id: 42, account_id: account_id)
      expect(described_class.verify(trace_id: 99, account_id: account_id, token: token_for_42)).to be(false)
    end

    it 'rejeita token forjado para outra conta (SEC-11 binding)' do
      token_for_account_7 = described_class.sign(trace_id: trace_id, account_id: account_id)
      # Atacante tenta usar token de conta 7 contra conta 99
      expect(described_class.verify(trace_id: trace_id, account_id: other_account_id, token: token_for_account_7)).to be(false)
    end

    it 'rejeita token alterado por 1 byte (digest)' do
      tampered = valid_token.dup
      tampered[-1] = valid_token[-1] == 'a' ? 'b' : 'a'
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: tampered)).to be(false)
    end

    it 'rejeita token com account_id manipulado no header' do
      parts = valid_token.split(':', 4)
      tampered = "#{parts[0]}:#{other_account_id}:#{parts[2]}:#{parts[3]}"
      # mesmo passando o account_id "correto" do header no verify, o digest
      # ainda foi gerado com account_id=7 → secure_compare falha
      expect(described_class.verify(trace_id: trace_id, account_id: other_account_id, token: tampered)).to be(false)
    end

    it 'rejeita token expirado (SEC-11 TTL)' do
      old_token = described_class.sign(trace_id: trace_id, account_id: account_id, issued_at: 10.days.ago)
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: old_token)).to be(false)
    end

    it 'aceita token dentro do max_age customizado' do
      token = described_class.sign(trace_id: trace_id, account_id: account_id, issued_at: 1.hour.ago)
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: token, max_age: 2.hours)).to be(true)
    end

    it 'rejeita token sem prefixo de versão' do
      bare = OpenSSL::HMAC.hexdigest('SHA256', described_class.secret, "v1:#{account_id}:#{trace_id}:#{Time.current.to_i}")
      expect(described_class.verify(trace_id: trace_id, account_id: account_id, token: bare)).to be(false)
    end
  end
end
