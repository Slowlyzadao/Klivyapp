require 'rails_helper'

RSpec.describe Contacts::BulkDeleteService do
  subject(:service) { described_class.new(account: account, contact_ids: contact_ids) }

  let(:account) { create(:account) }
  let!(:contact_one) { create(:contact, account: account) }
  let!(:contact_two) { create(:contact, account: account) }
  let(:contact_ids) { [contact_one.id, contact_two.id] }

  describe '#perform' do
    it 'deletes the provided contacts' do
      expect { service.perform }
        .to change { account.contacts.exists?(contact_one.id) }.from(true).to(false)
        .and change { account.contacts.exists?(contact_two.id) }.from(true).to(false)
    end

    it 'returns the number of contacts actually deleted' do
      expect(service.perform).to eq(2)
    end

    it 'returns 0 and does nothing when no contact ids are provided' do
      empty_service = described_class.new(account: account, contact_ids: [])

      expect { empty_service.perform }.not_to change(Contact, :count)
      expect(empty_service.perform).to eq(0)
    end
  end
end
