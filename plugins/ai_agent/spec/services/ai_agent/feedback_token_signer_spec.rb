require 'rails_helper'

RSpec.describe AiAgent::FeedbackTokenSigner do
  describe '.sign + .verify (round-trip)' do
    it 'token assinado bate na verificação' do
      token = described_class.sign(42)
      expect(described_class.verify(42, token)).to be(true)
    end

    it 'aceita trace_id como string ou inteiro (idempotente)' do
      a = described_class.sign(42)
      b = described_class.sign('42')
      expect(a).to eq(b)
    end
  end

  describe '.verify rejection paths' do
    it 'rejeita token vazio' do
      expect(described_class.verify(42, '')).to be(false)
      expect(described_class.verify(42, nil)).to be(false)
    end

    it 'rejeita trace_id vazio' do
      token = described_class.sign(42)
      expect(described_class.verify(nil, token)).to be(false)
    end

    it 'rejeita token de outro trace_id' do
      token_42 = described_class.sign(42)
      expect(described_class.verify(99, token_42)).to be(false)
    end

    it 'rejeita token alterado por 1 byte' do
      token = described_class.sign(42)
      tampered = token.dup
      tampered[0] = tampered[0] == 'a' ? 'b' : 'a'
      expect(described_class.verify(42, tampered)).to be(false)
    end
  end
end
