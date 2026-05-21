require 'rails_helper'

RSpec.describe Telemed::MarkInProgressJob do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user, status: 'arrived') }
  let(:tracker) { Telemed::SessionTracker.new(event) }

  context 'cenário canônico: ambos conectados há 5min+' do
    it 'transiciona arrived → in_progress' do
      tracker.record_joined!('patient', at: 6.minutes.ago)
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      both_at = tracker.session.both_started_at

      described_class.new.perform(event.id, both_at.iso8601)
      expect(event.reload.status).to eq('in_progress')
    end
  end

  context 'sessão renovada (paciente saiu e voltou)' do
    it 'descarta o job antigo — both_started_at não bate' do
      tracker.record_joined!('patient', at: 10.minutes.ago)
      tracker.record_joined!('doctor', at: 10.minutes.ago)
      antigo_iso = tracker.session.both_started_at.iso8601

      tracker.record_left!('patient')
      tracker.record_joined!('patient', at: 1.minute.ago)
      # both_started_at não se renova por design (ver SessionTracker spec).
      # Mas vamos simular um caso onde mudou: forçando o jsonb.
      attrs = event.custom_attributes.deep_dup
      attrs['telemed_session']['both_started_at'] = Time.current.iso8601
      event.update!(custom_attributes: attrs)

      described_class.new.perform(event.id, antigo_iso)
      expect(event.reload.status).to eq('arrived')
    end
  end

  context 'algum participante saiu antes do timer rodar' do
    it 'não transiciona' do
      tracker.record_joined!('patient', at: 6.minutes.ago)
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      tracker.record_left!('patient')
      both_at = tracker.session.both_started_at

      described_class.new.perform(event.id, both_at.iso8601)
      expect(event.reload.status).to eq('arrived')
    end
  end

  context 'event_id inexistente' do
    it 'não levanta' do
      expect {
        described_class.new.perform(999_999, Time.current.iso8601)
      }.not_to raise_error
    end
  end

  context 'event já em completed' do
    it 'não regride (StatusTransition rejeita)' do
      tracker.record_joined!('patient', at: 6.minutes.ago)
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      both_at = tracker.session.both_started_at
      event.update!(status: 'completed')

      described_class.new.perform(event.id, both_at.iso8601)
      expect(event.reload.status).to eq('completed')
    end
  end
end
