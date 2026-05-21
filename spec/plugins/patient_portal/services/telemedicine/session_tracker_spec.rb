require 'rails_helper'

RSpec.describe Telemed::SessionTracker do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user) }

  subject(:tracker) { described_class.new(event) }

  describe '#session em evento sem jsonb' do
    it 'retorna Session com todos nils' do
      s = tracker.session
      expect(s.doctor_joined_at).to be_nil
      expect(s.patient_joined_at).to be_nil
      expect(s.both_started_at).to be_nil
      expect(s.doctor_present?).to be(false)
      expect(s.patient_present?).to be(false)
    end
  end

  describe '#record_joined!' do
    it 'grava timestamp na primeira chamada' do
      t = Time.zone.parse('2026-05-19 10:00:00')
      tracker.record_joined!('doctor', at: t)

      session = tracker.session
      expect(session.doctor_joined_at).to be_within(1.second).of(t)
      expect(session.doctor_present?).to be(true)
    end

    it 'é idempotente — segunda chamada preserva o timestamp original' do
      t1 = Time.zone.parse('2026-05-19 10:00:00')
      t2 = Time.zone.parse('2026-05-19 10:05:00')
      tracker.record_joined!('doctor', at: t1)
      tracker.record_joined!('doctor', at: t2)

      expect(tracker.session.doctor_joined_at).to be_within(1.second).of(t1)
    end

    it 'seta both_started_at quando paciente entra depois do doutor' do
      t1 = Time.zone.parse('2026-05-19 10:00:00')
      t2 = Time.zone.parse('2026-05-19 10:02:00')
      tracker.record_joined!('doctor', at: t1)
      tracker.record_joined!('patient', at: t2)

      session = tracker.session
      expect(session.both_started_at).to be_within(1.second).of(t2)
      expect(session.both_present?).to be(true)
    end

    it 'seta both_started_at quando doutor entra depois do paciente' do
      tracker.record_joined!('patient', at: 1.minute.ago)
      tracker.record_joined!('doctor', at: Time.current)
      expect(tracker.session.both_started_at).to be_present
    end

    it 'NÃO sobrescreve both_started_at se mesmo participante reentra' do
      tracker.record_joined!('doctor', at: 5.minutes.ago)
      tracker.record_joined!('patient', at: 3.minutes.ago)
      original = tracker.session.both_started_at

      tracker.record_left!('patient')
      tracker.record_joined!('patient')
      # both_started_at não recalcula quando paciente reentra na mesma sessão
      # (já estava setado). Decisão: timer original prevalece.
      expect(tracker.session.both_started_at).to be_within(1.second).of(original)
    end

    it 'rejeita role inválido' do
      expect { tracker.record_joined!('admin') }.to raise_error(ArgumentError)
    end
  end

  describe '#record_left!' do
    it 'marca timestamp de saída' do
      tracker.record_joined!('patient')
      tracker.record_left!('patient')
      expect(tracker.session.patient_left_at).to be_present
      expect(tracker.session.patient_present?).to be(false)
    end

    it 'reentrada limpa left_at' do
      tracker.record_joined!('patient')
      tracker.record_left!('patient')
      tracker.record_joined!('patient')
      expect(tracker.session.patient_left_at).to be_nil
      expect(tracker.session.patient_present?).to be(true)
    end
  end

  describe '#session.nobody_present?' do
    it 'true quando ambos saíram' do
      tracker.record_joined!('doctor')
      tracker.record_joined!('patient')
      tracker.record_left!('doctor')
      tracker.record_left!('patient')
      expect(tracker.session.nobody_present?).to be(true)
    end

    it 'false enquanto algum ainda está presente' do
      tracker.record_joined!('doctor')
      expect(tracker.session.nobody_present?).to be(false)
    end
  end

  describe 'persistência em custom_attributes' do
    it 'grava sob a chave telemed_session' do
      tracker.record_joined!('doctor')
      event.reload
      expect(event.custom_attributes).to have_key('telemed_session')
      expect(event.custom_attributes['telemed_session']['doctor_joined_at']).to be_present
    end

    it 'preserva outras chaves de custom_attributes' do
      event.update!(custom_attributes: { 'priority' => 'high', 'foo' => 'bar' })
      tracker.record_joined!('patient')
      event.reload
      expect(event.custom_attributes['priority']).to eq('high')
      expect(event.custom_attributes['foo']).to eq('bar')
      expect(event.custom_attributes['telemed_session']).to be_present
    end
  end
end
