require 'rails_helper'

# Orquestrador — Sprint K. Cobre os fluxos de joined!/left! que disparam
# transições + jobs. Os jobs em si têm specs próprios.
RSpec.describe Telemed::SessionEventHandler do
  let(:account) { create(:account) }
  let(:user)    { create(:user, account: account) }
  let(:event)   { create(:agenda_event, account: account, user: user, status: 'confirmed') }

  describe '#joined! (paciente)' do
    it 'transiciona confirmed → arrived' do
      described_class.new(event: event, role: 'patient').joined!
      expect(event.reload.status).to eq('arrived')
    end

    it 'grava patient_joined_at no jsonb' do
      described_class.new(event: event, role: 'patient').joined!
      session = Telemed::SessionTracker.new(event).session
      expect(session.patient_joined_at).to be_present
      expect(session.doctor_joined_at).to be_nil
    end

    it 'NÃO agenda MarkInProgressJob (doutor ainda não está)' do
      expect {
        described_class.new(event: event, role: 'patient').joined!
      }.not_to have_enqueued_job(Telemed::MarkInProgressJob)
    end

    it 'NÃO agenda MarkNoShowJob (esse é caminho do doutor sozinho)' do
      expect {
        described_class.new(event: event, role: 'patient').joined!
      }.not_to have_enqueued_job(Telemed::MarkNoShowJob)
    end
  end

  describe '#joined! (doutor sozinho)' do
    it 'NÃO transiciona (doutor entrar não muda status; espera paciente)' do
      described_class.new(event: event, role: 'doctor').joined!
      expect(event.reload.status).to eq('confirmed')
    end

    it 'agenda MarkNoShowJob em 5min' do
      expect {
        described_class.new(event: event, role: 'doctor').joined!
      }.to have_enqueued_job(Telemed::MarkNoShowJob)
        .with(event.id, kind_of(String))
    end
  end

  describe '#joined! (ambos)' do
    it 'agenda MarkInProgressJob quando ambos estão presentes' do
      described_class.new(event: event, role: 'patient').joined!
      expect {
        described_class.new(event: event, role: 'doctor').joined!
      }.to have_enqueued_job(Telemed::MarkInProgressJob)
        .with(event.id, kind_of(String))
    end
  end

  describe '#left!' do
    context 'antes de in_progress' do
      it 'não transiciona (consulta nem começou)' do
        event.update!(status: 'arrived')
        Telemed::SessionTracker.new(event).record_joined!('patient')
        Telemed::SessionTracker.new(event).record_joined!('doctor')

        described_class.new(event: event, role: 'patient').left!
        described_class.new(event: event, role: 'doctor').left!

        expect(event.reload.status).to eq('arrived')
      end
    end

    context 'após in_progress' do
      it 'transiciona in_progress → completed quando ambos saem' do
        event.update!(status: 'in_progress')
        tracker = Telemed::SessionTracker.new(event)
        tracker.record_joined!('patient')
        tracker.record_joined!('doctor')

        described_class.new(event: event, role: 'patient').left!
        expect(event.reload.status).to eq('in_progress') # só 1 saiu

        described_class.new(event: event, role: 'doctor').left!
        expect(event.reload.status).to eq('completed')
      end
    end
  end

  describe 'validação' do
    it 'rejeita role inválido' do
      expect {
        described_class.new(event: event, role: 'admin')
      }.to raise_error(ArgumentError)
    end
  end
end
