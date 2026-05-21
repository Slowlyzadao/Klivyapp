require 'rails_helper'

RSpec.describe Telemed::MarkNoShowJob do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user, status: 'confirmed') }
  let(:tracker) { Telemed::SessionTracker.new(event) }

  context 'doutor sozinho há 5min, paciente nunca chegou' do
    it 'marca no_show' do
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      doctor_at = tracker.session.doctor_joined_at

      described_class.new.perform(event.id, doctor_at.iso8601)
      expect(event.reload.status).to eq('no_show')
    end
  end

  context 'paciente chegou em algum momento' do
    it 'não marca no_show (mesmo que tenha saído depois)' do
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      tracker.record_joined!('patient', at: 3.minutes.ago)
      tracker.record_left!('patient', at: 1.minute.ago)
      doctor_at = tracker.session.doctor_joined_at

      described_class.new.perform(event.id, doctor_at.iso8601)
      expect(event.reload.status).to eq('confirmed') # não regride pra no_show
    end
  end

  context 'doutor saiu, paciente nunca chegou — ainda marca no_show' do
    # Decisão intencional: doctor_joined_at é idempotente. Se faz 6min do
    # PRIMEIRO join do doutor e o paciente sequer apareceu, é no_show
    # mesmo que o doutor tenha entrado e saído várias vezes nesse intervalo.
    it 'preserva timestamp original e marca no_show' do
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      doctor_at = tracker.session.doctor_joined_at
      tracker.record_left!('doctor')
      tracker.record_joined!('doctor', at: 1.minute.ago)

      described_class.new.perform(event.id, doctor_at.iso8601)
      expect(event.reload.status).to eq('no_show')
    end
  end

  context 'event_id inexistente' do
    it 'não levanta' do
      expect {
        described_class.new.perform(999_999, Time.current.iso8601)
      }.not_to raise_error
    end
  end

  context 'event já em arrived (paciente chegou via outro caminho)' do
    it 'NÃO regride pra no_show — StatusTransition rejeita' do
      tracker.record_joined!('doctor', at: 6.minutes.ago)
      event.update!(status: 'arrived')
      doctor_at = tracker.session.doctor_joined_at

      described_class.new.perform(event.id, doctor_at.iso8601)
      expect(event.reload.status).to eq('arrived')
    end
  end
end
