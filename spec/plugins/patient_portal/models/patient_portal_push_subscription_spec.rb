require 'rails_helper'

RSpec.describe PatientPortalPushSubscription do
  let(:account) { create(:account) }
  let(:patient) { create(:patient, account: account) }

  def build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/abc123')
    described_class.create!(
      account: account, patient: patient,
      endpoint: endpoint, p256dh_key: 'pk_xyz', auth_key: 'auth_xyz'
    )
  end

  describe 'validações' do
    it 'exige endpoint, p256dh_key e auth_key' do
      sub = described_class.new(account: account, patient: patient)
      expect(sub).to be_invalid
      expect(sub.errors.attribute_names).to include(:endpoint, :p256dh_key, :auth_key)
    end

    it 'enforça unicidade de endpoint' do
      build_sub
      dup = described_class.new(
        account: account, patient: patient,
        endpoint: 'https://fcm.googleapis.com/fcm/send/abc123',
        p256dh_key: 'x', auth_key: 'y'
      )
      expect(dup).to be_invalid
      expect(dup.errors[:endpoint]).to be_present
    end
  end

  describe '#record_failure!' do
    it 'incrementa contador e desativa após MAX_FAILURES' do
      sub = build_sub
      (PatientPortalPushSubscription::MAX_FAILURES - 1).times { sub.record_failure! }
      expect(sub.reload.disabled?).to eq(false)

      sub.record_failure!
      expect(sub.reload.disabled?).to eq(true)
    end

    it 'desativa imediatamente quando permanent=true' do
      sub = build_sub
      sub.record_failure!(permanent: true)
      expect(sub.reload.disabled?).to eq(true)
    end
  end

  describe '#record_success!' do
    it 'reseta failure_count e atualiza last_used_at' do
      sub = build_sub
      sub.update_columns(failure_count: 2)
      sub.record_success!
      expect(sub.reload.failure_count).to eq(0)
      expect(sub.last_used_at).to be_present
    end
  end

  describe 'scopes' do
    it 'active retorna apenas subs não desativadas' do
      a = build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/aaa')
      b = build_sub(endpoint: 'https://fcm.googleapis.com/fcm/send/bbb')
      b.update_columns(disabled_at: Time.current)

      # Escopa por patient pra isolar de dados pré-existentes de E2E.
      expect(described_class.active.for_patient(patient).pluck(:id)).to contain_exactly(a.id)
    end
  end
end
