require 'rails_helper'

RSpec.describe AgendaEvent, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:contact) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_presence_of(:starts_at) }
    it { is_expected.to validate_presence_of(:ends_at) }

    describe '#ends_at_after_starts_at' do
      it 'is invalid when ends_at is before starts_at' do
        event = build(:agenda_event, starts_at: 1.day.from_now, ends_at: 1.day.ago)
        expect(event).not_to be_valid
        expect(event.errors[:ends_at]).to include('must be after starts_at')
      end

      it 'is valid when ends_at is after starts_at' do
        event = build(:agenda_event, starts_at: 1.day.from_now, ends_at: 2.days.from_now)
        expect(event).to be_valid
      end
    end

    describe '#status' do
      it 'allows valid status values' do
        %w[scheduled confirmed cancelled completed no_show].each do |status|
          event = build(:agenda_event, status: status)
          expect(event).to be_valid, "Expected status '#{status}' to be valid"
        end
      end

      it 'rejects invalid status values' do
        event = build(:agenda_event, status: 'invalid_status')
        expect(event).not_to be_valid
      end
    end
  end

  describe 'factory' do
    it 'creates a valid agenda event' do
      event = create(:agenda_event)
      expect(event).to be_persisted
      expect(event.account).to be_present
      expect(event.user).to be_present
      expect(event.contact).to be_present
    end

    it 'creates a confirmed event' do
      event = create(:agenda_event, :confirmed)
      expect(event.status).to eq('confirmed')
    end
  end
end
