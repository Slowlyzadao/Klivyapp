require 'rails_helper'

RSpec.describe Patients::SecureBlobTokenService do
  let(:blob_id) { 42 }
  let(:account_id) { 7 }

  describe '.encode' do
    it 'returns a non-empty signed string' do
      token = described_class.encode(blob_id: blob_id, account_id: account_id)
      expect(token).to be_a(String)
      expect(token).to be_present
    end

    it 'rejects non-integer blob_id at encode time (fail-fast)' do
      expect do
        described_class.encode(blob_id: 'not-int', account_id: account_id)
      end.to raise_error(ArgumentError)
    end

    it 'rejects non-integer account_id at encode time (fail-fast)' do
      expect do
        described_class.encode(blob_id: blob_id, account_id: 'not-int')
      end.to raise_error(ArgumentError)
    end

    it 'includes transformations when provided' do
      token = described_class.encode(
        blob_id: blob_id,
        account_id: account_id,
        transformations: { resize_to_limit: [400, 400] }
      )
      decoded = described_class.decode!(token)
      expect(decoded[:transformations]).to eq(resize_to_limit: [400, 400])
    end

    it 'omits transformations key when nil' do
      token = described_class.encode(blob_id: blob_id, account_id: account_id)
      decoded = described_class.decode!(token)
      expect(decoded[:transformations]).to be_nil
    end
  end

  describe '.decode!' do
    let(:token) do
      described_class.encode(blob_id: blob_id, account_id: account_id, expires_in: 5.minutes)
    end

    it 'roundtrips blob_id and account_id' do
      decoded = described_class.decode!(token)
      expect(decoded[:blob_id]).to eq(blob_id)
      expect(decoded[:account_id]).to eq(account_id)
    end

    it 'returns expires_at as Time' do
      decoded = described_class.decode!(token)
      expect(decoded[:expires_at]).to be_a(Time)
      expect(decoded[:expires_at]).to be_within(2.seconds).of(Time.current + 5.minutes)
    end

    it 'raises Tampered when payload is changed' do
      mutated = "#{token}xxxx"
      expect { described_class.decode!(mutated) }.to raise_error(described_class::Tampered)
    end

    it 'raises Tampered when token is signed with a different verifier' do
      foreign_token = Rails.application.message_verifier(:other_namespace)
                          .generate(JSON.generate('blob_id' => blob_id, 'account_id' => account_id, 'expires_at' => 1.hour.from_now.to_i))
      expect { described_class.decode!(foreign_token) }.to raise_error(described_class::Tampered)
    end

    it 'raises Expired when expires_at is past' do
      old_token = described_class.encode(blob_id: blob_id, account_id: account_id, expires_in: 1.second)
      travel_to(2.seconds.from_now) do
        expect { described_class.decode!(old_token) }.to raise_error(described_class::Expired)
      end
    end

    it 'raises Malformed when signed payload is not JSON' do
      bad_token = Rails.application.message_verifier(described_class::VERIFIER_NAMESPACE).generate('not-json{')
      expect { described_class.decode!(bad_token) }.to raise_error(described_class::Malformed)
    end

    it 'raises Malformed when required fields are missing' do
      partial_token = Rails.application.message_verifier(described_class::VERIFIER_NAMESPACE)
                           .generate(JSON.generate('blob_id' => blob_id))
      expect { described_class.decode!(partial_token) }.to raise_error(described_class::Malformed)
    end

    it 'raises Malformed when fields have wrong types' do
      bad_types_token = Rails.application.message_verifier(described_class::VERIFIER_NAMESPACE)
                             .generate(JSON.generate('blob_id' => 'string', 'account_id' => account_id, 'expires_at' => 1.hour.from_now.to_i))
      expect { described_class.decode!(bad_types_token) }.to raise_error(described_class::Malformed)
    end
  end
end
