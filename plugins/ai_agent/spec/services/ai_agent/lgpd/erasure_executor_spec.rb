require 'rails_helper'

RSpec.describe AiAgent::Lgpd::ErasureExecutor do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }

  def seed_data!
    AiAgent::PatientMemory.create!(account_id: account.id, contact_id: contact.id, preferences: { x: 1 }, history: [])
    AiAgent::Trace.create!(account_id: account.id, contact_id: contact.id, conversation_id: conversation.id, model: 't', provider: 't', latency_ms: 1, cost_cents: 0)
    AiAgent::Trace.create!(account_id: account.id, contact_id: contact.id, conversation_id: conversation.id, model: 't', provider: 't', latency_ms: 1, cost_cents: 0)
    AiAgent::ConversationState.create!(account_id: account.id, conversation_id: conversation.id, status: 'active')
  end

  describe '#call' do
    it 'apaga PatientMemory, Trace e ConversationState do contato' do
      seed_data!

      result = described_class.call(account_id: account.id, contact_id: contact.id, reason: 'Teste')

      expect(result.ok).to be(true)
      expect(result.counts[:patient_memories]).to eq(1)
      expect(result.counts[:traces]).to eq(2)
      expect(result.counts[:conversation_states]).to eq(1)
      expect(AiAgent::PatientMemory.where(contact_id: contact.id)).to be_empty
      expect(AiAgent::Trace.where(contact_id: contact.id)).to be_empty
    end

    it 'NÃO apaga Patient (retenção CFM 20 anos)' do
      patient = create(:patient, account: account, contact: contact) if defined?(Patient)
      seed_data!

      described_class.call(account_id: account.id, contact_id: contact.id)

      expect(Patient.find_by(id: patient.id)).to be_present if patient
    end

    it 'grava AuditLog com action lgpd_erasure_executed' do
      seed_data!

      described_class.call(account_id: account.id, contact_id: contact.id, reason: 'X')

      log = AiAgent::AuditLog.where(action: 'lgpd_erasure_executed', account_id: account.id).last
      expect(log).to be_present
      expect(log.changes_summary).to be_present
    end

    it 'retorna ok=false se algo explode' do
      allow(AiAgent::PatientMemory).to receive(:where).and_raise(StandardError, 'boom')

      result = described_class.call(account_id: account.id, contact_id: contact.id)

      expect(result.ok).to be(false)
      expect(result.error).to match(/boom/)
    end
  end
end
